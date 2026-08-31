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
  });

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

  bool get hasMedia =>
      attachmentKind != ChatAttachmentKind.none &&
      ((localMediaPath != null && localMediaPath!.isNotEmpty) ||
          (remoteMediaUrl != null && remoteMediaUrl!.isNotEmpty));

  ChatMessage copyWithReadState({bool? isRead, bool? readByRecipients}) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      authorName: authorName,
      isOutgoing: isOutgoing,
      createdAt: createdAt,
      text: text,
      attachmentKind: attachmentKind,
      localMediaPath: localMediaPath,
      remoteMediaUrl: remoteMediaUrl,
      fileName: fileName,
      replyTo: replyTo,
      forwardOf: forwardOf,
      isSystem: isSystem,
      repliedMessageId: repliedMessageId,
      isRead: isRead ?? this.isRead,
      authorAvatarUrl: authorAvatarUrl,
      readByRecipients: readByRecipients ?? this.readByRecipients,
    );
  }
}
