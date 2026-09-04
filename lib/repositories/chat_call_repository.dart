import 'package:connect/config/routes/chat_call_routes.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/utils/app_logger.dart';

class ChatCallRepository {
  ChatCallRepository._();
  static final ChatCallRepository instance = ChatCallRepository._();

  /// Просит бэкенд отправить VoIP/FCM push собеседнику.
  ///
  /// Бэкенд создаёт `call_id`, шлёт push `type: chat_call` и возвращает его
  /// в ответе. `null` — если запрос не удался (например, эндпоинт недоступен):
  /// экран «Звоним…» в этом случае просто отработает по таймауту.
  Future<String?> ringDirectCall({
    required String chatId,
    required String room,
    String? topic,
  }) async {
    try {
      final decoded = await ApiClient.instance.post(
        ChatCallRoutes.ringUrl(chatId),
        body: {
          'room': room,
          if (topic != null && topic.isNotEmpty) 'topic': topic,
        },
      );
      final data = ApiEnvelope.unwrapDataMap(decoded);
      final callId = data['call_id']?.toString();
      return callId != null && callId.isNotEmpty ? callId : null;
    } catch (e, st) {
      AppLogger.d(
        'ringDirectCall failed (endpoint may be unavailable): $e',
        name: 'chat.call',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// `POST /chat/call/{callId}/accept` — сообщить звонящему, что мы приняли звонок.
  Future<void> acceptCall(String callId) async {
    try {
      await ApiClient.instance.post(ChatCallRoutes.acceptUrl(callId));
    } catch (e, st) {
      AppLogger.d(
        'acceptCall failed: $e',
        name: 'chat.call',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// `POST /chat/call/{callId}/end` — завершить/отменить звонок до ответа.
  Future<void> endCall(String callId) async {
    try {
      await ApiClient.instance.post(ChatCallRoutes.endUrl(callId));
    } catch (e, st) {
      AppLogger.d(
        'endCall failed: $e',
        name: 'chat.call',
        error: e,
        stackTrace: st,
      );
    }
  }
}
