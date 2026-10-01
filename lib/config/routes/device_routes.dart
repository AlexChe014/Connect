import '../api_config.dart';

class DeviceRoutes {
  DeviceRoutes._();

  static const String _fcmPrefix = '/devices/fcm';
  static const String _voipPrefix = '/devices/voip';
  static const String _callPrefix = '/chat/call';

  static String get registerUrl => '${ApiConfig.baseUrl}$_fcmPrefix';

  static String get unregisterUrl => '${ApiConfig.baseUrl}$_fcmPrefix/delete';

  /// `POST /devices/voip` — PushKit VoIP-токен (только iOS).
  static String get registerVoipUrl => '${ApiConfig.baseUrl}$_voipPrefix';

  /// `POST /devices/voip/delete` — отвязать VoIP-токен при выходе.
  static String get unregisterVoipUrl =>
      '${ApiConfig.baseUrl}$_voipPrefix/delete';

  /// `POST /chat/call/{callId}/decline` — отклонение входящего звонка.
  static String declineCallUrl(String callId) =>
      '${ApiConfig.baseUrl}$_callPrefix/$callId/decline';
}
