import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mail/mail_connection.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/booking_glass_form.dart';
import '../utils/file_size_format.dart';
import '../widgets/mail_glass.dart';
import '../widgets/mail_recipient_field.dart';
import '../widgets/staff_user_picker_sheet.dart';
import 'mail_provider_picker_screen.dart';
import 'mail_screen.dart';
import '../services/haptics_service.dart';

class _PendingAttachment {
  final String filename;
  final List<int> bytes;

  const _PendingAttachment({required this.filename, required this.bytes});
}

class ComposeMailScreen extends StatefulWidget {
  const ComposeMailScreen({
    super.key,
    required this.connection,
    this.replyTo,
    this.replyAll = false,
    this.forwardOf,
    this.initialTo = const [],
  });

  final MailConnection connection;

  /// Готовые получатели нового письма — например, из карточки сотрудника.
  final List<MailRecipient> initialTo;
  final MailMessage? replyTo;

  /// Ответить всем: в «Кому» — отправитель и все получатели исходного
  /// письма (включая копию), кроме своего адреса.
  final bool replyAll;
  final MailMessage? forwardOf;

  /// Новое письмо из приложения (кнопка «Почта» в карточке сотрудника):
  /// отправляем с ящика по умолчанию. Если ящик не подключён — предлагаем
  /// подключить его или открыть стороннюю почту.
  static Future<void> openNew(
    BuildContext context, {
    required MailRecipient to,
  }) async {
    List<MailConnection> connections;
    try {
      connections = await MailScreen.loadConnectionsForCurrentUser();
    } catch (_) {
      connections = const [];
    }
    if (!context.mounted) return;
    final sendable = connections.where((c) => c.canSend && c.isActive);
    final connection =
        sendable.where((c) => c.isDefault).firstOrNull ?? sendable.firstOrNull;
    if (connection != null) {
      await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (context) =>
              ComposeMailScreen(connection: connection, initialTo: [to]),
        ),
      );
      return;
    }

    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Почта не подключена'),
        message: const Text(
          'Подключите свой почтовый ящик, чтобы писать письма из приложения.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, 'connect'),
            child: const Text('Подключить ящик'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'external'),
            child: const Text('Открыть другую почту'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'external') {
      await launchUrl(Uri(scheme: 'mailto', path: to.email));
    } else if (choice == 'connect') {
      final created = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (context) => const MailProviderPickerScreen(),
        ),
      );
      if (created == true && context.mounted) {
        await openNew(context, to: to);
      }
    }
  }

  @override
  State<ComposeMailScreen> createState() => _ComposeMailScreenState();
}

class _ComposeMailScreenState extends State<ComposeMailScreen> {
  late final MailRecipientController _toController;
  late final MailRecipientController _ccController;
  final _bccController = MailRecipientController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  static const _forwardMarker = '---------- Пересланное сообщение ----------';

  final List<_PendingAttachment> _attachments = [];
  bool _isSending = false;
  String? _toError;
  String? _copyError;
  String? _subjectError;

  /// Поля «Копия» и «Скрытая» свёрнуты в одну строку, пока их не открыли —
  /// как в «Почте» iOS.
  bool _showCopyFields = false;

  /// Значения полей при открытии — чтобы понять, есть ли что терять
  /// при выходе без отправки.
  late final String _initialTo;
  late final String _initialCc;

  static const _labelWidth = 72.0;

  /// SendEmailRequest: `attachments_files.*` — `max:10240` (КБ). Больше —
  /// сервер отвечает 422 уже после нажатия «Отправить».
  static const _maxAttachmentBytes = 10240 * 1024;
  late final String _initialSubject;
  late final String _initialBody;

  static final _replyPrefix = RegExp(
    r'^\s*(re|ответ|aw|sv)\s*:',
    caseSensitive: false,
  );
  static final _forwardPrefix = RegExp(
    r'^\s*(fwd?|пересл|tr|wg)\s*:',
    caseSensitive: false,
  );

  String _ownEmail() => widget.connection.email.trim().toLowerCase();

  bool _isOwn(String address) =>
      mailEmailOnly(address).toLowerCase() == _ownEmail();

  /// Кому отвечать. На своё письмо (из «Отправленных») — его получателям,
  /// а не себе; «всем» — отправителю и получателям без себя (копия исходного
  /// письма уходит в поле «Копия», см. [_replyAllCopy]).
  List<String> _replyRecipients(MailMessage message) {
    final from = message.from.trim();
    final to = MailMessage.splitAddresses(message.to);
    final candidates = <String>[
      if (!_isOwn(from) && from.isNotEmpty) from,
      if (widget.replyAll || _isOwn(from)) ...to,
    ];
    final seen = <String>{};
    final result = candidates
        .where((a) => !_isOwn(a))
        .where((a) => seen.add(mailEmailOnly(a).toLowerCase()))
        .toList();
    return result.isEmpty && from.isNotEmpty ? [from] : result;
  }

