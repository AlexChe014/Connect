import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connect/config/call_config.dart';
import 'package:connect/models/call_conference.dart';
import 'package:connect/models/connector/connector_session.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/widgets/home_shortcut_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

/// [failed] — разговор не состоялся: собеседник так и не вошёл в комнату.
typedef JitsiLeaveCallback = void Function(String? callId, {bool failed});

/// Видеоконференция через Jitsi Meet Flutter SDK (форк в
/// packages/jitsi_meet_flutter_sdk).
///
/// Конференция рисуется не нативным экраном Jitsi, а встроенным во Flutter
/// видом ([JitsiMeetConferenceView]) внутри собственного экрана звонка
/// (CallOverlayHost): шапка, кнопки, сворачивание в окошко — наши, Jitsi
/// отвечает только за видео и звук. Состояние для экрана — [conference].
///
/// На desktop/web — fallback на браузер (SDK только Android/iOS).
class JitsiMeetingService extends ChangeNotifier {
  JitsiMeetingService._();
  static final JitsiMeetingService instance = JitsiMeetingService._();

  /// Брендинг Jitsi через `dynamicBrandingUrl` (см. config.js в исходниках
  /// jitsi-meet, раздел "External API url used to receive branding specific
  /// information"). Отдаём как data:-URI, без отдельного хостинга под JSON.
  ///
  /// Нативный SDK из этого JSON учитывает только `avatarBackgrounds`
  /// (middleware.native.ts → base/avatar/functions.ts:getAvatarColor) —
  /// цвет кружка-аватарки участника с выключенной камерой в плитках Jitsi.
  /// Остальные поля (`customTheme`, `logoImageUrl`, `backgroundColor`)
  /// читает только веб-клиент.
  static final String _brandingDataUri = () {
    final json = jsonEncode({
      'avatarBackgrounds': ['#1677FF'],
    });
    return 'data:application/json;base64,${base64Encode(utf8.encode(json))}';
  }();

  /// Тип служебного сообщения между нашими приложениями о камере и
  /// микрофоне (Jitsi не сообщает о чужой камере). По нему 1:1 без видео
  /// показывает экран с аватаром вместо пустого кадра.
  static const String _stateMessageType = 'connect.call-state';

  final JitsiMeet _jitsi = JitsiMeet();
  bool _joining = false;
  String? _activeCallId;
  bool _endWhenLeave = false;
  bool _leaveNotified = false;
  bool _inConference = false;
  bool _peerJoined = false;
  Timer? _peerJoinTimer;
  Timer? _peerRejoinTimer;
  Timer? _closeTimer;
  JitsiLeaveCallback? _onLeave;
  VoidCallback? _releaseHomeSuppress;
  CallConference? _conference;

  /// Текущая конференция для экрана звонка; `null` — звонка нет.
  CallConference? get conference => _conference;

