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
  final _selected = <int>{};
  bool _creating = false;
  String? _nameError;
  final _chat = ChatService.instance;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChat);
    _chat.loadContacts();
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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
    final contacts = _chat.contacts.where((c) => c.userId > 0).toList();
    final contactsLoading = _chat.isContactsLoading && contacts.isEmpty;

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
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              CupertinoFormSection.insetGrouped(
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
              if (_nameError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    _nameError!,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 13,
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
              if (contactsLoading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: List.generate(
                      6,
                      (index) => const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: AppSkeletonCardTile(),
                      ),
                    ),
                  ),
                )
              else if (contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Нет доступных контактов',
                    style: TextStyle(color: CupertinoColors.secondaryLabel),
                  ),
                )
              else
                CupertinoListSection.insetGrouped(
                  children: contacts.map((c) {
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
      ),
    );
  }
}
