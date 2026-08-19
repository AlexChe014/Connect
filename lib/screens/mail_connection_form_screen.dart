import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';
import '../widgets/booking_pickers.dart';

class MailConnectionFormScreen extends StatefulWidget {
  const MailConnectionFormScreen({super.key, this.existing});

  final MailConnection? existing;

  @override
  State<MailConnectionFormScreen> createState() => _MailConnectionFormScreenState();
}

class _MailConnectionFormScreenState extends State<MailConnectionFormScreen> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController(text: '993');

  String _service = 'yandex';
  String _encryption = 'ssl';
  bool _isSaving = false;
  String? _errorText;

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

  String? _validate() {
    if (!_isEdit) {
      if (_emailController.text.trim().isEmpty) return 'Введите email';
      if (!_emailController.text.contains('@')) return 'Некорректный email';
      if (_usernameController.text.trim().isEmpty) {
        return 'Введите имя пользователя';
      }
      if (_service == 'other' && _imapHostController.text.trim().isEmpty) {
        return 'Введите IMAP-хост';
      }
    }
    if (_passwordController.text.isEmpty) return 'Введите пароль';
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    setState(() => _errorText = error);
    if (error != null) return;

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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? 'Обновить пароль' : 'Новый почтовый ящик'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 26),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const CupertinoActivityIndicator()
              : Text(
                  _isEdit ? 'Сохранить' : 'Подключить',
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (!_isEdit) ...[
                CupertinoFormSection.insetGrouped(
                  margin: EdgeInsets.zero,
                  header: const Text('ПОДКЛЮЧЕНИЕ'),
                  children: [
                    CupertinoListTile(
                      title: const Text('Сервис'),
                      additionalInfo: Text(_knownServices[_service] ?? _service),
                      trailing: const CupertinoListTileChevron(),
                      onTap: _isSaving
                          ? null
                          : () async {
                              final picked = await showBookingOptionSheet<String>(
                                context: context,
                                title: 'Сервис',
                                options: _knownServices.keys.toList(),
                                current: _service,
                                labelOf: (key) => _knownServices[key] ?? key,
                              );
                              if (picked != null) setState(() => _service = picked);
                            },
                    ),
                    CupertinoTextFormFieldRow(
                      controller: _emailController,
                      prefix: const Text('Email'),
                      placeholder: 'name@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textAlign: TextAlign.end,
                      enabled: !_isSaving,
                    ),
                    CupertinoTextFormFieldRow(
                      controller: _usernameController,
                      prefix: const Text('Логин'),
                      textAlign: TextAlign.end,
                      enabled: !_isSaving,
                    ),
                  ],
                ),
                if (_service == 'other') ...[
                  const SizedBox(height: 20),
                  CupertinoFormSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: const Text('IMAP'),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _nameController,
                        prefix: const Text('Название'),
                        placeholder: 'Необязательно',
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _imapHostController,
                        prefix: const Text('Хост'),
                        placeholder: 'imap.example.com',
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _imapPortController,
                        prefix: const Text('Порт'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                      CupertinoListTile(
                        title: const Text('Шифрование'),
                        additionalInfo: Text(
                          _encryptionLabels[_encryption] ?? _encryption,
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: _isSaving
                            ? null
                            : () async {
                                final picked = await showBookingOptionSheet<String>(
                                  context: context,
                                  title: 'Шифрование',
                                  options: _encryptionLabels.keys.toList(),
                                  current: _encryption,
                                  labelOf: (key) =>
                                      _encryptionLabels[key] ?? key,
                                );
                                if (picked != null) {
                                  setState(() => _encryption = picked);
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ] else
                CupertinoListSection.insetGrouped(
                  margin: EdgeInsets.zero,
                  children: [
                    CupertinoListTile(
                      leading: Container(
                        width: 29,
                        height: 29,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CupertinoColors.activeBlue,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          CupertinoIcons.mail_solid,
                          size: 16,
                          color: CupertinoColors.white,
                        ),
                      ),
                      title: Text(widget.existing!.email),
                      subtitle: Text(widget.existing!.serviceLabel),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              CupertinoFormSection.insetGrouped(
                margin: EdgeInsets.zero,
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _passwordController,
                    prefix: Text(_isEdit ? 'Новый пароль' : 'Пароль'),
                    obscureText: true,
                    textAlign: TextAlign.end,
                    enabled: !_isSaving,
                  ),
                ],
              ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
