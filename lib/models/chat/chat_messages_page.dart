import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/paginated.dart';

/// Результат загрузки сообщений вместе с участниками чата (из `show`).
class ChatMessagesPage {
  const ChatMessagesPage({
    required this.messages,
    this.members = const [],
  });

  final Paginated<ChatMessage> messages;
  final List<ChatMemberSummary> members;
}