  /// «Ответить всем»: копия исходного письма без себя и без тех, кто уже
  /// в «Кому».
  List<String> _replyAllCopy(MailMessage message, List<String> to) {
    final seen = to.map((a) => mailEmailOnly(a).toLowerCase()).toSet();
    return MailMessage.splitAddresses(message.cc)
        .where((a) => !_isOwn(a))
        .where((a) => seen.add(mailEmailOnly(a).toLowerCase()))
        .toList();
  }

  /// `/mail/smtp/reply` игнорирует `to` и `subject` из запроса: шлёт всегда
  /// на `from` исходного письма с темой «Re: …» (копию учитывает). Ответ на
  /// своё письмо из «Отправленных» уходил самому себе, а в «Ответить всем»
  /// терялись все из «Кому», кроме отправителя. Поэтому reply используем,
  /// только когда сервер отправит то же, что видно на экране, иначе — обычная
  /// отправка (без связи с перепиской). См. docs/BACKEND_MAIL_FIXES.md, п. 14.
  bool _replyMatchesServer(MailMessage replyTo) {
    final from = mailEmailOnly(replyTo.from).toLowerCase();
    final to = _toController.emails.map((e) => e.toLowerCase()).toList();
    return from.isNotEmpty &&
        !_isOwn(replyTo.from) &&
        to.length == 1 &&
        to.single == from &&
        _subjectController.text.trim() == _initialSubject.trim();
  }

  @override
  void initState() {
    super.initState();
    final replyTo = widget.replyTo;
    final forwardOf = widget.forwardOf;
    final dateFormat = DateFormat('d MMMM yyyy, HH:mm', 'ru_RU');
    final to = replyTo != null ? _replyRecipients(replyTo) : const <String>[];
    _toController = MailRecipientController([
      ...widget.initialTo,
      ...to.map(MailRecipient.parse),
    ]);
    _ccController = MailRecipientController(
      replyTo != null && widget.replyAll
          ? _replyAllCopy(replyTo, to).map(MailRecipient.parse)
          : const [],
    );
    _showCopyFields = _ccController.recipients.isNotEmpty;
    if (replyTo != null) {
      _subjectController.text = _replyPrefix.hasMatch(replyTo.subject)
          ? replyTo.subject
          : 'Re: ${replyTo.subject}';
      final quote = replyTo.previewBody;
      if (quote.isNotEmpty) {
        final date = replyTo.date;
        final header = date == null
            ? '${replyTo.from} пишет:'
            : '${dateFormat.format(date.toLocal())}, ${replyTo.from} пишет:';
        _bodyController.text = '\n\n$header\n$quote';
      }
    } else if (forwardOf != null) {
      _subjectController.text = _forwardPrefix.hasMatch(forwardOf.subject)
          ? forwardOf.subject
          : 'Fwd: ${forwardOf.subject}';
      final quote = forwardOf.previewBody;
      final date = forwardOf.date;
      _bodyController.text =
          '\n\n$_forwardMarker\n'
          'От: ${forwardOf.from}\n'
          '${date == null ? '' : 'Дата: ${dateFormat.format(date.toLocal())}\n'}'
          'Тема: ${forwardOf.subject}\n'
          '${(forwardOf.to ?? '').isEmpty ? '' : 'Кому: ${forwardOf.to}\n'}'
          '\n$quote';
    }
    _initialTo = _toController.snapshot;
    _initialCc = _ccController.snapshot;
    _initialSubject = _subjectController.text;
    _initialBody = _bodyController.text;
  }

  bool get _hasUnsavedChanges =>
      _attachments.isNotEmpty ||
      _toController.snapshot != _initialTo ||
      _ccController.snapshot != _initialCc ||
      !_bccController.isEmpty ||
      _subjectController.text != _initialSubject ||
      _bodyController.text != _initialBody;

