import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/models/chat/add_chat_members_request.dart';
import 'package:connect/models/chat/chat_member_info.dart';
import 'package:connect/models/chat/chat_record.dart';
import 'package:connect/models/chat/create_chat_request.dart';
import 'package:connect/models/chat/update_chat_member_request.dart';
import 'package:connect/models/chat/update_chat_message_request.dart';
import 'package:connect/models/chat/update_chat_request.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/utils/chat_mapper.dart';

/// API-методы управления чатами (CRUD чатов, участников, сообщений).
class ChatManagementRepository {
  ChatManagementRepository._();
  static final ChatManagementRepository instance = ChatManagementRepository._();

  static const _deleteFallbackStatuses = {403, 404, 405};

  /// `POST /api/chat`
  Future<ChatRecord> createChat(
    CreateChatRequest request, {
    required int currentUserId,
  }) async {
    if (request.userIds.isEmpty) {
      throw ApiException(400, 'Укажите хотя бы одного участника');
    }

    final decoded = await ApiClient.instance.post(
      ChatRoutes.listUrl,
      body: request.toJson(),
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось создать чат',
    );
    return ChatRecord.fromJson(data);
  }

  /// `PUT /api/chat/{chat}`
  Future<ChatRecord> updateChat(
    int chatId,
    UpdateChatRequest request, {
    required int currentUserId,
  }) async {
    final body = request.toJson();
    if (body.isEmpty) {
      throw ApiException(400, 'Нет полей для обновления чата');
    }

    final decoded = await ApiClient.instance.put(
      ChatRoutes.chatUrl(chatId),
      body: body,
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось обновить чат',
    );
    return ChatRecord.fromJson(data);
  }

  /// `DELETE /api/chat/{chat}`
  ///
  /// На сервере нет `POST .../delete` для чата (в отличие от members/messages).
  /// Если инфраструктура блокирует HTTP DELETE (403), нужна правка на бэкенде/nginx.
  Future<void> deleteChat(int chatId) async {
    final decoded = await ApiClient.instance.delete(ChatRoutes.chatUrl(chatId));
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось удалить чат',
    );
  }

  /// `POST /api/chat/{chat}/members`
  Future<ChatRecord> addMembers(
    int chatId,
    AddChatMembersRequest request, {
    required int currentUserId,
  }) async {
    if (request.userIds.isEmpty) {
      throw ApiException(400, 'Укажите участников для добавления');
    }

    final decoded = await ApiClient.instance.post(
      ChatRoutes.membersUrl(chatId),
      body: request.toJson(),
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось добавить участников',
    );
    return ChatRecord.fromJson(data);
  }

  /// `PUT /api/chat/{chat}/members/{user}`
  Future<ChatMemberInfo> updateMember(
    int chatId,
    int userId,
    UpdateChatMemberRequest request, {
    required int currentUserId,
  }) async {
    final body = request.toJson();
    if (body.isEmpty) {
      throw ApiException(400, 'Нет полей для обновления участника');
    }

    final decoded = await ApiClient.instance.put(
      ChatRoutes.memberUrl(chatId, userId),
      body: body,
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось обновить участника',
    );
    return ChatMemberInfo.fromJson(data);
  }

  /// `DELETE /api/chat/{chat}/members/{user}` (fallback: `POST .../delete`)
  Future<void> removeMember(
    int chatId,
    int userId, {
    required int currentUserId,
  }) async {
    await _deleteWithPostFallback(
      deleteUrl: ChatRoutes.memberUrl(chatId, userId),
      postDeleteUrl: ChatRoutes.memberDeleteUrl(chatId, userId),
      defaultErrorMessage: 'Не удалось удалить участника',
    );
  }

  /// `PUT /api/chat/{chat}/messages/{message}`
  Future<ChatMessage> updateMessage(
    int chatId,
    int messageId,
    UpdateChatMessageRequest request, {
    required int currentUserId,
  }) async {
    if (request.text.trim().isEmpty) {
      throw ApiException(400, 'Текст сообщения пустой');
    }

    final decoded = await ApiClient.instance.put(
      ChatRoutes.messageUrl(chatId, messageId),
      body: request.toJson(),
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось обновить сообщение',
    );
    return ChatMapper.mapMessage(
      data,
      chatId: chatId.toString(),
      currentUserId: currentUserId,
    );
  }

  /// `DELETE /api/chat/{chat}/messages/{message}` (fallback: `POST .../delete`)
  Future<void> deleteMessage(int chatId, int messageId) async {
    await _deleteWithPostFallback(
      deleteUrl: ChatRoutes.messageUrl(chatId, messageId),
      postDeleteUrl: ChatRoutes.messageDeleteUrl(chatId, messageId),
      defaultErrorMessage: 'Не удалось удалить сообщение',
    );
  }

  /// На проде DELETE часто отвечает 403 (как раньше PATCH), хотя
  /// `POST .../delete` по спецификации поддерживается.
  Future<void> _deleteWithPostFallback({
    required String deleteUrl,
    required String postDeleteUrl,
    required String defaultErrorMessage,
  }) async {
    try {
      final decoded = await ApiClient.instance.delete(deleteUrl);
      ApiEnvelope.unwrapData(
        decoded,
        defaultErrorMessage: defaultErrorMessage,
      );
      return;
    } on ApiException catch (e) {
      if (!_deleteFallbackStatuses.contains(e.statusCode)) rethrow;
    }

    final decoded = await ApiClient.instance.post(postDeleteUrl);
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: defaultErrorMessage,
    );
  }
}
