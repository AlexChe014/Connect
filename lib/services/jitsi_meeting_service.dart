import 'dart:convert';
import 'dart:io';

import 'package:connect/models/connector/connector_session.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/services/crash_reporting_service.dart';
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

  /// Брендинг Jitsi через `dynamicBrandingUrl` (см. config.js в исходниках
  /// jitsi-meet, раздел "External API url used to receive branding specific
  /// information"). Отдаём как data:-URI, без отдельного хостинга под JSON.
  ///
  /// ВАЖНО: бо́льшая часть полей этого JSON (`customTheme` — акцентные
  /// цвета кнопок, `logoImageUrl` — водяной знак, `backgroundColor` — фон
  /// видео) в исходниках jitsi-meet обрабатывается только веб-клиентом
  /// (react/features/dynamic-branding/middleware.web.ts,
  /// .../base/react/components/web/Watermarks.tsx) — у нативного
  /// iOS/Android SDK, которым пользуется наше приложение, нет своего кода,
  /// который бы их читал, поэтому там эти поля молча игнорируются.
  /// Единственное поле, которое нативный SDK реально учитывает
  /// (middleware.native.ts → base/avatar/functions.ts:getAvatarColor) —
  /// `avatarBackgrounds`: цвет кружка-аватарки участника, когда у него
  /// выключена камера. Красим его в синий приложения — с учётом, что
  /// камера/микрофон теперь по умолчанию выключены, аватарку будет видно
  /// почти в каждом звонке.
  static final String _brandingDataUri = () {
    final json = jsonEncode({
      'avatarBackgrounds': ['#1677FF'],
    });
    return 'data:application/json;base64,${base64Encode(utf8.encode(json))}';
  }();

  final JitsiMeet _jitsi = JitsiMeet();
  bool _joining = false;
  String? _activeCallId;
  bool _endWhenLeave = false;
  bool _leaveNotified = false;
  JitsiLeaveCallback? _onLeave;
  VoidCallback? _releaseHomeSuppress;

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

    try {
      final granted = await CallPermissions.ensureMediaOnly();
      if (!granted) {
        throw ApiException(
          403,
          'Нужен доступ к камере и микрофону для видеоконференции',
        );
      }

      // Скрываем кнопку "на главный экран" на всё время звонка, а не только
      // на экране "Звоним…" — иначе после hangUp() она уже включена под
      // нативным UI Jitsi и сразу проявляется.
      _releaseHomeSuppress?.call();
      _releaseHomeSuppress = HomeShortcutButton.suppress();

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
          'subject': session.topic ?? '',
          'dynamicBrandingUrl': _brandingDataUri,
          // Явно гарантируем, что окошко с собственным видео не спрятано —
          // в групповом звонке настройки доступны пользователю (settings.
          // enabled ниже), и он мог сам выключить self-view в прошлый раз;
          // Jitsi запоминает этот выбор локально между звонками.
          'disableSelfView': false,
          // Вкладка профиля — не "устройства"/"язык", прячем как вторичную
          // настройку и в 1:1, и в групповом звонке.
          'disableProfile': true,
          // 1:1 — только завершение (настройки/участники/чат скрыты).
          // Групповой звонок — базовый набор кнопок Jitsi; панель участников
          // видна всем, но управление ими (kick-out и т.п.) Jitsi показывает
          // только модератору автоматически.
          'toolbarButtons': endWhenLeave
              ? const [
                  'microphone',
                  'camera',
                  'toggle-camera',
                  'desktop',
                  'hangup',
                ]
              : const [
                  'microphone',
                  'camera',
                  'toggle-camera',
                  'desktop',
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
          'video-share.enabled': true,
          // Filmstrip — это не только миниатюры остальных участников, но и
          // окошко с собственным видео (self-view). Раньше в 1:1-звонке
          // (endWhenLeave=true) filmstrip целиком выключался, чтобы не
          // показывать дублирующую миниатюру собеседника — но тем самым
          // пропадало и окошко "видишь себя". Включаем всегда; миниатюры
          // остальных участников в 1:1 всё равно не нужны — их там просто
          // нет (собеседник и так на весь экран).
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
          participantLeft: (participantId) {
            if (!_endWhenLeave) return;
            AppLogger.d(
              'Jitsi participantLeft: $participantId — ending 1:1 call',
              name: 'meeting',
            );
            _notifyLeft();
            // ignore: discarded_futures
            hangUp();
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
    } catch (e, st) {
      _releaseHomeSuppress?.call();
      _releaseHomeSuppress = null;
      // Нефатально: следим в проде за сбоями входа в конференцию — в
      // частности, чтобы подтвердить, что на Android больше не всплывает
      // NPE из WrapperJitsiMeetActivity.launch(activity!!, ...) при Accept
      // из полностью убитого приложения (см. IncomingCallService).
      CrashReportingService.recordNonFatal(e, st, reason: 'jitsi_join_failed');
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
    _releaseHomeSuppress?.call();
    _releaseHomeSuppress = null;
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
