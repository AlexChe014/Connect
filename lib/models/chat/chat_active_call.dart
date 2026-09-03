import 'package:flutter/foundation.dart';

/// Активная видеовстреча, привязанная к чату.
@immutable
class ChatActiveCall {
  const ChatActiveCall({
    required this.chatId,
    required this.room,
    this.topic,
    required this.startedAt,
    this.isIncoming = false,
  });

  final String chatId;
  final String room;
  final String? topic;
  final DateTime startedAt;

  /// Для личного чата: приглашение от собеседника (не мы инициировали).
  final bool isIncoming;

  ChatActiveCall copyWith({
    String? chatId,
    String? room,
    String? topic,
    DateTime? startedAt,
    bool? isIncoming,
  }) {
    return ChatActiveCall(
      chatId: chatId ?? this.chatId,
      room: room ?? this.room,
      topic: topic ?? this.topic,
      startedAt: startedAt ?? this.startedAt,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }
}