  /// Выход без отправки: набранное письмо пропадало молча.
  Future<void> _confirmDiscard() async {
    final discard = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Письмо не отправлено'),
        message: const Text('Если выйти, набранный текст будет потерян.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить черновик'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Продолжить редактирование'),
        ),
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  /// Вложения в ответе сервер пока не принимает — до доработки бэкенда
  /// (replyAttachmentsSupported) кнопку прикрепления не показываем.
  /// Пересылка идёт через /mail/smtp/send, там вложения работают.
  bool get _canAttach =>
      widget.replyTo == null || MailRepository.replyAttachmentsSupported;

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    // withData обязателен: без него на iOS/Android FilePicker отдаёт файлы
    // только с заполненным path, а bytes всегда null — вложения молча
    // терялись при отправке.
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final picked = <_PendingAttachment>[];
    final tooLarge = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      if (bytes.length > _maxAttachmentBytes) {
        tooLarge.add(file.name);
        continue;
      }
      picked.add(_PendingAttachment(filename: file.name, bytes: bytes));
    }
    if (!mounted) return;
    if (tooLarge.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            tooLarge.length == 1
                ? 'Файл «${tooLarge.single}» больше 10 МБ — такие сервер не принимает'
                : 'Файлы больше 10 МБ не добавлены: ${tooLarge.join(', ')}',
          ),
        ),
      );
    }
    if (picked.isEmpty) return;
    setState(() => _attachments.addAll(picked));
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  List<MailRecipientController> get _fields => [
    _toController,
    _ccController,
    _bccController,
  ];

  /// Получатели одной строкой в формате списка адресов (RFC 5322) —
  /// так `to` и уходит на сервер.
  String get _toValue => _toController.emails.join(', ');

  /// Добавляет в поле сотрудников из справочника компании. Шторка не
  /// закрывается после выбора — можно отметить сразу несколько человек,
  /// повторное нажатие снимает отметку.
  Future<void> _pickEmployees(MailRecipientController field) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await StaffUserPickerSheet.show(
      context,
      title: 'Получатели',
      selectedIds: field.userIds,
      validateUser: (user) {
        final email = user.email?.trim() ?? '';
        if (email.isEmpty) {
          return 'У сотрудника ${user.fullName} не указан e-mail';
        }
        if (_fields.any((f) => f.contains(email))) {
          return '$email уже есть среди получателей';
        }
        return null;
      },
      onUserSelected: (user) {
        field.add(MailRecipient.fromStaff(user));
        _clearRecipientErrors();
      },
      onUserDeselected: (user) => field.removeUser(user.id),
    );
  }

  void _clearRecipientErrors() {
    if (_toError == null && _copyError == null) return;
    setState(() {
      _toError = null;
      _copyError = null;
    });
  }

  bool _validate() {
    final invalid = _toController.commitInput();
    final invalidCopy = [
      ..._ccController.commitInput(),
      ..._bccController.commitInput(),
    ];
    final subject = _subjectController.text.trim();
    setState(() {
      _toError = invalid.isNotEmpty
          ? 'Некорректный email: ${invalid.join(', ')}'
          : _toController.recipients.isEmpty
          ? 'Введите адрес получателя'
          : null;
      _copyError = invalidCopy.isEmpty
          ? null
          : 'Некорректный email в копии: ${invalidCopy.join(', ')}';
      if (_copyError != null) _showCopyFields = true;
      _subjectError = subject.isEmpty ? 'Введите тему письма' : null;
    });
    return _toError == null && _copyError == null && _subjectError == null;
  }

  Future<void> _send() async {
    if (_isSending) return;
    if (!_validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _isSending = true);
    try {
      final replyTo = widget.replyTo;
      final forwardOf = widget.forwardOf;
      final files = _attachments
          .map((a) => MailUpload(filename: a.filename, bytes: a.bytes))
          .toList();
      final cc = _ccController.emails;
      final bcc = _bccController.emails;
      // /mail/smtp/reply/{email} отправляет с ящика исходного письма и
      // связывает ответ с перепиской, но адресатов и тему берёт сам.
      if (replyTo != null && _replyMatchesServer(replyTo)) {
        await MailRepository.instance.replyMail(
          ReplyMailRequest(
            messageId: replyTo.id,
            to: _toValue,
            subject: _subjectController.text.trim(),
            body: _bodyController.text,
            cc: cc,
            bcc: bcc,
            attachments: files,
          ),
        );
      } else if (forwardOf != null) {
        await MailRepository.instance.forwardMail(
          ForwardMailRequest(
            connectionId: widget.connection.id,
            messageId: forwardOf.id,
            to: _toValue,
            subject: _subjectController.text.trim(),
            body: _bodyController.text,
            cc: cc,
            bcc: bcc,
            attachments: files,
          ),
        );
      } else {
        // Новое письмо — и ответ, который сервер отправил бы не тем людям
        // (см. [_replyMatchesServer]).
        await MailRepository.instance.sendMail(
          SendMailRequest(
            connectionId: widget.connection.id,
            to: _toValue,
            subject: _subjectController.text.trim(),
            body: _bodyController.text,
            cc: cc,
            bcc: bcc,
            attachments: files,
          ),
        );
      }
      AppHaptics.success();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      AppHaptics.error();
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось отправить письмо';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _fieldLabel(BuildContext context, String text) {
    return SizedBox(
      width: _labelWidth,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  Widget _separator(BuildContext context) => Container(
    height: 0.5,
    margin: const EdgeInsets.only(left: 16),
    color: CupertinoColors.separator.resolveFrom(context),
  );

  /// «Кому», «Копия», «От» и «Тема» — одной стеклянной карточкой с
  /// подписями слева, как в «Почте» iOS.
  Widget _buildHeaderFields(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final fieldStyle = TextStyle(fontSize: 15, color: label);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: Column(
          children: [
            MailRecipientField(
              label: 'Кому:',
              controller: _toController,
              labelWidth: _labelWidth,
              placeholder: 'Имя или email',
              enabled: !_isSending,
              onChanged: _clearRecipientErrors,
              onPickEmployees: () => _pickEmployees(_toController),
            ),
            _separator(context),
            if (_showCopyFields) ...[
              MailRecipientField(
                label: 'Копия:',
                controller: _ccController,
                labelWidth: _labelWidth,
                enabled: !_isSending,
                onChanged: _clearRecipientErrors,
                onPickEmployees: () => _pickEmployees(_ccController),
              ),
              _separator(context),
              MailRecipientField(
                label: 'Скрытая:',
                controller: _bccController,
                labelWidth: _labelWidth,
                enabled: !_isSending,
                onChanged: _clearRecipientErrors,
                onPickEmployees: () => _pickEmployees(_bccController),
              ),
            ] else
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isSending
                    ? null
                    : () => setState(() => _showCopyFields = true),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Копия, скрытая копия',
                          style: TextStyle(
                            fontSize: 15,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 15,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _separator(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  _fieldLabel(context, 'От:'),
                  Expanded(
                    child: Text(
                      widget.connection.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _separator(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  _fieldLabel(context, 'Тема:'),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _subjectController,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 3,
                      enabled: !_isSending,
                      decoration: const BoxDecoration(),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      style: fieldStyle.copyWith(fontWeight: FontWeight.w600),
                      onChanged: (_) {
                        if (_subjectError != null) {
                          setState(() => _subjectError = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: CupertinoTextField(
          controller: _bodyController,
          minLines: 10,
          maxLines: null,
          enabled: !_isSending,
          textCapitalization: TextCapitalization.sentences,
          placeholder: 'Текст письма',
          decoration: const BoxDecoration(),
          padding: const EdgeInsets.all(16),
          style: TextStyle(
            fontSize: 16,
            height: 1.35,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachments(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    return AppGlassSection(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      children: [
        for (var index = 0; index < _attachments.length; index++)
          CupertinoListTile(
            leading: AppIconBadge(
              icon: CupertinoIcons.doc_fill,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
            title: Text(
              _attachments[index].filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(formatFileSize(_attachments[index].bytes.length)),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _isSending ? null : () => _removeAttachment(index),
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 22,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ),
          ),
        CupertinoListTile(
          leading: AppIconBadge(
            icon: CupertinoIcons.paperclip,
            color: CupertinoColors.systemGrey.resolveFrom(context),
          ),
          title: Text(
            _attachments.isEmpty ? 'Прикрепить файлы' : 'Добавить ещё',
            style: TextStyle(fontSize: 15, color: label),
          ),
          onTap: _isSending ? null : _pickAttachments,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _toError ?? _copyError ?? _subjectError;
    return PopScope(
      canPop: _isSending || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSending) _confirmDiscard();
      },
      child: BookingGlassScaffold(
        title: widget.replyTo != null
            ? (widget.replyAll ? 'Ответ всем' : 'Ответ')
            : widget.forwardOf != null
            ? 'Переслать'
            : 'Новое письмо',
        canPop: !_isSending,
        trailing: BookingNavAction(
          label: 'Отправить',
          isLoading: _isSending,
          onPressed: _send,
        ),
        children: [
          _buildHeaderFields(context),
          if (error != null) BookingFootnote(error, isError: true),
          _buildBody(context),
          if (_canAttach) _buildAttachments(context),
        ],
      ),
    );
  }
}
