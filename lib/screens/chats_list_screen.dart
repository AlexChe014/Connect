import 'package:connect/config/app_icons.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/screens/chat_conversation_screen.dart';
import 'package:connect/screens/create_group_chat_screen.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _weekdayShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _weekStart(DateTime d) {
  final day = _dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

bool _isSameWeek(DateTime a, DateTime b) => _weekStart(a) == _weekStart(b);

String _formatLastMessageTime(DateTime d) {
  final local = d.toLocal();
  final now = DateTime.now();
  final today = _dateOnly(now);
  final messageDay = _dateOnly(local);
  final dayDiff = today.difference(messageDay).inDays;

  if (dayDiff == 0) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (dayDiff == 1) {
    return 'вчера';
  }
  if (_isSameWeek(local, now)) {
    return _weekdayShort[local.weekday - 1];
  }
  final formatted = DateFormat('d MMM', 'ru_RU').format(local);
  return formatted.endsWith('.') ? formatted.substring(0, formatted.length - 1) : formatted;
}

Widget _chatAvatar(BuildContext context, Chat c) => ChatAvatar(chat: c, radius: 22);

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chat.init();
      _chat.loadContacts();
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_onChats);
    super.dispose();
  }

  void _onChats() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _buildBody(BuildContext context) {
    if (_chat.isLoading && _chat.chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_chat.error != null && _chat.chats.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  _chat.error!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _chat.refreshChats,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_chat.chats.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Нет чатов')),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _chat.chats.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outline,
      ),
      itemBuilder: (context, index) {
        final c = _chat.chats[index];
        return _ChatRow(
          chat: c,
          time: c.lastMessageAt != null ? _formatLastMessageTime(c.lastMessageAt!) : '',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => ChatConversationScreen(chat: c),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(
            tooltip: 'Новый диалог',
            icon: const AppIcon(AppIcons.compose),
            onPressed: _openNewDirect,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _chat.refreshChats,
        child: _buildBody(context),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewGroup,
        icon: const AppIcon(AppIcons.users),
        label: const Text('Группа'),
      ),
    );
  }

  Future<void> _openNewDirect() async {
    final selected = await showModalBottomSheet<ChatContactChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final contacts = _chat.contacts;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Начать диалог',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  separatorBuilder: (context, i) => Divider(
                    height: 1,
                    thickness: 0.6,
                    indent: 76,
                    endIndent: 12,
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
                  ),
                  itemBuilder: (context, i) {
                    final ct = contacts[i];
                    final fakeChat = Chat(
                      id: 'tmp',
                      title: ct.fullName,
                      isGroup: false,
                      peerAvatarPath: ct.avatarPath,
                      peerAvatarUrl: ct.avatarUrl,
                    );
                    return ListTile(
                      leading: _chatAvatar(context, fakeChat),
                      title: Text(ct.fullName),
                      onTap: () => Navigator.pop(
                        context,
                        ChatContactChoice(
                          userId: ct.userId,
                          fullName: ct.fullName,
                          avatarPath: ct.avatarPath,
                          avatarUrl: ct.avatarUrl,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    final c = await _chat.createDirect(
      fullName: selected.fullName,
      peerAvatarPath: selected.avatarPath,
      peerUserId: selected.userId,
      peerAvatarUrl: selected.avatarUrl,
    );
    if (!mounted) return;
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать диалог')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChatConversationScreen(chat: c),
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

@immutable
class ChatContactChoice {
  const ChatContactChoice({
    required this.userId,
    required this.fullName,
    this.avatarPath,
    this.avatarUrl,
  });
  final int userId;
  final String fullName;
  final String? avatarPath;
  final String? avatarUrl;
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
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: ChatAvatar(chat: chat, radius: 22),
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
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
    );
  }
}
