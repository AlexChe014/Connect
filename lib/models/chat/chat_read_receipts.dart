import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:flutter/foundation.dart';

/// Кто из участников группы прочитал исходящее сообщение.
@immutable
class ChatReadReceipts {
  const ChatReadReceipts({required this.read, required this.unread});

  /// Считает по текущему составу чата: у вышедших нет имени, а вступившие
  /// после сообщения его не получали (у них нет статуса).
  factory ChatReadReceipts.of(
    ChatMessage message,
    List<ChatMemberSummary> members, {
    int? selfUserId,
  }) {
    final statuses = message.recipientReads;
    final read = <ChatMemberSummary>[];
    final unread = <ChatMemberSummary>[];
    for (final member in members) {
      if (member.userId == selfUserId) continue;
      final status = statuses.isEmpty
          ? message.readByRecipients
          : statuses[member.userId];
      if (status == null) continue;
      (status ? read : unread).add(member);
    }
    int byName(ChatMemberSummary a, ChatMemberSummary b) =>
        a.displayName.compareTo(b.displayName);
    read.sort(byName);
    unread.sort(byName);
    return ChatReadReceipts(read: read, unread: unread);
  }

  final List<ChatMemberSummary> read;
  final List<ChatMemberSummary> unread;

  int get total => read.length + unread.length;
}
