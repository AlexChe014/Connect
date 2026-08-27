import 'dart:io';

import 'package:connect/models/connector/connector_session.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Запуск видеоконференции через Jitsi Meet Flutter SDK.
///
/// На desktop/web — fallback на браузер (SDK только Android/iOS).
class JitsiMeetingService {
  JitsiMeetingService._();
  static final JitsiMeetingService instance = JitsiMeetingService._();

  final JitsiMeet _jitsi = JitsiMeet();
  bool _joining = false;

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<void> joinSession(ConnectorSession session) async {
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

    try {
      final granted = await _ensureMediaPermissions();
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
          'startWithAudioMuted': true,
          'startWithVideoMuted': true,
          'disableInviteFunctions': true,
          'hideConferenceSubject': true,
          'prejoinConfig': {'enabled': false},
          'defaultLanguage': 'ru',
          'subject': session.topic ?? '',
        },
        featureFlags: {
          'unsaferoomwarning.enabled': false,
          'add-people.enabled': false,
          'invite.enabled': false,
          'welcomepage.enabled': false,
          'live-streaming.enabled': false,
          'recording.enabled': true,
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
          },
          readyToClose: () {
            AppLogger.d('Jitsi readyToClose', name: 'meeting');
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

  Future<bool> _ensureMediaPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    return (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);
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
