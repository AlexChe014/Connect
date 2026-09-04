import '../api_config.dart';

class ChatCallRoutes {
  ChatCallRoutes._();

  static const String _prefix = '/chat';

  /// `POST /chat/{chatId}/call/ring` — инициировать входящий звонок у собеседника.
  static String ringUrl(String chatId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/call/ring';

  /// `POST /chat/call/{callId}/end` — завершить/отменить звонок.
  static String endUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId/end';

  /// `POST /chat/call/{callId}/accept` — собеседник принял звонок.
  static String acceptUrl(String callId) =>
      '${ApiConfig.baseUrl}$_prefix/call/$callId/accept';
}
