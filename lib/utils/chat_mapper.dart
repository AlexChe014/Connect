import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_record.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/services/paginated.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/utils/media_url_utils.dart';
import 'package:connect/utils/user_display_name.dart';

/// Маппинг JSON чат-API → модели приложения.
class ChatMapper {
  ChatMapper._();

  static Chat mapChat(Map<String, dynamic> json, {required int currentUserId}) {
    final id = _parseInt(json['id'])?.toString() ?? '';
    final isGroup = json['is_group'] == true;
    final members = mapMembers(json['members']);
    final creatorId = _parseInt(json['creator_id']);

    String title = (json['title'] as String?)?.trim() ?? '';
    if (title.isEmpty && !isGroup) {
      title = _peerMember(members, currentUserId)?.displayName ?? 'Чат';
    }
    if (title.isEmpty && isGroup) {
      title = 'Группа';
    }

    final peer = !isGroup ? _peerMember(members, currentUserId) : null;
    final previewMessage = _latestPreviewMessage(
      json['messages'],
      currentUserId: currentUserId,
    );

    return Chat(
      id: id,
      title: title,
      description: (json['description'] as String?)?.trim(),
      isGroup: isGroup,
      creatorId: creatorId,
      members: members,
      peerUserId: peer?.userId,
      peerAvatarUrl: peer?.avatarUrl,
      lastMessagePreview: previewMessage?.preview,
      lastMessageAt: previewMessage?.createdAt,
    );
  }

  static Chat fromRecord(ChatRecord record, {required int currentUserId}) {
    final members = record.members
        .map(
          (m) => ChatMemberSummary(
            userId: m.userId,
            displayName: m.fullName,
            avatarUrl: m.avatarUrl,
            isAdmin: m.isAdmin,
          ),
        )
        .toList(growable: false);

    String title = record.title;
    if (title.isEmpty && !record.isGroup) {
      title = _peerMember(members, currentUserId)?.displayName ?? 'Чат';
    }
    if (title.isEmpty && record.isGroup) {
      title = 'Группа';
    }

    final peer = !record.isGroup ? _peerMember(members, currentUserId) : null;

    return Chat(
      id: record.id.toString(),
      title: title,
      description: record.description,
      isGroup: record.isGroup,
      creatorId: record.creatorId,
      members: members,
      peerUserId: peer?.userId,
      peerAvatarUrl: peer?.avatarUrl,
    );
  }

  static List<ChatMemberSummary> mapMembers(Object? raw) {
    if (raw is! List) return const [];
    final out = <ChatMemberSummary>[];
    for (final item in raw) {
      final map = _asJsonMap(item);
      if (map == null) continue;
      final user = _asJsonMap(map['user']);
      if (user == null) continue;
      final userId = _parseInt(map['user_id'] ?? user['id']);
      if (userId == null) continue;
      out.add(
        ChatMemberSummary(
          userId: userId,
          displayName: userDisplayNameFromJson(user),
          avatarUrl: MediaUrlUtils.normalizeFirstUrl(user['media']),
          isAdmin: map['is_admin'] == true,
        ),
      );
    }
    return out;
  }

  static ChatMessage mapMessage(
    Map<String, dynamic> json, {
    required String chatId,
    required int currentUserId,
  }) {
    final id = _parseInt(json['id'])?.toString() ?? '';
    final senderId = _parseInt(json['sender_id']);
    final sender = _asJsonMap(json['sender']);
    final authorName =
        sender != null ? userDisplayNameFromJson(sender) : 'Пользователь';
    final authorAvatarUrl = sender != null
        ? MediaUrlUtils.normalizeFirstUrl(sender['media'])
        : null;
    final type = (json['type'] as String?)?.trim().toUpperCase() ?? 'TEXT';
    final rawMessage = _readMessageText(json);
    final createdAt = _parseDate(json['created_at']) ?? DateTime.now();
    final resolved = _resolveMessageContent(
      rawMessage: rawMessage,
      type: type,
      json: json,
    );

    return ChatMessage(
      id: id,
      chatId: chatId,
      authorName: authorName,
      isOutgoing: senderId == currentUserId,
      createdAt: createdAt,
      text: resolved.text,
      attachmentKind: resolved.attachmentKind,
      remoteMediaUrl: resolved.remoteMediaUrl,
      isSystem: type == 'SYSTEM',
      repliedMessageId: _parseInt(json['replied_message_id'])?.toString(),
      isRead: _isReadForUser(json, currentUserId, senderId),
      authorAvatarUrl: authorAvatarUrl,
    );
  }