  /// Экран конференции открыт (от входа до выхода/закрытия).
  bool get isInConference => _conference != null || _joining;

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// [title]/[avatarUrl] — собеседник 1:1 для экрана звонка; без них
  /// берётся тема встречи или имя первого вошедшего участника.
  Future<void> joinSession(
    ConnectorSession session, {
    String? callId,
    bool endWhenLeave = false,
    JitsiLeaveCallback? onLeave,
    String? title,
    String? avatarUrl,
  }) async {
    final room = session.room.trim();
    if (room.isEmpty) {
      throw ApiException(500, 'Сервер не вернул комнату конференции');
    }

    final server = session.jitsiServerUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (server.isEmpty) {
      throw ApiException(500, 'Сервер не вернул адрес Jitsi');
    }

    if (!isSupported) {
      await _openInBrowser(session);
      return;
    }

    final current = _conference;
    if (current != null &&
        current.room == room &&
        current.phase != CallPhase.ending) {
      // Уже в этой комнате (например, «Присоединиться» на плашке чата при
      // свёрнутом звонке) — просто разворачиваем.
      expand();
      return;
    }

    if (_joining) return;
    _joining = true;

    try {
      if (current != null) await _leaveCurrent();

      final granted = await CallPermissions.ensureMediaOnly();
      if (!granted) {
        throw ApiException(
          403,
          'Нужен доступ к камере и микрофону для видеоконференции',
        );
      }

      _activeCallId = callId;
      _endWhenLeave = endWhenLeave;
      _onLeave = onLeave;
      _leaveNotified = false;
      _inConference = false;
      _peerJoined = false;
      _peerJoinTimer?.cancel();
      _peerRejoinTimer?.cancel();
      _closeTimer?.cancel();

      // Кнопка "на главный экран" скрыта всё время звонка: под свёрнутым
      // окошком звонка ей не место, а полноэкранный звонок её перекрывает.
      _releaseHomeSuppress?.call();
      _releaseHomeSuppress = HomeShortcutButton.suppress();

      // Снимаем фокус с полей ввода Flutter (обычно — поле сообщения в чате):
      // иначе клавиатура всплывает поверх звонка (в т.ч. при возврате из
      // фона после ответа через CallKit).
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

      final topic = session.topic?.trim();
      final options = JitsiMeetConferenceOptions(
        serverURL: server,
        room: room,
        token: session.jwt,
        userInfo: session.displayName != null && session.displayName!.isNotEmpty
            ? JitsiMeetUserInfo(displayName: session.displayName)
            : null,
        configOverrides: {
          // Камера и микрофон при входе в звонок всегда выключены — участник
          // включает их сам, если нужно (и в 1:1, и в групповом звонке).
          'startWithAudioMuted': true,
          'startWithVideoMuted': true,
          'disableInviteFunctions': true,
          'hideConferenceSubject': true,
          'prejoinConfig': {'enabled': false},
          'defaultLanguage': 'ru',
          'subject': topic ?? '',
          'dynamicBrandingUrl': _brandingDataUri,
          // Окошко с собственным видео: Jitsi запоминает выключенный
          // self-view локально между звонками — явно включаем.
          'disableSelfView': false,
          'disableProfile': true,
        },
        featureFlags: {
          // Звонком уже управляет наш flutter_callkit_incoming (см.
          // incoming_call_service.dart и AppDelegate.swift) — если оставить
          // и встроенную CallKit-интеграцию Jitsi, две системы конфликтуют
          // и обычное завершение звонка показывается как "Встреча прервана".
          'call-integration.enabled': false,
          // Панель кнопок, шапка, таймер и PiP Jitsi не нужны — всё это
          // рисует наш экран звонка. Jitsi остаётся видео: большой кадр
          // говорящего и окошко своего видео (filmstrip).
          'toolbox.enabled': false,
          'conference-timer.enabled': false,
          'meeting-name.enabled': false,
          'pip.enabled': false,
          // Иначе Jitsi включает immersive-режим и прячет системные панели
          // у всего приложения — конференция теперь внутри MainActivity.
          'fullscreen.enabled': false,
          // Всплывашки Jitsi («X вошёл», «Вас не слышно») — в его стиле
          // поверх нашего экрана; о входе/выходе сообщает наш экран.
          'notifications.enabled': false,
          'filmstrip.enabled': true,
          'tile-view.enabled': false,
          'car-mode.enabled': false,
          'unsaferoomwarning.enabled': false,
          'add-people.enabled': false,
          'invite.enabled': false,
          'welcomepage.enabled': false,
          'prejoinpage.enabled': false,
          'live-streaming.enabled': false,
          'recording.enabled': false,
          'calendar.enabled': false,
          'help.enabled': false,
          'lobby-mode.enabled': false,
          'meeting-password.enabled': false,
          'security-options.enabled': false,
          'server-url-change.enabled': false,
          'speakerstats.enabled': false,
          'breakout-rooms.enabled': false,
          'close-captions.enabled': false,
          // Чат Jitsi открывается с нашей кнопки «Чат» во встрече.
          'chat.enabled': !endWhenLeave,
          'android.screensharing.enabled': !endWhenLeave,
          'video-share.enabled': false,
        },
      );

      _jitsi.setListener(_buildListener());
      _conference = CallConference(
        options: options,
        room: room,
        title:
            _firstNonEmpty([title, topic]) ??
            (endWhenLeave ? '' : 'Видеовстреча'),
        avatarUrl: avatarUrl,
        isDirect: endWhenLeave,
      );
      notifyListeners();
    } catch (e) {
      _releaseHomeSuppress?.call();
      _releaseHomeSuppress = null;
      rethrow;
    } finally {
      _joining = false;
    }
  }

