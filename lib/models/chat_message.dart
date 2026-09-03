import 'package:connect/models/chat/chat_file.dart';
import 'package:flutter/foundation.dart';

/// Вложенная ссылка на цитируемое или пересылаемое сообщение.
@immutable
class MessageReference {
  const MessageReference({
    required this.messageId,
    required this.authorName,
    required this.textPreview,
    this.sourceChatTitle,
  });

  final String messageId;
  final String authorName;
  final String textPreview;
  final String? sourceChatTitle;
}

/// Текст, изображение, видео или файл.
enum ChatAttachmentKind { none, image, video, file }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.authorName,
    required this.isOutgoing,
    required this.createdAt,
    this.text,
    this.attachmentKind = ChatAttachmentKind.none,
    this.localMediaPath,
    this.remoteMediaUrl,
    this.fileName,
    this.replyTo,
    this.forwardOf,
    this.isSystem = false,
    this.repliedMessageId,
    this.isRead = true,
    this.authorAvatarUrl,
    this.readByRecipients = false,
    this.reactions = const <String>[],
    this.isEdited = false,
    this.isDeleted = false,
    this.isPinned = false,
    this.files = const [],
  });

  /// Сообщение можно редактировать в течение 15 минут после отправки.
  static const Duration editWindow = Duration(seconds: 900);
  /// Сообщение можно удалить в течение часа после отправки.
  static const Duration deleteWindow = Duration(seconds: 3600);

  final String id;
  final String chatId;
  final String authorName;
  final bool isOutgoing;
  final DateTime createdAt;
  final String? text;
  final ChatAttachmentKind attachmentKind;
  final String? localMediaPath;
  final String? remoteMediaUrl;
  final String? fileName;
  final MessageReference? replyTo;
  final MessageReference? forwardOf;
  final bool isSystem;
  final String? repliedMessageId;
  final bool isRead;
  final String? authorAvatarUrl;
  /// Для исходящих сообщений: прочитано ли всеми получателями (двойная галочка).
  final bool readByRecipients;
  /// Эмодзи-реакции текущего пользователя на сообщение (локальные, без синхронизации с сервером).
  final List<String> reactions;
  /// Сообщение было отредактировано после отправки.
  final bool isEdited;
  /// Сообщение удалено — вместо содержимого показывается плашка "Сообщение удалено".
  final bool isDeleted;
  /// Закреплено в чате (`is_pinned`).
  final bool isPinned;
  /// Файлы из `chat__files`, прикреплённые к сообщению.
  final List<ChatFile> files;

  bool get hasMedia =>
      files.isNotEmpty ||
      (attachmentKind != ChatAttachmentKind.none &&
          ((localMediaPath != null && localMediaPath!.isNotEmpty) ||
              (remoteMediaUrl != null && remoteMediaUrl!.isNotEmpty)));

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? authorName,
    bool? isOutgoing,
    DateTime? createdAt,
    String? text,
    ChatAttachmentKind? attachmentKind,
    String? localMediaPath,
    String? remoteMediaUrl,
    String? fileName,
    MessageReference? replyTo,
    MessageReference? forwardOf,
    bool? isSystem,
    String? repliedMessageId,
    bool? isRead,
    String? authorAvatarUrl,
    bool? readByRecipients,
    List<String>? reactions,
    bool? isEdited,
    bool? isDeleted,
    bool? isPinned,
    List<ChatFile>? files,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      authorName: authorName ?? this.authorName,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      createdAt: createdAt ?? this.createdAt,
      text: text ?? this.text,
      attachmentKind: attachmentKind ?? this.attachmentKind,
      localMediaPath: localMediaPath ?? this.localMediaPath,
      remoteMediaUrl: remoteMediaUrl ?? this.remoteMediaUrl,
      fileName: fileName ?? this.fileName,
      replyTo: replyTo ?? this.replyTo,
      forwardOf: forwardOf ?? this.forwardOf,
      isSystem: isSystem ?? this.isSystem,
      repliedMessageId: repliedMessageId ?? this.repliedMessageId,
      isRead: isRead ?? this.isRead,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      readByRecipients: readByRecipients ?? this.readByRecipients,
      reactions: reactions ?? this.reactions,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      isPinned: isPinned ?? this.isPinned,
      files: files ?? this.files,
    );
  }

  bool get canStillEdit =>
      !isDeleted && DateTime.now().difference(createdAt) <= editWindow;

  bool get canStillDelete =>
      !isDeleted && DateTime.now().difference(createdAt) <= deleteWindow;

  ChatMessage copyWithReadState({bool? isRead, bool? readByRecipients}) {
    return copyWith(isRead: isRead, readByRecipients: readByRecipients);
  }

  ChatMessage copyWithReactions(List<String> reactions) {
    return copyWith(reactions: reactions);
  }

  ChatMessage copyWithEdited(String text) {
    return copyWith(text: text, isEdited: true);
  }

  ChatMessage copyWithDeleted() {
    return ChatMessage(
      id: id,
      chatId: chatId,
      authorName: authorName,
      isOutgoing: isOutgoing,
      createdAt: createdAt,
      isSystem: isSystem,
      repliedMessageId: repliedMessageId,
      isRead: isRead,
      authorAvatarUrl: authorAvatarUrl,
      readByRecipients: readByRecipients,
      isEdited: isEdited,
      isDeleted: true,
      isPinned: isPinned,
    );
  }
}
