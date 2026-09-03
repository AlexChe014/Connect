import 'package:connect/models/chat_message.dart';
import 'package:flutter/foundation.dart';

/// Закреплённое сообщение чата (`GET /api/chat/{chat}/pinned-messages`).
@immutable
class PinnedChatMessage {
  const PinnedChatMessage({
    required this.id,
    required this.chatId,
    required this.messageId,
    required this.userId,
    required this.message,
    this.pinnedByName,
  });

  final int id;
  final int chatId;
  final int messageId;
  final int userId;
  final ChatMessage message;
  final String? pinnedByName;
}
