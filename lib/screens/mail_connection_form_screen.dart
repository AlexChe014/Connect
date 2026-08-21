import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';

class MailConnectionFormScreen extends StatefulWidget {
  const MailConnectionFormScreen({super.key, this.existing});

  final MailConnection? existing;

  @override
  State<MailConnectionFormScreen> createState() => _MailConnectionFormScreenState();
}

class _MailConnectionFormScreenState extends State<MailConnectionFormScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController(text: '993');

  bool _isSaving = false;
  String? _errorText;

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

  String? _validate() {
    if (!_isEdit) {
      if (_emailController.text.trim().isEmpty) return 'Введите email';
      if (!_emailController.text.contains('@')) return 'Некорректный email';
      if (_imapHostController.text.trim().isEmpty) return 'Введите IMAP-хост';
      if (_imapPortController.text.trim().isEmpty) return 'Введите порт';
      if (int.tryParse(_imapPortController.text.trim()) == null) {
        return 'Некорректный порт';
      }
      if (_passwordController.text.isEmpty) return 'Введите пароль';
    } else {
      if (_imapPortController.text.trim().isNotEmpty &&
          int.tryParse(_imapPortController.text.trim()) == null) {
        return 'Некорректный порт';
      }
      if (_emailController.text.trim().isNotEmpty &&
          !_emailController.text.contains('@')) {
        return 'Некорректный email';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    setState(() => _errorText = error);
    if (error != null) return;

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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? 'Редактировать подключение' : 'Новый почтовый ящик'),
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
              if (!_isEdit)
                CupertinoFormSection.insetGrouped(
                  margin: EdgeInsets.zero,
                  header: const Text('ПОДКЛЮЧЕНИЕ'),
                  children: [
                    CupertinoTextFormFieldRow(
                      controller: _emailController,
                      prefix: const Text('Email'),
                      placeholder: 'name@example.com',
                      keyboardType: TextInputType.emailAddress,
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
                  ],
                )
              else
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
                    placeholder: _isEdit ? 'Необязательно' : null,
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
