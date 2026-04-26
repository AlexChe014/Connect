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
    this.fileName,
    this.replyTo,
    this.forwardOf,
  });

  final String id;
  final String chatId;
  final String authorName;
  final bool isOutgoing;
  final DateTime createdAt;
  final String? text;
  final ChatAttachmentKind attachmentKind;
  final String? localMediaPath;
  final String? fileName;
  final MessageReference? replyTo;
  final MessageReference? forwardOf;

  bool get hasMedia =>
      localMediaPath != null &&
      localMediaPath!.isNotEmpty &&
      attachmentKind != ChatAttachmentKind.none;
}