  static Paginated<ChatMessage> unwrapMessagesPage(
    Map<String, dynamic> decoded, {
    required int chatId,
    required int currentUserId,
    required String messagesBaseUrl,
    String defaultErrorMessage = 'Не удалось получить сообщения',
  }) {
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: defaultErrorMessage,
    );

    final rawList = data['messages'] ?? data['data'];
    if (rawList is! List) {
      throw ApiException(200, 'Некорректный формат messages');
    }

    final chatIdStr = chatId.toString();
    final items = rawList
        .map(_asJsonMap)
        .whereType<Map<String, dynamic>>()
        .map(
          (json) => mapMessage(
            json,
            chatId: chatIdStr,
            currentUserId: currentUserId,
          ),
        )
        .toList(growable: false);

    final pagination = _asJsonMap(data['pagination']);
    var currentPage = 1;
    int? lastPage;
    int? perPage;
    int? total;
    String? nextPageUrl;

    if (pagination != null) {
      currentPage = _parseInt(pagination['current_page']) ?? 1;
      lastPage = _parseInt(pagination['last_page']);
      perPage = _parseInt(pagination['per_page']);
      total = _parseInt(pagination['total']);
      if (lastPage != null && currentPage < lastPage) {
        final pp = perPage ?? 50;
        nextPageUrl =
            '$messagesBaseUrl?page=${currentPage + 1}&per_page=$pp';
      }
    } else {
      currentPage = _parseInt(data['current_page']) ?? 1;
      lastPage = _parseInt(data['last_page']);
      perPage = _parseInt(data['per_page']);
      total = _parseInt(data['total']);
      nextPageUrl = data['next_page_url'] as String?;
    }

    final chronological = items.reversed.toList(growable: false);
    final withReplies = attachReplyReferences(chronological);