  JitsiMeetEventListener _buildListener() {
    return JitsiMeetEventListener(
      conferenceJoined: (url) {
        AppLogger.d('Jitsi joined: $url', name: 'meeting');
        _inConference = true;
        final c = _conference;
        if (c == null) return;
        if (c.isDirect) {
          if (!_peerJoined) c.phase = CallPhase.waiting;
        } else {
          c.phase = CallPhase.active;
          c.startedAt ??= DateTime.now();
        }
        if (_endWhenLeave && !_peerJoined) _armPeerJoinWatchdog();
        unawaited(_jitsi.refreshAudioRoute());
        notifyListeners();
      },
      participantJoined: (email, name, role, participantId) {
        // До conferenceJoined может прийти событие о нас самих.
        if (!_inConference) return;
        final c = _conference;
        final id = participantId?.trim() ?? '';
        if (c == null || id.isEmpty) return;
        final displayName = name?.trim() ?? '';
        final participant = c.participants.putIfAbsent(
          id,
          () => CallParticipant(id: id, name: displayName),
        );
        if (displayName.isNotEmpty) participant.name = displayName;
        if (c.title.isEmpty && displayName.isNotEmpty) c.title = displayName;

        _peerJoined = true;
        _peerJoinTimer?.cancel();
        _peerRejoinTimer?.cancel();
        if (c.phase != CallPhase.ending) c.phase = CallPhase.active;
        c.startedAt ??= DateTime.now();
        _sendState(to: id);
        notifyListeners();
      },
      participantLeft: (participantId) {
        final c = _conference;
        if (c != null && participantId != null) {
          c.participants.remove(participantId);
        }
        if (!_endWhenLeave) {
          notifyListeners();
          return;
        }
        // Обычное завершение собеседником приходит пушем/вебхуком сразу;
        // здесь ждём — это может быть реконнект (смена сети), см.
        // CallConfig.peerRejoinGrace.
        AppLogger.d(
          'Jitsi participantLeft: $participantId — waiting for rejoin',
          name: 'meeting',
        );
        if (c != null &&
            c.participants.isEmpty &&
            c.phase == CallPhase.active) {
          c.phase = CallPhase.reconnecting;
        }
        notifyListeners();
        _peerRejoinTimer?.cancel();
        _peerRejoinTimer = Timer(CallConfig.peerRejoinGrace, () {
          if (_leaveNotified) return;
          AppLogger.d(
            'Jitsi: peer did not return — ending 1:1 call',
            name: 'meeting',
          );
          _notifyLeft();
          // ignore: discarded_futures
          hangUp();
        });
      },
      audioMutedChanged: (muted) {
        final c = _conference;
        if (c == null) return;
        c.audioMuted = muted;
        _sendState();
        notifyListeners();
      },
      videoMutedChanged: (muted) {
        final c = _conference;
        if (c == null) return;
        c.videoMuted = muted;
        _sendState();
        notifyListeners();
      },
      endpointTextMessageReceived: (senderId, message) {
        _onStateMessage(senderId, message);
      },
      screenShareToggled: (participantId, sharing) {
        final c = _conference;
        // Событие приходит и о чужих демонстрациях — свою узнаём по тому,
        // что это не кто-то из собеседников.
        if (c == null || c.participants.containsKey(participantId)) return;
        c.screenSharing = sharing;
        notifyListeners();
      },
      chatMessageReceived: (senderId, message, isPrivate, timestamp) {
        final c = _conference;
        if (c == null || c.chatOpen) return;
        c.unreadChat++;
        notifyListeners();
      },
      chatToggled: (isOpen) {
        final c = _conference;
        if (c == null) return;
        c.chatOpen = isOpen;
        if (isOpen) c.unreadChat = 0;
        notifyListeners();
      },
      audioRouteChanged: (route, available) {
        final c = _conference;
        if (c == null) return;
        c.audioRoute = CallAudioRoute.parse(route);
        c.availableRoutes = available
            .map(CallAudioRoute.parse)
            .where((r) => r != CallAudioRoute.unknown)
            .toList();
        notifyListeners();
      },
      conferenceTerminated: (url, error) {
        AppLogger.d('Jitsi terminated: $url error=$error', name: 'meeting');
        _notifyLeft();
        // Обычно следом приходит readyToClose; если нет — закрываемся сами.
        _scheduleClose(const Duration(milliseconds: 1500));
      },
      readyToClose: () {
        AppLogger.d('Jitsi readyToClose', name: 'meeting');
        _notifyLeft();
        _scheduleClose(const Duration(milliseconds: 700));
      },
    );
  }

