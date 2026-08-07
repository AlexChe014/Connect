import 'package:connect/models/chat.dart';
import 'package:connect/services/chat_service.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    ChatService.instance.loadContacts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название группы')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одного участника')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать группу')),
      );
      return;
    }
    Navigator.of(context).pop<Chat>(c);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ChatService.instance.contacts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая группа'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Название группы',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Описание (необязательно)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          Text(
            'Участники',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...contacts.map((c) {
            if (c.userId <= 0) return const SizedBox.shrink();
            return CheckboxListTile(
              value: _selected.contains(c.userId),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(c.userId);
                  } else {
                    _selected.remove(c.userId);
                  }
                });
              },
              title: Text(c.fullName),
              contentPadding: EdgeInsets.zero,
            );
          }),
        ],
      ),
    );
  }
}
