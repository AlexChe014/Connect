import '../api_config.dart';

class ChatCallRoutes {
  ChatCallRoutes._();

  static const String _prefix = '/chat';

  /// `POST /chat/{chatId}/call/ring` — инициировать входящий звонок у собеседника.
  static String ringUrl(String chatId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/call/ring';
}
