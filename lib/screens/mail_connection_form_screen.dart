import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';
import '../services/api_client.dart';

enum MailProviderKind { yandex, mailru, corporate }

MailProviderKind mailProviderKindFromService(String? service) {
  switch (service?.trim().toLowerCase()) {
    case 'yandex':
      return MailProviderKind.yandex;
    case 'mailru':
      return MailProviderKind.mailru;
    default:
      return MailProviderKind.corporate;
  }
}

extension on MailProviderKind {
  String get title {
    switch (this) {
      case MailProviderKind.yandex:
        return 'Яндекс Почта';
      case MailProviderKind.mailru:
        return 'Mail';
      case MailProviderKind.corporate:
        return 'Корпоративная почта';
    }
  }

  String get serviceValue {
    switch (this) {
      case MailProviderKind.yandex:
        return 'yandex';
      case MailProviderKind.mailru:
        return 'mailru';
      case MailProviderKind.corporate:
        return 'other';
    }
  }

  String get passwordLabel {
    switch (this) {
      case MailProviderKind.yandex:
        return 'Пароль приложения';
      case MailProviderKind.mailru:
        return 'Пароль от почтового ящика';
      case MailProviderKind.corporate:
        return 'Пароль приложения';
    }
  }

  String? get passwordPlaceholder {
    switch (this) {
      case MailProviderKind.yandex:
        return '16-значный пароль приложения';
      case MailProviderKind.mailru:
        return null;
      case MailProviderKind.corporate:
        return null;
    }
  }

  String? get note {
    switch (this) {
      case MailProviderKind.yandex:
        return '⚠️ Важно: Обычный пароль от вашего аккаунта Яндекс не подойдет. '
            'Вам необходимо сгенерировать специальный Пароль приложения. '
            'Как это сделать: Перейдите в Яндекс ID → Безопасность → Пароли '
            'приложений → Создать пароль → Выберите тип «Почта». Скопируйте '
            'полученный 16-значный код и вставьте в поле выше.';
      case MailProviderKind.mailru:
        return 'Если в аккаунте включена двухфакторная аутентификация, вам '
            'потребуется сгенерировать специальный пароль для внешних '
            'приложений в настройках безопасности Mail.ru.';
      case MailProviderKind.corporate:
        return null;
    }
  }
}

class MailConnectionFormScreen extends StatefulWidget {
  const MailConnectionFormScreen({
    super.key,
    this.provider = MailProviderKind.corporate,
    this.existing,
  });

  final MailProviderKind provider;
  final MailConnection? existing;

  @override
  State<MailConnectionFormScreen> createState() => _MailConnectionFormScreenState();
}