    return Paginated<ChatMessage>(
      data: withReplies,
      currentPage: currentPage,
      nextPageUrl: nextPageUrl,
      prevPageUrl: null,
      path: messagesBaseUrl,
      perPage: perPage,
      to: withReplies.length,
      total: total ?? withReplies.length,
    );
  }

  static List<ChatMessage> attachReplyReferences(List<ChatMessage> messages) {
    if (messages.isEmpty) return messages;

    final byId = {for (final m in messages) m.id: m};
    return messages
        .map((m) {
          final replyId = m.repliedMessageId;
          if (replyId == null) return m;
          final source = byId[replyId];
          if (source == null) return m;
          return ChatMessage(
            id: m.id,
            chatId: m.chatId,
            authorName: m.authorName,
            isOutgoing: m.isOutgoing,
            createdAt: m.createdAt,
            text: m.text,
            attachmentKind: m.attachmentKind,
            localMediaPath: m.localMediaPath,
            remoteMediaUrl: m.remoteMediaUrl,
            fileName: m.fileName,
            replyTo: MessageReference(
              messageId: source.id,
              authorName: source.authorName,
              textPreview: snippet(source),
            ),
            forwardOf: m.forwardOf,
            isSystem: m.isSystem,
            repliedMessageId: m.repliedMessageId,
            isRead: m.isRead,
            authorAvatarUrl: m.authorAvatarUrl,
          );
        })
        .toList(growable: false);
  }

  static String snippet(ChatMessage m) {
    if (m.text != null && m.text!.trim().isNotEmpty) {
      return HtmlTextUtils.toPlainText(m.text!);
    }
    switch (m.attachmentKind) {
      case ChatAttachmentKind.image:
        return '📷 Фото';
      case ChatAttachmentKind.video:
        return '🎬 Видео';
      case ChatAttachmentKind.file:
        return '📎 ${m.fileName ?? 'Файл'}';
      case ChatAttachmentKind.none:
        if (m.isSystem) {
          final t = m.text;
          if (t == null || t.trim().isEmpty) return 'Системное сообщение';
          return HtmlTextUtils.toPlainText(t);
        }
        return 'Сообщение';
    }
  }

  static _PreviewMessage? _latestPreviewMessage(
    Object? rawMessages, {
    required int currentUserId,
  }) {
    if (rawMessages is! List || rawMessages.isEmpty) return null;

    ChatMessage? latest;
    for (final item in rawMessages) {
      final map = _asJsonMap(item);
      if (map == null) continue;
      final chatId = _parseInt(map['chat_id'])?.toString() ?? '';
      final message = mapMessage(
        map,
        chatId: chatId,
        currentUserId: currentUserId,
      );
      if (latest == null || message.createdAt.isAfter(latest.createdAt)) {
        latest = message;
      }
    }

    if (latest == null) return null;
    if (latest.isSystem) {
      return _PreviewMessage(latest.text, latest.createdAt);
    }
    return _PreviewMessage(snippet(latest), latest.createdAt);
  }

  static ChatMemberSummary? _peerMember(
    List<ChatMemberSummary> members,
    int currentUserId,
  ) {
    for (final member in members) {
      if (member.userId != currentUserId) return member;
    }
    return members.isNotEmpty ? members.first : null;
  }

  static String? _readMessageText(Map<String, dynamic> json) {
    final message = (json['message'] as String?)?.trim();
    if (message != null && message.isNotEmpty) return message;
    final text = (json['text'] as String?)?.trim();
    if (text != null && text.isNotEmpty) return text;
    return null;
  }

  static _ResolvedMessageContent _resolveMessageContent({
    required String? rawMessage,
    required String type,
    required Map<String, dynamic> json,
  }) {
    if (type == 'SYSTEM') {
      return _ResolvedMessageContent(text: rawMessage);
    }

    if (type == 'MEDIA') {
      final remoteUrl = _remoteMediaUrl(json) ??
          (rawMessage != null && rawMessage.startsWith('http')
              ? rawMessage
              : null);
      return _ResolvedMessageContent(
        text: rawMessage != null && !rawMessage.startsWith('http')
            ? rawMessage
            : null,
        attachmentKind: ChatAttachmentKind.image,
        remoteMediaUrl: remoteUrl,
      );
    }

    return _ResolvedMessageContent(text: rawMessage);
  }

  static String? _remoteMediaUrl(Map<String, dynamic> json) {
    final attachments = json['attachments'] ?? json['media'];
    return MediaUrlUtils.normalizeFirstUrl(attachments);
  }

  static bool _isReadForUser(
    Map<String, dynamic> json,
    int currentUserId,
    int? senderId,
  ) {
    if (senderId == currentUserId) return true;

    final statuses = json['statuses'];
    if (statuses is! List || statuses.isEmpty) return true;

    for (final item in statuses) {
      final map = _asJsonMap(item);
      if (map == null) continue;
      final userId = _parseInt(map['user_id']);
      if (userId == currentUserId) {
        return _parseBool(map['read'], defaultValue: false);
      }
    }
    return true;
  }

  static bool _parseBool(Object? value, {bool defaultValue = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value?.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  static Map<String, dynamic>? _asJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString().trim());
  }
}

class _PreviewMessage {
  const _PreviewMessage(this.preview, this.createdAt);

  final String? preview;
  final DateTime createdAt;
}

class _ResolvedMessageContent {
  const _ResolvedMessageContent({
    this.text,
    this.attachmentKind = ChatAttachmentKind.none,
    this.remoteMediaUrl,
  });

  final String? text;
  final ChatAttachmentKind attachmentKind;
  final String? remoteMediaUrl;
}
