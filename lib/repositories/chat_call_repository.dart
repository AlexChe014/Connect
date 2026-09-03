import 'package:connect/config/routes/chat_call_routes.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/utils/app_logger.dart';

class ChatCallRepository {
  ChatCallRepository._();
  static final ChatCallRepository instance = ChatCallRepository._();

  /// Просит бэкенд отправить VoIP/FCM push собеседнику.
  ///
  /// Бэкенд создаёт `call_id`, шлёт push `type: chat_call` и возвращает 200.
  Future<void> ringDirectCall({
    required String chatId,
    required String room,
    String? topic,
  }) async {
    try {
      await ApiClient.instance.post(
        ChatCallRoutes.ringUrl(chatId),
        body: {
          'room': room,
          if (topic != null && topic.isNotEmpty) 'topic': topic,
        },
      );
    } catch (e, st) {
      AppLogger.d(
        'ringDirectCall failed (endpoint may be unavailable): $e',
        name: 'chat.call',
        error: e,
        stackTrace: st,
      );
    }
  }
}
