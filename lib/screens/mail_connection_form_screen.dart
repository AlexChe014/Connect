import 'package:flutter/material.dart';

import '../config/app_icons.dart';
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
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController(text: '993');

  String _service = 'yandex';
  String _encryption = 'ssl';
  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  static const _knownServices = <String, String>{
    'yandex': 'Yandex',
    'gmail': 'Gmail',
    'mailru': 'Mail.ru',
    'other': 'Другой (IMAP)',
  };

  static const _encryptionLabels = <String, String>{
    'ssl': 'SSL',
    'tls': 'TLS',
    'none': 'Без шифрования',
  };

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _emailController.text = existing.email;
      _usernameController.text = existing.username ?? '';
      _nameController.text = existing.name ?? '';
      _imapHostController.text = existing.customImapHost ?? '';
      if (existing.customImapPort != null) {
        _imapPortController.text = existing.customImapPort.toString();
      }
      _encryption = existing.customImapEncryption ?? 'ssl';
      _service = existing.isCustom ? 'other' : (existing.service?.toLowerCase() ?? 'yandex');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _imapHostController.dispose();
    _imapPortController.dispose();
    super.dispose();
  }

  Future<String?> _pickOption({
    required String title,
    required Map<String, String> options,
    required String current,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              ...options.entries.map(
                (e) => ListTile(
                  dense: true,
                  title: Text(e.value),
                  trailing: e.key == current
                      ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(context, e.key),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _optionField({
    required String label,
    required String valueLabel,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isSaving ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.keyboard_arrow_down),
        ),
        child: Text(valueLabel),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_isEdit) {
        await MailRepository.instance.updateConnectionPassword(
          connectionId: widget.existing!.id,
          password: _passwordController.text,
        );
      } else {
        await MailRepository.instance.createConnection(
          CreateMailConnectionRequest(
            service: _service == 'other' ? 'other' : _service,
            email: _emailController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
            customImapHost: _service == 'other' ? _imapHostController.text.trim() : null,
            customImapPort: _service == 'other'
                ? int.tryParse(_imapPortController.text.trim())
                : null,
            customImapEncryption: _service == 'other' ? _encryption : null,
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
            _isEdit ? 'Не удалось обновить пароль' : 'Не удалось создать подключение',
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
          _isEdit ? 'Обновить пароль' : 'Новый почтовый ящик',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEdit) ...[
              _optionField(
                label: 'Сервис',
                valueLabel: _knownServices[_service] ?? _service,
                onTap: () async {
                  final picked = await _pickOption(
                    title: 'Сервис',
                    options: _knownServices,
                    current: _service,
                  );
                  if (picked != null) setState(() => _service = picked);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Введите email';
                  if (!v.contains('@')) return 'Некорректный email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Имя пользователя'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Введите имя пользователя' : null,
              ),
              const SizedBox(height: 12),
              if (_service == 'other') ...[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Название (необязательно)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imapHostController,
                  decoration: const InputDecoration(labelText: 'IMAP-хост'),
                  validator: (v) => _service == 'other' && (v == null || v.trim().isEmpty)
                      ? 'Введите IMAP-хост'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imapPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'IMAP-порт'),
                ),
                const SizedBox(height: 12),
                _optionField(
                  label: 'Шифрование',
                  valueLabel: _encryptionLabels[_encryption] ?? _encryption,
                  onTap: () async {
                    final picked = await _pickOption(
                      title: 'Шифрование',
                      options: _encryptionLabels,
                      current: _encryption,
                    );
                    if (picked != null) setState(() => _encryption = picked);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ] else
              Card(
                child: ListTile(
                  leading: const AppIcon(AppIcons.mailAt),
                  title: Text(widget.existing!.email),
                  subtitle: Text(widget.existing!.serviceLabel),
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _isEdit ? 'Новый пароль' : 'Пароль',
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Введите пароль' : null,
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
