import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';
import '../services/api_client.dart';
import '../services/mail_sync_notice_service.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/booking_glass_form.dart';

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
  State<MailConnectionFormScreen> createState() =>
      _MailConnectionFormScreenState();
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
      final encryption =
          (existing.customImapEncryption ?? existing.smtpEncryption)
              ?.trim()
              .toLowerCase();
      _useSsl =
          encryption == null || encryption == 'ssl' || encryption == 'tls';
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
        if (_imapHostController.text.trim().isEmpty)
          return 'Введите IMAP-сервер';
        if (int.tryParse(_imapPortController.text.trim()) == null) {
          return 'Некорректный IMAP-порт';
        }
        if (_smtpHostController.text.trim().isEmpty)
          return 'Введите SMTP-сервер';
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

  /// Письма с сервера подтягиваются не сразу — предупреждаем, чтобы пустой
  /// список во входящих не выглядел как ошибка.
  Future<void> _showSyncNotice() {
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Ящик подключён'),
        content: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Письма будут загружены в ближайшее время. Загрузка идёт '
            'постепенно и может занять до нескольких часов, если в ящике '
            'много писем.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
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
            customImapHost:
                _isCorporate && _imapHostController.text.trim().isNotEmpty
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
        final created = await MailRepository.instance.createConnection(
          CreateMailConnectionRequest(
            service: _provider.serviceValue,
            email: _isCorporate
                ? _emailController.text.trim()
                : _loginController.text.trim(),
            password: _passwordController.text,
            username: _isCorporate ? _loginController.text.trim() : null,
            customImapHost: _isCorporate
                ? _imapHostController.text.trim()
                : null,
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
        final email = created.email.isNotEmpty
            ? created.email
            : (_isCorporate ? _emailController.text : _loginController.text);
        await MailSyncNoticeService.instance.markConnected(email);
        if (!mounted) return;
        await _showSyncNotice();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : (_isEdit
                ? 'Не удалось обновить подключение'
                : 'Не удалось создать подключение');
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Поле формы: подпись слева, ввод справа — как в «Настройках» iOS.
  Widget _field(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? placeholder,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    final color = CupertinoColors.label.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 15, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              keyboardType: keyboardType,
              obscureText: obscureText,
              autocorrect: false,
              enableSuggestions: !obscureText,
              textAlign: TextAlign.end,
              enabled: !_isSaving,
              decoration: const BoxDecoration(),
              padding: const EdgeInsets.symmetric(vertical: 13),
              style: TextStyle(fontSize: 15, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// IMAP/SMTP и SSL — общие для подключения и редактирования
  /// корпоративного ящика; в режиме правки подсказок в полях нет.
  List<Widget> _buildServerSections(BuildContext context) {
    final hints = !_isEdit;
    return [
      const AppGlassSectionLabel('Адрес отправителя'),
      AppGlassSection(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _field(
            context,
            label: 'Адрес почты',
            controller: _emailController,
            placeholder: hints ? 'name@company.com' : null,
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
      const AppGlassSectionLabel('IMAP'),
      AppGlassSection(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _field(
            context,
            label: 'Сервер',
            controller: _imapHostController,
            placeholder: hints ? 'imap.company.com' : null,
            keyboardType: TextInputType.url,
          ),
          _field(
            context,
            label: 'Порт',
            controller: _imapPortController,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      const AppGlassSectionLabel('SMTP'),
      AppGlassSection(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _field(
            context,
            label: 'Сервер',
            controller: _smtpHostController,
            placeholder: hints ? 'smtp.company.com' : null,
            keyboardType: TextInputType.url,
          ),
          _field(
            context,
            label: 'Порт',
            controller: _smtpPortController,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      AppGlassSection(
        children: [
          BookingSwitchRow(
            icon: CupertinoIcons.lock_shield_fill,
            color: CupertinoColors.systemGreen.resolveFrom(context),
            label: 'Использовать SSL',
            value: _useSsl,
            onChanged: (value) {
              if (!_isSaving) setState(() => _useSsl = value);
            },
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return BookingGlassScaffold(
      title: _isEdit ? 'Подключение' : _provider.title,
      canPop: !_isSaving,
      trailing: BookingNavAction(
        label: _isEdit ? 'Сохранить' : 'Подключить',
        isLoading: _isSaving,
        onPressed: _save,
      ),
      children: [
        if (existing == null) ...[
          const AppGlassSectionLabel(
            'Подключение',
            padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
          ),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _field(
                context,
                label: _isCorporate ? 'Логин' : 'E-mail',
                controller: _loginController,
                placeholder: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              _field(
                context,
                label: _provider.passwordLabel,
                controller: _passwordController,
                placeholder: _provider.passwordPlaceholder,
                obscureText: true,
              ),
            ],
          ),
          if (_provider.note != null) BookingFootnote(_provider.note!),
        ] else ...[
          AppGlassSection(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            children: [
              CupertinoListTile(
                leading: AppIconBadge(
                  icon: CupertinoIcons.mail_solid,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
                title: Text(existing.email),
                subtitle: Text(_provider.title),
              ),
            ],
          ),
          AppGlassSection(
            children: [
              _field(
                context,
                label: _provider.passwordLabel,
                controller: _passwordController,
                placeholder: 'Без изменений',
                obscureText: true,
              ),
            ],
          ),
          const BookingFootnote('Оставьте пустым, чтобы не менять пароль.'),
        ],
        if (_isCorporate) ..._buildServerSections(context),
        if (_errorText != null) BookingFootnote(_errorText!, isError: true),
      ],
    );
  }
}
