import 'package:connect/models/chat.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar, showModalBottomSheet;

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

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editChat() async {
    final titleCtrl = TextEditingController(text: _chat.title);
    final descCtrl = TextEditingController(text: _chat.description ?? '');

    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Редактировать чат'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: titleCtrl,
                placeholder: 'Название',
                autofocus: true,
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: descCtrl,
                placeholder: 'Описание',
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
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
    _showSnack(success ? 'Чат обновлён' : 'Не удалось обновить чат');
  }

  Future<void> _addMembers() async {
    await _service.loadContacts();
    if (!mounted) return;

    final existingIds = _chat.members.map((m) => m.userId).toSet();
    final candidates = _service.contacts
        .where((c) => c.userId > 0 && !existingIds.contains(c.userId))
        .toList();

    if (candidates.isEmpty) {
      _showSnack('Нет доступных контактов для добавления');
      return;
    }

    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: _AddMembersSheet(candidates: candidates),
        );
      },
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.addMembers(_chat.id, selected.toList());
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack(
      success ? 'Участники добавлены' : 'Не удалось добавить участников',
    );
  }

  Future<void> _removeMember(ChatMemberSummary member) async {
    final selfId = _service.selfUserId;
    if (selfId == null) return;
    if (member.userId == _chat.creatorId) return;

    final isSelf = member.userId == selfId;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(isSelf ? 'Выйти из чата?' : 'Удалить участника?'),
        content: Text(
          isSelf
              ? 'Вы покинете этот чат.'
              : 'Удалить ${member.displayName} из чата?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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

    _showSnack(
      success
          ? 'Участник удалён'
          : (_service.lastActionError ?? 'Не удалось удалить участника'),
    );
  }

  Future<void> _deleteChat() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить чат?'),
        content: const Text(
          'Чат будет помечен как удалённый для всех участников.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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
      _showSnack(_service.lastActionError ?? 'Не удалось удалить чат');
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selfId = _service.selfUserId;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Настройки чата'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: _busy
              ? const Center(child: CupertinoActivityIndicator(radius: 14))
              : ListView(
                  padding: const EdgeInsets.only(top: 20, bottom: 32),
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
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: CupertinoColors.label,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_chat.description != null &&
                        _chat.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                        child: Text(
                          _chat.description!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (_canManage && _chat.isGroup)
                      CupertinoListSection.insetGrouped(
                        children: [
                          CupertinoListTile(
                            leading: _iconBadge(
                              CupertinoIcons.person_add_solid,
                              CupertinoColors.systemGreen,
                            ),
                            title: const Text('Добавить участников'),
                            trailing: const CupertinoListTileChevron(),
                            onTap: _addMembers,
                          ),
                        ],
                      ),
                    if (_chat.members.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                        child: Text(
                          'УЧАСТНИКИ (${_chat.members.length})',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      CupertinoListSection.insetGrouped(
                        margin: EdgeInsets.zero,
                        children: _chat.members.map((m) {
                          final isCreator = m.userId == _chat.creatorId;
                          final canRemove =
                              m.userId == selfId || (_canManage && !isCreator);
                          final roleLabel = [
                            if (isCreator) 'Создатель',
                            if (m.isAdmin && !isCreator) 'Администратор',
                          ].join(' · ');
                          return CupertinoListTile(
                            leading: MemberAvatar(
                              displayName: m.displayName,
                              avatarUrl: m.avatarUrl,
                              radius: 18,
                            ),
                            title: Text(m.displayName),
                            subtitle: roleLabel.isEmpty
                                ? null
                                : Text(roleLabel),
                            trailing: canRemove
                                ? GestureDetector(
                                    onTap: () => _removeMember(m),
                                    child: Icon(
                                      m.userId == selfId
                                          ? CupertinoIcons.square_arrow_right
                                          : CupertinoIcons.minus_circle,
                                      color: CupertinoColors.systemRed,
                                    ),
                                  )
                                : null,
                          );
                        }).toList(),
                      ),
                    ],
                    if (_canManage && _chat.isGroup) ...[
                      const SizedBox(height: 20),
                      CupertinoListSection.insetGrouped(
                        children: [
                          CupertinoListTile(
                            leading: _iconBadge(
                              CupertinoIcons.delete_solid,
                              CupertinoColors.systemRed,
                            ),
                            title: const Text(
                              'Удалить чат',
                              style: TextStyle(color: CupertinoColors.systemRed),
                            ),
                            onTap: _deleteChat,
                          ),
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

class _AddMembersSheet extends StatefulWidget {
  const _AddMembersSheet({required this.candidates});

  final List<ChatContact> candidates;

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Добавить участников',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                CupertinoListSection.insetGrouped(
                  margin: EdgeInsets.zero,
                  children: widget.candidates.map((c) {
                    final checked = _selected.contains(c.userId);
                    return CupertinoListTile(
                      leading: MemberAvatar(
                        displayName: c.fullName,
                        avatarUrl: c.avatarUrl,
                        radius: 18,
                      ),
                      title: Text(c.fullName),
                      trailing: checked
                          ? const Icon(
                              CupertinoIcons.checkmark_circle_fill,
                              color: CupertinoColors.activeBlue,
                            )
                          : const Icon(
                              CupertinoIcons.circle,
                              color: CupertinoColors.systemGrey3,
                            ),
                      onTap: () {
                        setState(() {
                          if (checked) {
                            _selected.remove(c.userId);
                          } else {
                            _selected.add(c.userId);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: const Text('Добавить'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