  // --- Кнопки экрана звонка ---

  Future<void> toggleMicrophone() async {
    final c = _conference;
    if (c == null) return;
    c.audioMuted = !c.audioMuted;
    notifyListeners();
    await _jitsi.setAudioMuted(c.audioMuted);
  }

  Future<void> toggleCamera() async {
    final c = _conference;
    if (c == null) return;
    c.videoMuted = !c.videoMuted;
    notifyListeners();
    await _jitsi.setVideoMuted(c.videoMuted);
  }

  Future<void> flipCamera() => _jitsi.toggleCamera();

  Future<void> setAudioRoute(CallAudioRoute route) =>
      _jitsi.setAudioRoute(route.name);

  /// Системный выбор устройства (iOS): AirPods, машина, динамик…
  Future<void> showAudioRoutePicker() => _jitsi.setAudioRoute('picker');

  Future<void> toggleScreenShare() async {
    final c = _conference;
    if (c == null) return;
    await _jitsi.toggleScreenShare(!c.screenSharing);
  }

  Future<void> openChat() async {
    final c = _conference;
    if (c == null) return;
    c.unreadChat = 0;
    notifyListeners();
    await _jitsi.openChat();
  }

  void minimize() {
    final c = _conference;
    if (c == null || c.minimized || c.phase == CallPhase.ending) return;
    c.minimized = true;
    notifyListeners();
  }

  void expand() {
    final c = _conference;
    if (c == null || !c.minimized) return;
    c.minimized = false;
    notifyListeners();
  }

  Future<void> hangUp() async {
    final c = _conference;
    if (c != null && c.phase != CallPhase.ending) {
      c.phase = CallPhase.ending;
      notifyListeners();
    }
    try {
      await _jitsi.hangUp();
    } catch (e, st) {
      AppLogger.d(
        'Jitsi hangUp failed',
        name: 'meeting',
        error: e,
        stackTrace: st,
      );
    }
    // Нет readyToClose (сеть пропала, SDK завис) — не держим экран.
    if (c != null) {
      _scheduleClose(const Duration(seconds: 3), onlyIfLater: true);
    }
  }

  /// Перед входом в другую комнату: выйти из текущей и дождаться закрытия.
  Future<void> _leaveCurrent() async {
    await hangUp();
    _notifyLeft();
    _closeNow();
  }

