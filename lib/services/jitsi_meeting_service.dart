import 'dart:async';
import 'dart:io';

import 'package:connect/models/connector/connector_session.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/branding_service.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/widgets/home_shortcut_button.dart';
import 'package:flutter/foundation.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

typedef JitsiLeaveCallback = void Function(String? callId);

/// Запуск видеоконференции через Jitsi Meet Flutter SDK.
///
/// На desktop/web — fallback на браузер (SDK только Android/iOS).
class JitsiMeetingService {
  JitsiMeetingService._();
  static final JitsiMeetingService instance = JitsiMeetingService._();

  final JitsiMeet _jitsi = JitsiMeet();

  /// true, пока нативный экран звонка Jitsi показан поверх Flutter — от
  /// успешного join() (экран открылся) до реального завершения звонка в
  /// _notifyLeft() (а не от Future join(), который резолвится сразу при
  /// показе экрана). Слушают AppNavigationService/main.dart, чтобы не
  /// затирать Flutter-навигацию pushNamedAndRemoveUntil из push-уведомлений,
  /// пока пользователь всё ещё в звонке — иначе после звонка можно
  /// оказаться на случайном экране вместо того, откуда звонили.
  static final ValueNotifier<bool> isInCall = ValueNotifier(false);

  bool _joining = false;
  String? _activeCallId;
  bool _endWhenLeave = false;
  bool _leaveNotified = false;
  JitsiLeaveCallback? _onLeave;
  final Set<String> _remoteParticipantIds = {};
  Timer? _participantLeftGraceTimer;

