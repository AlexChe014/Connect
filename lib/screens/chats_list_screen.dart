import 'dart:async';

import 'package:connect/models/chat.dart';
import 'package:connect/screens/chat_conversation_screen.dart';
import 'package:connect/screens/create_group_chat_screen.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/app_empty_state.dart';
import 'package:connect/widgets/app_loading.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:connect/widgets/menu_button.dart';
import 'package:flutter/cupertino.dart';
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
  return formatted.endsWith('.')
      ? formatted.substring(0, formatted.length - 1)
      : formatted;
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
    _chat.loadContacts();
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

  Widget _buildSliverBody() {
    if (_chat.isLoading && _chat.chats.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: 6,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => const AppSkeletonCardTile(),
        ),
      );
    }

    if (_chat.error != null && _chat.chats.isEmpty) {
      return SliverFillRemaining(
        child: AppEmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          message: _chat.error!,
          onRetry: _chat.refreshChats,
        ),
      );
    }

    if (_chat.chats.isEmpty) {
      return const SliverFillRemaining(
        child: AppEmptyState(
          icon: CupertinoIcons.chat_bubble_2,
          message: 'Нет чатов',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      sliver: SliverList.separated(
        itemCount: _chat.chats.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final c = _chat.chats[index];
          return _ChatRow(
            chat: c,
            time: c.lastMessageAt != null
                ? _formatLastMessageTime(c.lastMessageAt!)
                : '',
            onTap: () {
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (context) => ChatConversationScreen(chat: c),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _chat.refreshChats,
            child: CustomScrollView(
              slivers: [
                CupertinoSliverNavigationBar(
                  largeTitle: const Text('Чаты'),
                  leading: const MenuButton(),
                  backgroundColor: CupertinoColors.systemGroupedBackground
                      .withValues(alpha: 0.9),
                  border: null,
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: _openComposeMenu,
                    child: const Icon(CupertinoIcons.add_circled, size: 28),
                  ),
                ),
                _buildSliverBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openComposeMenu() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'direct'),
            child: const Text('Новый диалог'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'group'),
            child: const Text('Новая группа'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'direct') {
      await _openNewDirect();
    } else {
      await _openNewGroup();
    }
  }

  Future<void> _openNewDirect() async {
    final selected = await showModalBottomSheet<ChatContactChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: const _NewDirectChatSheet(),
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
      _showMessage('Не удалось создать диалог');
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => ChatConversationScreen(chat: c),
      ),
    );
  }

  Future<void> _openNewGroup() async {
    final created = await Navigator.of(context).push<Chat>(
      CupertinoPageRoute(
        builder: (context) => const CreateGroupChatScreen(),
        fullscreenDialog: true,
      ),
    );
    if (created == null || !mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => ChatConversationScreen(chat: created),
      ),
    );
  }

  void _showMessage(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
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

class _NewDirectChatSheet extends StatefulWidget {
  const _NewDirectChatSheet();

  @override
  State<_NewDirectChatSheet> createState() => _NewDirectChatSheetState();
}

class _NewDirectChatSheetState extends State<_NewDirectChatSheet> {
  final _chat = ChatService.instance;
  final _searchCtrl = TextEditingController();
  String _search = '';
  List<ChatContact> _searchResults = const [];
  bool _searching = false;
  int _searchToken = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
    if (_chat.contacts.isEmpty) {
      _chat.loadContacts();
    }
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChange);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim();
    setState(() {
      _search = query.toLowerCase();
      if (query.isEmpty) {
        _searchResults = const [];
        _searching = false;
      }
    });

    _searchDebounce?.cancel();
    if (query.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    setState(() => _searching = true);
    try {
      final results = await _chat.searchContacts(query);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allContacts = _chat.contacts;
    List<ChatContact> contacts;
    if (_search.isEmpty) {
      contacts = allContacts;
    } else {
      final byId = <int, ChatContact>{
        for (final c in allContacts)
          if (c.fullName.toLowerCase().contains(_search)) c.userId: c,
      };
      for (final c in _searchResults) {
        byId[c.userId] = c;
      }
      contacts = byId.values.toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
    }
    final loading = _chat.isContactsLoading && allContacts.isEmpty;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Начать диалог',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Поиск',
            ),
          ),
          Expanded(
            child: loading
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: 8,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        const AppSkeletonCardTile(),
                  )
                : contacts.isEmpty && _searching
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                : contacts.isEmpty
                ? Center(
                    child: Text(
                      allContacts.isEmpty && _search.isEmpty
                          ? 'Нет доступных контактов'
                          : 'Ничего не найдено',
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final ct = contacts[index];
                      final fakeChat = Chat(
                        id: 'tmp',
                        title: ct.fullName,
                        isGroup: false,
                        peerAvatarPath: ct.avatarPath,
                        peerAvatarUrl: ct.avatarUrl,
                      );
                      return _ContactTile(
                        chat: fakeChat,
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
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.chat, required this.onTap});

  final Chat chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ChatAvatar(chat: chat, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: CupertinoColors.activeGreen,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.time, required this.onTap});

  final Chat chat;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        chat.lastMessagePreview ??
        (chat.isGroup && chat.memberNames.isNotEmpty
            ? chat.memberNames.join(', ')
            : '');

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChatAvatar(chat: chat, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (time.isNotEmpty || chat.unreadCount > 0) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.tertiaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    if (chat.unreadCount > 0) ...[
                      const SizedBox(height: 4),
                      _UnreadBadge(count: chat.unreadCount),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
