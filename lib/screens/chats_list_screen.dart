import 'package:connect/models/chat.dart';
import 'package:connect/screens/chat_conversation_screen.dart';
import 'package:connect/screens/create_group_chat_screen.dart';
import 'package:connect/services/chat_service.dart';
import 'package:flutter/material.dart';

String _formatTime(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _chat = ChatService.instance;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChats);
    _chat.init();
  }

  @override
  void dispose() {
    _chat.removeListener(_onChats);
    super.dispose();
  }

  void _onChats() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView.separated(
        itemCount: _chat.chats.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final c = _chat.chats[index];
          return _ChatRow(
            chat: c,
            time: c.lastMessageAt != null ? _formatTime(c.lastMessageAt!) : '',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ChatConversationScreen(chat: c),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewGroup,
        icon: const Icon(Icons.group_add),
        label: const Text('Группа'),
      ),
    );
  }

  Future<void> _openNewGroup() async {
    final created = await Navigator.of(context).push<Chat>(
      MaterialPageRoute(
        builder: (context) => const CreateGroupChatScreen(),
        fullscreenDialog: true,
      ),
    );
    if (created == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChatConversationScreen(chat: created),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.time,
    required this.onTap,
  });

  final Chat chat;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          chat.isGroup ? Icons.groups : Icons.person,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        chat.lastMessagePreview ??
            (chat.isGroup && chat.memberNames.isNotEmpty
                ? chat.memberNames.join(', ')
                : ''),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      trailing: time.isNotEmpty
          ? Text(
              time,
              style: TextStyle(
                color: theme.colorScheme.outline,
                fontSize: 12,
              ),
            )
          : null,
    );
  }
}
