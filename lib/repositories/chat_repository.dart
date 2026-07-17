import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/models/chat/chat_messages_page.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/utils/chat_mapper.dart';

class ChatRepository {
  ChatRepository._();
  static final ChatRepository instance = ChatRepository._();

  Future<List<Chat>> getChats({required int currentUserId}) async {
    const perPage = 50;
    // Для превью в списке достаточно последнего сообщения.
    const messagesPerChat = 1;
    const maxPages = 100;
    final chats = <Chat>[];
    var page = 1;
    var lastPage = 1;

    do {
      final decoded = await ApiClient.instance.get(
        ChatRoutes.listUrl,
        queryParameters: {
          'page': '$page',
          'per_page': '$perPage',
          'messages_per_chat': '$messagesPerChat',
        },
      );
      final data = ApiEnvelope.unwrapDataMap(
        decoded,
        defaultErrorMessage: 'Не удалось получить список чатов',
      );
      final rawChats = data['chats'];
      if (rawChats is! List) {
        throw ApiException(200, 'Некорректный формат списка чатов');
      }

      chats.addAll(
        rawChats
            .map(_asJsonMap)
            .whereType<Map<String, dynamic>>()
            .map((json) => ChatMapper.mapChat(json, currentUserId: currentUserId))
            .where((c) => c.id.isNotEmpty),
      );

      final pagination = _asJsonMap(data['pagination']);
      lastPage = _parseInt(pagination?['last_page']) ?? page;
      final currentPage = _parseInt(pagination?['current_page']) ?? page;
      if (currentPage >= lastPage || page >= maxPages) break;
      page = currentPage + 1;
    } while (page <= lastPage);

    chats.sort((a, b) {
      final at = a.lastMessageAt;
      final bt = b.lastMessageAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return chats;
  }

  int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  Future<Chat> getChat(int chatId, {required int currentUserId}) async {
    final decoded = await ApiClient.instance.get(ChatRoutes.chatUrl(chatId));
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить чат',
    );
    return ChatMapper.mapChat(data, currentUserId: currentUserId);
  }

  Future<ChatMessagesPage> getMessages(
    int chatId, {
    required int currentUserId,
    String? pageUrl,
  }) async {
    final messagesBaseUrl = ChatRoutes.messagesUrl(chatId);
    final url = pageUrl ?? messagesBaseUrl;
    final decoded = await ApiClient.instance.get(
      url,
      queryParameters: pageUrl == null ? const {'per_page': '50'} : null,
    );

    final messages = ChatMapper.unwrapMessagesPage(
      decoded,
      chatId: chatId,
      currentUserId: currentUserId,
      messagesBaseUrl: messagesBaseUrl,
    );

    List<ChatMemberSummary> members = const [];
    if (pageUrl == null) {
      try {
        final chat = await getChat(chatId, currentUserId: currentUserId);
        members = chat.members;
      } catch (_) {}
    }

    return ChatMessagesPage(messages: messages, members: members);
  }

  Future<ChatMessage> sendTextMessage(
    int chatId, {
    required String text,
    required int currentUserId,
    int? repliedMessageId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ApiException(400, 'Текст сообщения пустой');
    }

    final body = <String, dynamic>{
      'message': trimmed,
      'type': 'TEXT',
    };
    if (repliedMessageId != null) {
      body['replied_message_id'] = repliedMessageId;
    }

    final decoded = await ApiClient.instance.post(
      ChatRoutes.messagesUrl(chatId),
      body: body,
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось отправить сообщение',
    );
    return ChatMapper.mapMessage(
      data,
      chatId: chatId.toString(),
      currentUserId: currentUserId,
    );
  }

  Map<String, dynamic>? _asJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
