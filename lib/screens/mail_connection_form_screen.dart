import 'package:flutter/material.dart';

import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';

class MailConnectionFormScreen extends StatefulWidget {
  const MailConnectionFormScreen({super.key, this.existing});

  final MailConnection? existing;

  @override
  State<MailConnectionFormScreen> createState() => _MailConnectionFormScreenState();
}

class _MailConnectionFormScreenState extends State<MailConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController(text: '993');

  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _emailController.text = existing.email;
      _imapHostController.text = existing.host ?? existing.customImapHost ?? '';
      final portValue = existing.port ?? existing.customImapPort;
      if (portValue != null) {
        _imapPortController.text = portValue.toString();
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _imapHostController.dispose();
    _imapPortController.dispose();
    super.dispose();
  }


  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_isEdit) {
        await MailRepository.instance.updateConnection(
          connectionId: widget.existing!.id,
          request: UpdateMailConnectionRequest(
            host: _imapHostController.text.trim().isNotEmpty
                ? _imapHostController.text.trim()
                : null,
            port: int.tryParse(_imapPortController.text.trim()),
            email: _emailController.text.trim().isNotEmpty
                ? _emailController.text.trim()
                : null,
            password: _passwordController.text.isNotEmpty
                ? _passwordController.text
                : null,
          ),
        );
      } else {
        await MailRepository.instance.createConnection(
          CreateMailConnectionRequest(
            host: _imapHostController.text.trim(),
            port: int.tryParse(_imapPortController.text.trim()) ?? 993,
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? 'Не удалось обновить подключение' : 'Не удалось создать подключение',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Редактировать подключение' : 'Новый почтовый ящик',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) {
                if (!_isEdit && (v == null || v.trim().isEmpty)) return 'Введите email';
                if (v != null && v.trim().isNotEmpty && !v.contains('@')) {
                  return 'Некорректный email';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _imapHostController,
              decoration: const InputDecoration(labelText: 'IMAP-хост'),
              validator: (v) {
                if (!_isEdit && (v == null || v.trim().isEmpty)) return 'Введите IMAP-хост';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _imapPortController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'IMAP-порт'),
              validator: (v) {
                if (!_isEdit && (v == null || v.trim().isEmpty)) return 'Введите порт';
                if (v != null && v.trim().isNotEmpty && int.tryParse(v.trim()) == null) {
                  return 'Некорректный порт';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _isEdit ? 'Новый пароль (необязательно)' : 'Пароль',
              ),
              validator: (v) {
                if (!_isEdit && (v == null || v.isEmpty)) return 'Введите пароль';
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEdit ? 'Сохранить' : 'Подключить'),
            ),
          ],
        ),
      ),
    );
  }
}