  /// Сколько ждём перед тем, как считать participantLeft настоящим уходом
  /// собеседника: SDK Jitsi иногда шлёт participantLeft/participantJoined
  /// подряд для одного и того же участника при переключении JVB → P2P сразу
  /// после подключения второго человека к 1:1 звонку — без этой паузы такое
  /// переключение выглядело бы как "собеседник положил трубку" и рвало
  /// звонок сразу после ответа.
  static const _participantLeftGrace = Duration(seconds: 3);

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<void> joinSession(
    ConnectorSession session, {
    String? callId,
    bool endWhenLeave = false,
    JitsiLeaveCallback? onLeave,
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

    if (_joining) return;
    _joining = true;
    _activeCallId = callId;
    _endWhenLeave = endWhenLeave;
    _onLeave = onLeave;
    _leaveNotified = false;
    _remoteParticipantIds.clear();
    _participantLeftGraceTimer?.cancel();
    _participantLeftGraceTimer = null;

    // Скрываем кнопку "на главный экран" сразу, до запроса разрешений —
    // иначе она успевает мелькнуть, пока ждём ответ CallPermissions, а после
    // hangUp() остаётся включена под нативным UI Jitsi и сразу проявляется.
    HomeShortcutButton.suppressed.value = true;

    try {
      final granted = await CallPermissions.ensureMediaOnly();
      if (!granted) {
        throw ApiException(
          403,
          'Нужен доступ к камере и микрофону для видеоконференции',
        );
      }

      // BrandingService отдаёт light_logo с сервера как абсолютный URL — он
      // и нужен нативному UI Jitsi (defaultLogoUrl грузится не из Flutter-
      // ассетов, а самим Jitsi по сети). Пока URL не подтянулся, просто не
      // переопределяем — Jitsi покажет свой водяной знак по умолчанию.
      final logoUrl = BrandingService.instance.logoUrl?.trim();

      final options = JitsiMeetConferenceOptions(
        serverURL: server,
        room: room,
        token: session.jwt,
        userInfo: session.displayName != null && session.displayName!.isNotEmpty
            ? JitsiMeetUserInfo(displayName: session.displayName)
            : null,
        configOverrides: {
          'startWithAudioMuted': true,
          'startWithVideoMuted': true,
          'disableInviteFunctions': true,
          'hideConferenceSubject': true,
          'prejoinConfig': {'enabled': false},
          'defaultLanguage': 'ru',
          'subject': session.topic ?? '',
          // Косметика под наш брендинг — не трогает поведение звонка.
          if (logoUrl != null && logoUrl.isNotEmpty) 'defaultLogoUrl': logoUrl,
          'defaultLocalDisplayName': 'Вы',
          'hideDominantSpeakerBadge': true,
          'backgroundAlpha': 0.6,
          'toolbarConfig': {'backgroundColor': 'rgba(17, 24, 39, 0.85)'},
          'filmstrip': {'initialWidth': 120},
          // Вкладка профиля — не "устройства"/"язык", прячем как вторичную
          // настройку и в 1:1, и в групповом звонке.
          'disableProfile': true,
          // 1:1 — только завершение (настройки/участники/чат скрыты).
          // Групповой звонок — базовый набор кнопок Jitsi; панель участников
          // видна всем, но управление ими (kick-out и т.п.) Jitsi показывает
          // только модератору автоматически.
          // 'desktop' (демонстрация экрана) временно отключена во всех
          // звонках — закомментирована, а не удалена, чтобы легко вернуть.
          'toolbarButtons': endWhenLeave
              ? const [
                  'microphone',
                  'camera',
                  'toggle-camera',
                  // 'desktop',
                  'hangup',
                ]
              : const [
                  'microphone',
                  'camera',
                  'toggle-camera',
                  // 'desktop',
                  'chat',
                  'raisehand',
                  'reactions',
                  'tileview',
                  'fullscreen',
                  'videoquality',
                  'participants-pane',
                  'settings',
                  'stats',
                  'shortcuts',
                  'select-background',
                  'hangup',
                ],
        },
        featureFlags: {
          // Звонком уже управляет наш flutter_callkit_incoming (см.
          // incoming_call_service.dart и AppDelegate.swift) — если оставить
          // и встроенную CallKit-интеграцию Jitsi, две системы конфликтуют
          // и обычное завершение звонка показывается как "Встреча прервана".
          'call-integration.enabled': false,
          'toggle-camera.enabled': true,
          'unsaferoomwarning.enabled': false,
          'add-people.enabled': false,
          'invite.enabled': false,
          'welcomepage.enabled': false,
          'live-streaming.enabled': false,
          'recording.enabled': !endWhenLeave,
          'toolbox.enabled': true,
          'toolbox.alwaysVisible': true,
          'calendar.enabled': false,
          'help.enabled': false,
          // Управление участниками (кикнуть и т.п.) — доступно только
          // модератору, Jitsi сам скрывает эти действия от остальных.
          'kick-out.enabled': !endWhenLeave,
          'lobby-mode.enabled': false,
          'meeting-name.enabled': false,
          'meeting-password.enabled': false,
          'security-options.enabled': false,
          'server-url-change.enabled': false,
          'speakerstats.enabled': false,
          'breakout-rooms.enabled': false,
          'close-captions.enabled': false,
          'raise-hand.enabled': !endWhenLeave,
          'reactions.enabled': !endWhenLeave,
          'tile-view.enabled': !endWhenLeave,
          'participants-pane.enabled': !endWhenLeave,
          'settings.enabled': !endWhenLeave,
          'chat.enabled': !endWhenLeave,
          'overflow-menu.enabled': !endWhenLeave,
          // Демонстрация экрана временно отключена (см. toolbarButtons выше).
          // 'video-share.enabled': true,
          'video-share.enabled': false,
          // filmstrip — не только миниатюры других участников, но и
          // собственное превью (self-view) поверх видео собеседника, поэтому
          // включаем всегда, а не только в групповых звонках.
          'filmstrip.enabled': true,
        },
      );

      final response = await _jitsi.join(
        options,
        JitsiMeetEventListener(
          conferenceJoined: (url) {
            AppLogger.d('Jitsi joined: $url', name: 'meeting');
          },
          conferenceTerminated: (url, error) {
            AppLogger.d(
              'Jitsi terminated: $url error=$error',
              name: 'meeting',
            );
            _notifyLeft();
          },
          readyToClose: () {
            AppLogger.d('Jitsi readyToClose', name: 'meeting');
            _notifyLeft();
          },
          participantJoined: (email, name, role, participantId) {
            if (!_endWhenLeave || participantId == null) return;
            _remoteParticipantIds.add(participantId);
            // Собеседник снова в комнате (например, после JVB → P2P
            // переключения) — отменяем отложенное завершение звонка.
            _participantLeftGraceTimer?.cancel();
            _participantLeftGraceTimer = null;
          },
          participantLeft: (participantId) {
            if (!_endWhenLeave) return;
            if (participantId != null) {
              _remoteParticipantIds.remove(participantId);
            }
            AppLogger.d(
              'Jitsi participantLeft: $participantId, remaining=$_remoteParticipantIds',
              name: 'meeting',
            );
            // Не рвём звонок по первому participantLeft: SDK может прислать
            // его как часть JVB → P2P переключения сразу после ответа
            // собеседника, а через мгновение — participantJoined с тем же
            // ID. Ждём немного и завершаем, только если никто не вернулся.
            _participantLeftGraceTimer?.cancel();
            _participantLeftGraceTimer = Timer(_participantLeftGrace, () {
              if (_remoteParticipantIds.isNotEmpty) return;
              AppLogger.d(
                'Jitsi participantLeft confirmed after grace period — ending 1:1 call',
                name: 'meeting',
              );
              _notifyLeft();
              // ignore: discarded_futures
              hangUp();
            });
          },
        ),
      );

      if (!response.isSuccess) {
        throw ApiException(
          500,
          response.message?.trim().isNotEmpty == true
              ? response.message!
              : 'Не удалось открыть видеоконференцию',
        );
      }
      isInCall.value = true;
    } catch (e) {
      HomeShortcutButton.suppressed.value = false;
      rethrow;
    } finally {
      _joining = false;
    }
  }

  Future<void> hangUp() async {
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
  }

  void _notifyLeft() {
    if (_leaveNotified) return;
    _leaveNotified = true;
    isInCall.value = false;
    _participantLeftGraceTimer?.cancel();
    _participantLeftGraceTimer = null;
    _remoteParticipantIds.clear();
    // Не снимаем скрытие сразу: если звонили из того же экрана, глубина
    // стека не изменилась, и кнопка тут же "выскочила" бы после звонка.
    // Держим её скрытой до следующей настоящей навигации.
    HomeShortcutButton.suppressUntilNextNavigation();
    final callId = _activeCallId;
    final cb = _onLeave;
    _activeCallId = null;
    _onLeave = null;
    if (_endWhenLeave) {
      cb?.call(callId);
    }
  }

  Future<void> _openInBrowser(ConnectorSession session) async {
    final jwt = session.jwt?.trim();
    final room = session.room.trim();
    final server = session.jitsiServerUrl.trim().replaceAll(RegExp(r'/+$'), '');

    Uri? uri;
    if (jwt != null && jwt.isNotEmpty && room.isNotEmpty && server.isNotEmpty) {
      uri = Uri.parse('$server/$room').replace(
        queryParameters: {'jwt': jwt, 'lang': 'ru'},
      );
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