class _MailConnectionFormScreenState extends State<MailConnectionFormScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController(text: '993');
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController(text: '465');
  bool _useSsl = true;

  bool _isSaving = false;
  String? _errorText;

  late final MailProviderKind _provider;

  bool get _isEdit => widget.existing != null;
  bool get _isCorporate => _provider == MailProviderKind.corporate;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _provider = existing != null
        ? mailProviderKindFromService(existing.service)
        : widget.provider;

    if (existing != null) {
      _loginController.text = existing.username ?? existing.email;
      _emailController.text = existing.email;
      _imapHostController.text = existing.customImapHost ?? existing.host ?? '';
      final imapPort = existing.customImapPort ?? existing.port;
      if (imapPort != null) _imapPortController.text = imapPort.toString();
      _smtpHostController.text = existing.smtpHost ?? '';
      if (existing.smtpPort != null) {
        _smtpPortController.text = existing.smtpPort.toString();
      }
      final encryption = (existing.customImapEncryption ?? existing.smtpEncryption)
          ?.trim()
          .toLowerCase();
      _useSsl = encryption == null || encryption == 'ssl' || encryption == 'tls';
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _imapHostController.dispose();
    _imapPortController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    super.dispose();
  }

  String? _validate() {
    if (!_isEdit) {
      if (_loginController.text.trim().isEmpty) return 'Введите email';
      if (!_loginController.text.contains('@')) return 'Некорректный email';
      if (_passwordController.text.isEmpty) return 'Введите пароль';
      if (_isCorporate) {
        if (_emailController.text.trim().isEmpty) {
          return 'Введите адрес электронной почты';
        }
        if (!_emailController.text.contains('@')) {
          return 'Некорректный адрес электронной почты';
        }
        if (_imapHostController.text.trim().isEmpty) return 'Введите IMAP-сервер';
        if (int.tryParse(_imapPortController.text.trim()) == null) {
          return 'Некорректный IMAP-порт';
        }
        if (_smtpHostController.text.trim().isEmpty) return 'Введите SMTP-сервер';
        if (int.tryParse(_smtpPortController.text.trim()) == null) {
          return 'Некорректный SMTP-порт';
        }
      }
    } else {
      if (_isCorporate) {
        if (_imapPortController.text.trim().isNotEmpty &&
            int.tryParse(_imapPortController.text.trim()) == null) {
          return 'Некорректный IMAP-порт';
        }
        if (_smtpPortController.text.trim().isNotEmpty &&
            int.tryParse(_smtpPortController.text.trim()) == null) {
          return 'Некорректный SMTP-порт';
        }
        if (_emailController.text.trim().isNotEmpty &&
            !_emailController.text.contains('@')) {
          return 'Некорректный адрес электронной почты';
        }
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
      final encryption = _isCorporate ? (_useSsl ? 'ssl' : null) : null;
      if (_isEdit) {
        await MailRepository.instance.updateConnection(
          connectionId: widget.existing!.id,
          request: UpdateMailConnectionRequest(
            password: _passwordController.text.isNotEmpty
                ? _passwordController.text
                : null,
            email: _isCorporate && _emailController.text.trim().isNotEmpty
                ? _emailController.text.trim()
                : null,
            username: _isCorporate && _loginController.text.trim().isNotEmpty
                ? _loginController.text.trim()
                : null,
            customImapHost: _isCorporate && _imapHostController.text.trim().isNotEmpty
                ? _imapHostController.text.trim()
                : null,
            customImapPort: _isCorporate
                ? int.tryParse(_imapPortController.text.trim())
                : null,
            customImapEncryption: encryption,
            smtpHost: _isCorporate && _smtpHostController.text.trim().isNotEmpty
                ? _smtpHostController.text.trim()
                : null,
            smtpPort: _isCorporate
                ? int.tryParse(_smtpPortController.text.trim())
                : null,
            smtpEncryption: encryption,
            canSend: _isCorporate ? true : null,
          ),
        );
      } else {
        await MailRepository.instance.createConnection(
          CreateMailConnectionRequest(
            service: _provider.serviceValue,
            email: _isCorporate
                ? _emailController.text.trim()
                : _loginController.text.trim(),
            password: _passwordController.text,
            username: _isCorporate ? _loginController.text.trim() : null,
            customImapHost:
                _isCorporate ? _imapHostController.text.trim() : null,
            customImapPort: _isCorporate
                ? int.tryParse(_imapPortController.text.trim())
                : null,
            customImapEncryption: encryption,
            smtpHost: _isCorporate ? _smtpHostController.text.trim() : null,
            smtpPort: _isCorporate
                ? int.tryParse(_smtpPortController.text.trim())
                : null,
            smtpEncryption: encryption,
            canSend: _isCorporate ? true : null,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : (_isEdit ? 'Не удалось обновить подключение' : 'Не удалось создать подключение');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message)),
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
        middle: Text(_isEdit ? 'Редактировать подключение' : _provider.title),
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
                    CupertinoTextFormFieldRow(
                      controller: _loginController,
                      prefix: const Text('Email (Логин)'),
                      placeholder: 'name@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textAlign: TextAlign.end,
                      enabled: !_isSaving,
                    ),
                    CupertinoTextFormFieldRow(
                      controller: _passwordController,
                      prefix: Text(_provider.passwordLabel),
                      placeholder: _provider.passwordPlaceholder,
                      obscureText: true,
                      textAlign: TextAlign.end,
                      enabled: !_isSaving,
                    ),
                  ],
                ),
                if (_provider.note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(
                      _provider.note!,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                if (_isCorporate) ...[
                  const SizedBox(height: 20),
                  CupertinoFormSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: const Text('АДРЕС ОТПРАВИТЕЛЯ'),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _emailController,
                        prefix: const Text('Адрес почты'),
                        placeholder: 'name@company.com',
                        keyboardType: TextInputType.emailAddress,
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CupertinoFormSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: const Text('IMAP'),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _imapHostController,
                        prefix: const Text('IMAP-сервер'),
                        placeholder: 'imap.company.com',
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _imapPortController,
                        prefix: const Text('IMAP-порт'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CupertinoFormSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: const Text('SMTP'),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _smtpHostController,
                        prefix: const Text('SMTP-сервер'),
                        placeholder: 'smtp.company.com',
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _smtpPortController,
                        prefix: const Text('SMTP-порт'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CupertinoListSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    children: [
                      CupertinoListTile(
                        title: const Text('Использовать SSL'),
                        trailing: CupertinoSwitch(
                          value: _useSsl,
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(() => _useSsl = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
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
                      subtitle: Text(_provider.title),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CupertinoFormSection.insetGrouped(
                  margin: EdgeInsets.zero,
                  children: [
                    CupertinoTextFormFieldRow(
                      controller: _passwordController,
                      prefix: Text(_provider.passwordLabel),
                      placeholder: 'Необязательно',
                      obscureText: true,
                      textAlign: TextAlign.end,
                      enabled: !_isSaving,
                    ),
                  ],
                ),
                if (_isCorporate) ...[
                  const SizedBox(height: 20),
                  CupertinoFormSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: const Text('АДРЕС ОТПРАВИТЕЛЯ'),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _emailController,
                        prefix: const Text('Адрес почты'),
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CupertinoFormSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: const Text('IMAP'),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _imapHostController,
                        prefix: const Text('IMAP-сервер'),
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _imapPortController,
                        prefix: const Text('IMAP-порт'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CupertinoFormSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: const Text('SMTP'),
                    children: [
                      CupertinoTextFormFieldRow(
                        controller: _smtpHostController,
                        prefix: const Text('SMTP-сервер'),
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                      CupertinoTextFormFieldRow(
                        controller: _smtpPortController,
                        prefix: const Text('SMTP-порт'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CupertinoListSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    children: [
                      CupertinoListTile(
                        title: const Text('Использовать SSL'),
                        trailing: CupertinoSwitch(
                          value: _useSsl,
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(() => _useSsl = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
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