  /// 1:1: собеседник принял звонок, но так и не вошёл в комнату (упало
  /// приложение, нет сети, отказ в правах) — не держим пользователя одного.
  void _armPeerJoinWatchdog() {
    _peerJoinTimer?.cancel();
    _peerJoinTimer = Timer(CallConfig.peerJoinTimeout, () {
      if (_peerJoined || _leaveNotified) return;
      AppLogger.d(
        'Jitsi: peer never joined in ${CallConfig.peerJoinTimeout} — ending',
        name: 'meeting',
      );
      _notifyLeft(failed: true);
      // ignore: discarded_futures
      hangUp();
    });
  }

  void _notifyLeft({bool failed = false}) {
    if (_leaveNotified) return;
    _leaveNotified = true;
    _inConference = false;
    _peerJoinTimer?.cancel();
    _peerJoinTimer = null;
    _peerRejoinTimer?.cancel();
    _peerRejoinTimer = null;
    _releaseHomeSuppress?.call();
    _releaseHomeSuppress = null;
    final callId = _activeCallId;
    final cb = _onLeave;
    _activeCallId = null;
    _onLeave = null;
    if (_endWhenLeave) {
      cb?.call(callId, failed: failed);
    }
  }

  DateTime? _closeAt;

  /// Показать «Звонок завершён» и убрать экран (вместе с ним уходит и
  /// встроенный вид Jitsi — нативная часть выходит из комнаты).
  void _scheduleClose(Duration delay, {bool onlyIfLater = false}) {
    final c = _conference;
    if (c == null) return;
    final at = DateTime.now().add(delay);
    if (onlyIfLater && _closeAt != null && _closeAt!.isBefore(at)) return;
    if (c.phase != CallPhase.ending) {
      c.phase = CallPhase.ending;
      notifyListeners();
    }
    _closeAt = at;
    _closeTimer?.cancel();
    _closeTimer = Timer(delay, _closeNow);
  }

  void _closeNow() {
    _closeTimer?.cancel();
    _closeTimer = null;
    _closeAt = null;
    if (_conference == null) return;
    _conference = null;
    _jitsi.setListener(null);
    notifyListeners();
  }

  /// Сообщаем собеседникам (нашим приложениям) про свои камеру и микрофон.
  void _sendState({String? to}) {
    final c = _conference;
    if (c == null || !_inConference || c.participants.isEmpty) return;
    final message = jsonEncode({
      'type': _stateMessageType,
      'video': !c.videoMuted,
      'audio': !c.audioMuted,
    });
    unawaited(_jitsi.sendEndpointTextMessage(to: to, message: message));
  }

  void _onStateMessage(String senderId, String message) {
    final c = _conference;
    if (c == null) return;
    Object? decoded;
    try {
      decoded = jsonDecode(message);
    } catch (_) {
      return;
    }
    if (decoded is! Map || decoded['type'] != _stateMessageType) return;
    final participant = c.participants.putIfAbsent(
      senderId,
      () => CallParticipant(id: senderId, name: ''),
    );
    final video = decoded['video'];
    final audio = decoded['audio'];
    if (video is bool) participant.videoOn = video;
    if (audio is bool) participant.audioOn = audio;
    notifyListeners();
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  Future<void> _openInBrowser(ConnectorSession session) async {
    final jwt = session.jwt?.trim();
    final room = session.room.trim();
    final server = session.jitsiServerUrl.trim().replaceAll(RegExp(r'/+$'), '');

    Uri? uri;
    if (jwt != null && jwt.isNotEmpty && room.isNotEmpty && server.isNotEmpty) {
      uri = Uri.parse(
        '$server/$room',
      ).replace(queryParameters: {'jwt': jwt, 'lang': 'ru'});
    } else {
      final public = session.publicUrl.trim();
      if (public.isNotEmpty) uri = Uri.tryParse(public);
    }

    if (uri == null) {
      throw ApiException(500, 'Некорректная ссылка на конференцию');
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw ApiException(500, 'Не удалось открыть конференцию');
    }
  }
}
