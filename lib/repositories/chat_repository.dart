import 'dart:convert';
import 'dart:typed_data';

import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/models/chat/chat_messages_page.dart';
import 'package:connect/models/chat/pinned_chat_message.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/utils/chat_mapper.dart';
import 'package:http/http.dart' as http;

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
      final payload = ApiEnvelope.unwrapData(
        decoded,
        defaultErrorMessage: 'Не удалось получить список чатов',
      );
      List rawChats;
      Map<String, dynamic>? pagination;
      if (payload is List) {
        rawChats = payload;
      } else if (payload is Map<String, dynamic>) {
        rawChats = (payload['chats'] ?? payload['data']) as List? ?? const [];
        pagination = _asJsonMap(payload['pagination']);
      } else if (payload is Map) {
        final map = payload.cast<String, dynamic>();
        rawChats = (map['chats'] ?? map['data']) as List? ?? const [];
        pagination = _asJsonMap(map['pagination']);
      } else {
        throw ApiException(200, 'Некорректный формат списка чатов');
      }

      chats.addAll(
        rawChats
            .map(_asJsonMap)
            .whereType<Map<String, dynamic>>()
            .map((json) => ChatMapper.mapChat(json, currentUserId: currentUserId))
            .where((c) => c.id.isNotEmpty),
      );

      lastPage = _parseInt(pagination?['last_page']) ?? page;
      final currentPage = _parseInt(pagination?['current_page']) ?? page;
      if (currentPage >= lastPage || page >= maxPages) break;
      page = currentPage + 1;
    } while (page <= lastPage);

    chats.sort(Chat.compareForList);

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

  /// Загружает всю историю сообщений чата постранично — для клиентской
  /// фильтрации (медиа/файлы/ссылки в деталях чата), поскольку сервер не
  /// умеет фильтровать сообщения по типу вложения.
  Future<List<ChatMessage>> getAllMessages(
    int chatId, {
    required int currentUserId,
    int maxPages = 200,
  }) async {
    final all = <ChatMessage>[];
    String? pageUrl;
    var pages = 0;
    do {
      final page = await getMessages(
        chatId,
        currentUserId: currentUserId,
        pageUrl: pageUrl,
      );
      all.addAll(page.messages.data);
      pageUrl = page.messages.hasMore ? page.messages.nextPageUrl : null;
      pages++;
    } while (pageUrl != null && pages < maxPages);
    return all;
  }

  Future<ChatMessage> sendTextMessage(
    int chatId, {
    required String text,
    required int currentUserId,
    int? repliedMessageId,
    int? forwardedMessageId,
  }) {
    return sendMessage(
      chatId,
      text: text,
      currentUserId: currentUserId,
      repliedMessageId: repliedMessageId,
      forwardedMessageId: forwardedMessageId,
    );
  }

  Future<ChatMessage> sendMessage(
    int chatId, {
    String text = '',
    required int currentUserId,
    int? repliedMessageId,
    int? forwardedMessageId,
    List<int>? fileIds,
  }) async {
    final trimmed = text.trim();
    final ids = fileIds ?? const <int>[];
    if (trimmed.isEmpty && ids.isEmpty) {
      throw ApiException(400, 'Текст сообщения пустой');
    }

    final body = <String, dynamic>{
      'message': trimmed,
      'text': trimmed,
    };
    if (repliedMessageId != null) {
      body['replied_message_id'] = repliedMessageId;
    }
    if (forwardedMessageId != null) {
      body['forwarded_message_id'] = forwardedMessageId;
    }
    if (ids.isNotEmpty) {
      body['file_ids'] = ids;
      body['type'] = 'MEDIA';
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

  Future<ChatFile> uploadFile({
    required List<int> bytes,
    required String filename,
  }) async {
    if (bytes.length > ChatFile.maxSizeBytes) {
      throw ApiException(400, 'Файл больше 10 МБ');
    }

    final decoded = await ApiClient.instance.postMultipart(
      ChatRoutes.filesUrl,
      files: [
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      ],
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось загрузить файл',
    );
    return ChatFile.fromJson(data);
  }

  Future<Uint8List> downloadFile(int fileId) async {
    final bytes = await ApiClient.instance.downloadBytes(
      ChatRoutes.fileUrl(fileId),
    );

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic> && decoded['success'] == false) {
        ApiEnvelope.unwrapData(
          decoded,
          defaultErrorMessage: 'Не удалось скачать файл',
        );
      }
    } catch (_) {
      // Бинарные данные не декодируются как UTF-8 JSON — это и есть файл.
    }

    return Uint8List.fromList(bytes);
  }

  Future<List<PinnedChatMessage>> getPinnedMessages(
    int chatId, {
    required int currentUserId,
  }) async {
    final decoded = await ApiClient.instance.get(
      ChatRoutes.pinnedMessagesUrl(chatId),
    );
    final raw = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить закреплённые сообщения',
    );
    return raw
        .map((item) {
          if (item is Map<String, dynamic>) {
            return ChatMapper.mapPinnedMessage(
              item,
              currentUserId: currentUserId,
            );
          }
          if (item is Map) {
            return ChatMapper.mapPinnedMessage(
              Map<String, dynamic>.from(item),
              currentUserId: currentUserId,
            );
          }
          return null;
        })
        .whereType<PinnedChatMessage>()
        .toList(growable: false);
  }

  Future<void> markRead(int chatId) async {
    await ApiClient.instance.post(ChatRoutes.readUrl(chatId));
  }

  Map<String, dynamic>? _asJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
