import 'dart:io';

import 'package:connect/models/connector/connector_session.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/utils/app_logger.dart';
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
  bool _joining = false;
  String? _activeCallId;
  bool _endWhenLeave = false;
  bool _leaveNotified = false;
  JitsiLeaveCallback? _onLeave;

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

      final options = JitsiMeetConferenceOptions(
        serverURL: server,
        room: room,
        token: session.jwt,
        userInfo: session.displayName != null && session.displayName!.isNotEmpty
            ? JitsiMeetUserInfo(displayName: session.displayName)
            : null,
        configOverrides: {
          'startWithAudioMuted': false,
          'startWithVideoMuted': false,
          'disableInviteFunctions': true,
          'hideConferenceSubject': true,
          'prejoinConfig': {'enabled': false},
          'defaultLanguage': 'ru',
          'subject': session.topic ?? '',
          if (endWhenLeave) 'disableProfile': true,
        },
        featureFlags: {
          'unsaferoomwarning.enabled': false,
          'add-people.enabled': false,
          'invite.enabled': false,
          'welcomepage.enabled': false,
          'live-streaming.enabled': false,
          'recording.enabled': !endWhenLeave,
          'toolbox.enabled': true,
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
