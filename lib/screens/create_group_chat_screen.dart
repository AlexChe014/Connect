import 'dart:async';

import 'package:connect/models/chat.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/app_loading.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:flutter/cupertino.dart';

class CreateGroupChatScreen extends StatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _selected = <int>{};
  bool _creating = false;
  String? _nameError;
  String _search = '';
  List<ChatContact> _searchResults = const [];
  bool _searching = false;
  int _searchToken = 0;
  Timer? _searchDebounce;
  final _chat = ChatService.instance;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChat);
    _chat.loadContacts();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    _searchDebounce?.cancel();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
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

  void _onChat() {
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Введите название группы' : null;
    });
    if (_nameError != null) return;

    if (_selected.isEmpty) {
      _showMessage('Выберите хотя бы одного участника');
      return;
    }

    setState(() => _creating = true);
    final c = await ChatService.instance.createGroup(
      title: name,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      userIds: _selected.toList(),
    );
    if (!mounted) return;
    setState(() => _creating = false);

    if (c == null) {
      _showMessage('Не удалось создать группу');
      return;
    }
    Navigator.of(context).pop<Chat>(c);
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

  @override
  Widget build(BuildContext context) {
    final allContacts = _chat.contacts.where((c) => c.userId > 0).toList();
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
    final contactsLoading = _chat.isContactsLoading && allContacts.isEmpty;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Новая группа'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 26),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _creating ? null : _create,
          child: _creating
              ? const CupertinoActivityIndicator()
              : const Text(
                  'Создать',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CupertinoFormSection.insetGrouped(
                  header: const Text('О ГРУППЕ'),
                  children: [
                    CupertinoTextFormFieldRow(
                      controller: _nameCtrl,
                      prefix: const Text('Название'),
                      placeholder: 'Например, Отдел продаж',
                      textCapitalization: TextCapitalization.sentences,
                      textAlign: TextAlign.end,
                      autofocus: true,
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                    ),
                    CupertinoTextFormFieldRow(
                      controller: _descCtrl,
                      prefix: const Text('Описание'),
                      placeholder: 'Необязательно',
                      textCapitalization: TextCapitalization.sentences,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              if (_nameError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _nameError!,
                      style: const TextStyle(
                        color: CupertinoColors.systemRed,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'УЧАСТНИКИ${_selected.isEmpty ? '' : ' • ${_selected.length}'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoSearchTextField(
                  controller: _searchCtrl,
                  placeholder: 'Поиск',
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: contactsLoading
                    ? ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: 6,
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
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final c = contacts[index];
                          final checked = _selected.contains(c.userId);
                          final isFirst = index == 0;
                          final isLast = index == contacts.length - 1;
                          return Container(
                            decoration: BoxDecoration(
                              color: CupertinoColors
                                  .secondarySystemGroupedBackground
                                  .resolveFrom(context),
                              borderRadius: BorderRadius.vertical(
                                top: isFirst
                                    ? const Radius.circular(10)
                                    : Radius.zero,
                                bottom: isLast
                                    ? const Radius.circular(10)
                                    : Radius.zero,
                              ),
                              border: isLast
                                  ? null
                                  : Border(
                                      bottom: BorderSide(
                                        color: CupertinoColors.separator
                                            .resolveFrom(context),
                                        width: 0.5,
                                      ),
                                    ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CupertinoListTile(
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
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
