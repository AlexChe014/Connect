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
    this.callId,
    this.isDirect = false,
  });

  final String chatId;
  final String room;
  final String? topic;
  final DateTime startedAt;

  /// Для личного чата: приглашение от собеседника (не мы инициировали).
  final bool isIncoming;

  /// UUID звонка с бэкенда (`call_id`) — для end/decline.
  final String? callId;

  /// Личный 1:1 звонок (без плашки и ссылки в чате).
  final bool isDirect;

  ChatActiveCall copyWith({
    String? chatId,
    String? room,
    String? topic,
    DateTime? startedAt,
    bool? isIncoming,
    String? callId,
    bool? isDirect,
  }) {
    return ChatActiveCall(
      chatId: chatId ?? this.chatId,
      room: room ?? this.room,
      topic: topic ?? this.topic,
      startedAt: startedAt ?? this.startedAt,
      isIncoming: isIncoming ?? this.isIncoming,
      callId: callId ?? this.callId,
      isDirect: isDirect ?? this.isDirect,
    );
  }
}
