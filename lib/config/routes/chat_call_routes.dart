import '../api_config.dart';

class ChatCallRoutes {
  ChatCallRoutes._();

  static const String _prefix = '/chat';

  /// `POST /chat/{chatId}/call/ring` — инициировать входящий звонок у собеседника.
  static String ringUrl(String chatId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/call/ring';

  /// `GET /chat/call/{callId}` — текущий статус звонка.
  static String statusUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId';

  /// `POST /chat/call/{callId}/ringing` — устройство показало входящий звонок.
  static String ringingUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId/ringing';

  /// `POST /chat/call/{callId}/accept` — собеседник принял звонок.
  static String acceptUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId/accept';

  /// `POST /chat/call/{callId}/decline` — отклонение входящего звонка.
  static String declineUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId/decline';

  /// `POST /chat/call/{callId}/end` — завершить/отменить звонок.
  static String endUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId/end';

  /// `POST /chat/call/{callId}/heartbeat` — клиент всё ещё в разговоре.
  static String heartbeatUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId/heartbeat';
}
