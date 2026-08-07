import 'package:connect/config/app_icons.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:flutter/material.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key, required this.chat});

  final Chat chat;

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  final _service = ChatService.instance;
  late Chat _chat;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _service.addListener(_onService);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onService);
    super.dispose();
  }

  void _onService() {
    if (!mounted) return;
    final updated = _service.chatById(widget.chat.id);
    if (updated != null) {
      setState(() => _chat = updated);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await _service.refreshChatDetails(widget.chat.id);
    if (mounted) setState(() => _busy = false);
  }

  bool get _canManage => _chat.canManage(_service.selfUserId);

  Future<void> _editChat() async {
    final titleCtrl = TextEditingController(text: _chat.title);
    final descCtrl = TextEditingController(text: _chat.description ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Редактировать чат',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Название', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Описание', isDense: true),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.updateChat(
      _chat.id,
      title: titleCtrl.text.trim(),
      description: descCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Чат обновлён' : 'Не удалось обновить чат'),
      ),
    );
  }

  Future<void> _addMembers() async {
    await _service.loadContacts();
    if (!mounted) return;

    final existingIds = _chat.members.map((m) => m.userId).toSet();
    final candidates = _service.contacts
        .where((c) => c.userId > 0 && !existingIds.contains(c.userId))
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступных контактов для добавления')),
      );
      return;
    }

    final selected = <int>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Добавить участников',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (context, i) {
                        final c = candidates[i];
                        return CheckboxListTile(
                          value: selected.contains(c.userId),
                          onChanged: (v) {
                            setModalState(() {
                              if (v == true) {
                                selected.add(c.userId);
                              } else {
                                selected.remove(c.userId);
                              }
                            });
                          },
                          title: Text(c.fullName),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, true),
                      child: const Text('Добавить'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || selected.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.addMembers(_chat.id, selected.toList());
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Участники добавлены' : 'Не удалось добавить участников',
        ),
      ),
    );
  }

  Future<void> _removeMember(ChatMemberSummary member) async {
    final selfId = _service.selfUserId;
    if (selfId == null) return;
    if (member.userId == _chat.creatorId) return;

    final isSelf = member.userId == selfId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSelf ? 'Выйти из чата?' : 'Удалить участника?'),
        content: Text(
          isSelf
              ? 'Вы покинете этот чат.'
              : 'Удалить ${member.displayName} из чата?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isSelf ? 'Выйти' : 'Удалить'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.removeMember(_chat.id, member.userId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (isSelf && success) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Участник удалён'
              : (_service.lastActionError ?? 'Не удалось удалить участника'),
        ),
      ),
    );
  }

  Future<void> _deleteChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: const Text('Чат будет помечен как удалённый для всех участников.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.deleteChat(_chat.id);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _service.lastActionError ?? 'Не удалось удалить чат',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final selfId = _service.selfUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки чата'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _canManage && _chat.isGroup ? _editChat : null,
                    child: ChatAvatar(chat: _chat, radius: 40),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _chat.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_chat.description != null && _chat.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _chat.description!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 24),
                if (_canManage && _chat.isGroup) ...[
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_add_outlined),
                    title: const Text('Добавить участников'),
                    onTap: _addMembers,
                  ),
                ],
                Text(
                  'Участники (${_chat.members.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ..._chat.members.map((m) {
                  final isCreator = m.userId == _chat.creatorId;
                  final canRemove = m.userId == selfId ||
                      (_canManage && !isCreator);
                  return ListTile(
                    leading: MemberAvatar(
                      displayName: m.displayName,
                      avatarUrl: m.avatarUrl,
                      radius: 20,
                    ),
                    title: Text(m.displayName),
                    subtitle: Text(
                      [
                        if (isCreator) 'Создатель',
                        if (m.isAdmin && !isCreator) 'Администратор',
                      ].join(' · '),
                    ),
                    trailing: canRemove
                        ? IconButton(
                            icon: m.userId == selfId
                                ? const AppIcon(AppIcons.logout)
                                : const Icon(Icons.person_remove_outlined),
                            tooltip: m.userId == selfId ? 'Выйти' : 'Удалить',
                            onPressed: () => _removeMember(m),
                          )
                        : null,
                  );
                }),
                const SizedBox(height: 24),
                if (_canManage && _chat.isGroup)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Удалить чат',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: _deleteChat,
                  ),
              ],
            ),
    );
  }
}
