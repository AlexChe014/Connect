import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/mail/mail_connection.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/booking_glass_form.dart';
import '../utils/file_size_format.dart';
import '../widgets/mail_glass.dart';
import '../widgets/staff_user_picker_sheet.dart';

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
  });

  final MailConnection connection;
  final MailMessage? replyTo;

  /// Ответить всем: в «Кому» — отправитель и все получатели исходного
  /// письма (включая копию), кроме своего адреса.
  final bool replyAll;
  final MailMessage? forwardOf;

  @override
  State<ComposeMailScreen> createState() => _ComposeMailScreenState();
}

class _ComposeMailScreenState extends State<ComposeMailScreen> {
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  static const _forwardMarker = '---------- Пересланное сообщение ----------';

  /// Текст пользователя без цитаты исходного письма: сервер сам добавляет
  /// пересылаемое письмо целиком (с HTML), иначе оно вышло бы дважды.
  String get _forwardComment {
    final text = _bodyController.text;
    final cut = text.indexOf(_forwardMarker);
    return (cut < 0 ? text : text.substring(0, cut)).trim();
  }

  final List<_PendingAttachment> _attachments = [];
  bool _isSending = false;
  String? _toError;
  String? _subjectError;

  /// Значения полей при открытии — чтобы понять, есть ли что терять
  /// при выходе без отправки.
  late final String _initialTo;
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
  /// а не себе; «всем» — отправителю, получателям и копии без себя.
  List<String> _replyRecipients(MailMessage message) {
    final from = message.from.trim();
    final to = MailMessage.splitAddresses(message.to);
    final cc = MailMessage.splitAddresses(message.cc);
    final candidates = <String>[
      if (!_isOwn(from) && from.isNotEmpty) from,
      if (widget.replyAll || _isOwn(from)) ...to,
      if (widget.replyAll) ...cc,
    ];
    final seen = <String>{};
    final result = candidates
        .where((a) => !_isOwn(a))
        .where((a) => seen.add(mailEmailOnly(a).toLowerCase()))
        .toList();
    return result.isEmpty && from.isNotEmpty ? [from] : result;
  }

  @override
  void initState() {
    super.initState();
    final replyTo = widget.replyTo;
    final forwardOf = widget.forwardOf;
    final dateFormat = DateFormat('d MMMM yyyy, HH:mm', 'ru_RU');
    if (replyTo != null) {
      _toController.text = _replyRecipients(replyTo).join(', ');
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
    _initialTo = _toController.text;
    _initialSubject = _subjectController.text;
    _initialBody = _bodyController.text;
  }

  bool get _hasUnsavedChanges =>
      _attachments.isNotEmpty ||
      _toController.text != _initialTo ||
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

  /// Вложения в ответе/пересылке сервер пока не принимает — до доработки
  /// бэкенда (replyAttachmentsSupported) кнопку прикрепления не показываем.
  bool get _canAttach =>
      (widget.replyTo == null && widget.forwardOf == null) ||
      MailRepository.replyAttachmentsSupported;

  @override
  void dispose() {
    _toController.dispose();
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
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      picked.add(_PendingAttachment(filename: file.name, bytes: bytes));
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _attachments.addAll(picked));
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  /// Адреса из поля «Кому»: можно перечислять через запятую или «;».
  List<String> get _recipients =>
      MailMessage.splitAddresses(_toController.text);

  /// Получатели одной строкой в формате списка адресов (RFC 5322) —
  /// так `to` и уходит на сервер.
  String get _toValue => _recipients.join(', ');

  /// Добавляет в «Кому» e-mail сотрудников из справочника компании. Шторка
  /// не закрывается после выбора — можно отметить сразу несколько человек.
  Future<void> _pickEmployees() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await StaffUserPickerSheet.show(
      context,
      selectedIds: const {},
      validateUser: (user) {
        final email = user.email?.trim() ?? '';
        if (email.isEmpty) {
          return 'У сотрудника ${user.fullName} не указан e-mail';
        }
        final lower = email.toLowerCase();
        if (_recipients.any((r) => r.toLowerCase() == lower)) {
          return '$email уже есть среди получателей';
        }
        return null;
      },
      onUserSelected: (user) {
        final email = user.email!.trim();
        setState(() {
          _toController.text = [..._recipients, email].join(', ');
          _toError = null;
        });
      },
    );
  }

  bool _validate() {
    final recipients = _recipients;
    final subject = _subjectController.text.trim();
    final invalid = recipients.where((r) => !_looksLikeEmail(r)).toList();
    setState(() {
      _toError = recipients.isEmpty
          ? 'Введите адрес получателя'
          : invalid.isNotEmpty
          ? 'Некорректный email: ${invalid.join(', ')}'
          : null;
      _subjectError = subject.isEmpty ? 'Введите тему письма' : null;
    });
    return _toError == null && _subjectError == null;
  }

  /// Принимает и `Имя <a@b.ru>`, и просто `a@b.ru`.
  static bool _looksLikeEmail(String value) {
    final match = RegExp(r'<([^>]+)>').firstMatch(value);
    final address = (match?.group(1) ?? value).trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address);
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
          .map(
            (a) => http.MultipartFile.fromBytes(
              'attachments[]',
              a.bytes,
              filename: a.filename,
            ),
          )
          .toList();
      // /mail/smtp/reply/{email} и /mail/smtp/forward/{email} отправляют с
      // ящика исходного письма и связывают ответ с перепиской.
      if (replyTo != null) {
        await MailRepository.instance.replyMail(
          ReplyMailRequest(
            messageId: replyTo.id,
            to: _toValue,
            subject: _subjectController.text.trim(),
            body: _bodyController.text,
            attachments: files,
          ),
        );
      } else if (forwardOf != null) {
        await MailRepository.instance.forwardMail(
          ForwardMailRequest(
            messageId: forwardOf.id,
            to: _toValue,
            subject: _subjectController.text.trim(),
            body: _forwardComment,
            attachments: files,
          ),
        );
      } else {
        await MailRepository.instance.sendMail(
          SendMailRequest(
            connectionId: widget.connection.id,
            to: _toValue,
            subject: _subjectController.text.trim(),
            body: _bodyController.text,
            attachments: files,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
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
      width: 58,
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

  /// «Кому», «От» и «Тема» — одной стеклянной карточкой с подписями
  /// слева, как в «Почте» iOS.
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
              child: Row(
                children: [
                  _fieldLabel(context, 'Кому:'),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _toController,
                      placeholder: 'email@example.com',
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_isSending,
                      decoration: const BoxDecoration(),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      style: fieldStyle,
                      onChanged: (_) {
                        if (_toError != null) setState(() => _toError = null);
                      },
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 40),
                    onPressed: _isSending ? null : _pickEmployees,
                    child: Icon(
                      CupertinoIcons.person_crop_circle_badge_plus,
                      size: 24,
                      color: label,
                    ),
                  ),
                ],
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
            leading: const AppIconBadge(
              icon: CupertinoIcons.doc_fill,
              color: CupertinoColors.systemGrey,
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
          leading: const AppIconBadge(
            icon: CupertinoIcons.paperclip,
            color: CupertinoColors.systemGrey,
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
    final error = _toError ?? _subjectError;
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
