import 'package:connect/models/chat.dart';
import 'package:connect/services/chat_service.dart';
import 'package:flutter/material.dart';

/// Мок-список сотрудников для добавления в группу.
const _mockContacts = <String>[
  'Анна Смирнова',
  'Пётр Волков',
  'Мария Орлова',
  'IT-поддержка',
  'Ольга Новикова',
  'Сергей Лебедев',
];

class CreateGroupChatScreen extends StatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final _nameCtrl = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
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
    final c = await ChatService.instance.createGroup(
      title: name,
      otherMemberNames: _selected.toList(),
    );
    if (mounted) Navigator.of(context).pop<Chat>(c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая группа'),
        actions: [
          TextButton(
            onPressed: _create,
            child: const Text('Создать'),
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
          const SizedBox(height: 24),
          Text(
            'Участники',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ..._mockContacts.map((n) {
            return CheckboxListTile(
              value: _selected.contains(n),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(n);
                  } else {
                    _selected.remove(n);
                  }
                });
              },
              title: Text(n),
              contentPadding: EdgeInsets.zero,
            );
          }),
        ],
      ),
    );
  }
}
