import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, Scaffold, ScaffoldMessenger, SnackBar;
import 'package:http/http.dart' as http;

import '../models/mail/mail_connection.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../services/api_client.dart';

class _PendingAttachment {
  final String filename;
  final List<int> bytes;

  const _PendingAttachment({required this.filename, required this.bytes});
}

class ComposeMailScreen extends StatefulWidget {
  const ComposeMailScreen({super.key, required this.connection, this.replyTo});

  final MailConnection connection;
  final MailMessage? replyTo;

  @override
  State<ComposeMailScreen> createState() => _ComposeMailScreenState();
}

class _ComposeMailScreenState extends State<ComposeMailScreen> {
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final List<_PendingAttachment> _attachments = [];
  bool _isSending = false;
  String? _toError;
  String? _subjectError;

  @override
  void initState() {
    super.initState();
    final replyTo = widget.replyTo;
    if (replyTo != null) {
      _toController.text = replyTo.from;
      _subjectController.text = replyTo.subject.startsWith('Re:')
          ? replyTo.subject
          : 'Re: ${replyTo.subject}';
      final quote = replyTo.previewBody;
      if (quote.isNotEmpty) {
        _bodyController.text = '\n\n---\n$quote';
      }
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
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

  bool _validate() {
    final to = _toController.text.trim();
    final subject = _subjectController.text.trim();
    setState(() {
      _toError = to.isEmpty
          ? 'Введите адрес получателя'
          : (!to.contains('@') ? 'Некорректный email' : null);
      _subjectError = subject.isEmpty ? 'Введите тему письма' : null;
    });
    return _toError == null && _subjectError == null;
  }

  Future<void> _send() async {
    if (!_validate()) return;

    setState(() => _isSending = true);
    try {
      final files = _attachments
          .map(
            (a) => http.MultipartFile.fromBytes(
              'attachments[]',
              a.bytes,
              filename: a.filename,
            ),
          )
          .toList();

      await MailRepository.instance.sendMail(
        SendMailRequest(
          to: _toController.text.trim(),
          subject: _subjectController.text.trim(),
          body: _bodyController.text,
          attachments: files,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    // Wrapped in a Material Scaffold purely so ScaffoldMessenger has a local
    // Scaffold to attach SnackBars to — this screen is pushed on top of the
    // app's only Scaffold (MainNavigationScreen's), which sits hidden behind
    // it, so error/success SnackBars would otherwise render invisibly there.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Новое письмо'),
          backgroundColor: CupertinoColors.systemGroupedBackground,
          border: null,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: _isSending ? null : () => Navigator.pop(context),
            child: const Icon(CupertinoIcons.back, size: 26),
          ),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: _isSending ? null : _send,
            child: _isSending
                ? const CupertinoActivityIndicator()
                : const Text(
                    'Отправить',
                    style: TextStyle(fontWeight: FontWeight.w600),
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
                Text(
                  'От: ${widget.connection.email}',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoFormSection.insetGrouped(
                  margin: EdgeInsets.zero,
                  children: [
                    CupertinoTextFormFieldRow(
                      controller: _toController,
                      prefix: const Text('Кому'),
                      placeholder: 'email@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textAlign: TextAlign.end,
                      enabled: !_isSending,
                      onChanged: (_) {
                        if (_toError != null) setState(() => _toError = null);
                      },
                    ),
                    CupertinoTextFormFieldRow(
                      controller: _subjectController,
                      prefix: const Text('Тема'),
                      textAlign: TextAlign.end,
                      enabled: !_isSending,
                      onChanged: (_) {
                        if (_subjectError != null) {
                          setState(() => _subjectError = null);
                        }
                      },
                    ),
                  ],
                ),
                if (_toError != null || _subjectError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      _toError ?? _subjectError!,
                      style: const TextStyle(
                        color: CupertinoColors.systemRed,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemGroupedBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: CupertinoTextField(
                    controller: _bodyController,
                    minLines: 8,
                    maxLines: null,
                    enabled: !_isSending,
                    placeholder: 'Текст письма',
                    decoration: const BoxDecoration(),
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 20),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _isSending ? null : _pickAttachments,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(CupertinoIcons.paperclip, size: 18),
                      SizedBox(width: 6),
                      Text('Прикрепить файлы'),
                    ],
                  ),
                ),
                if (_attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  CupertinoListSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    children: List.generate(_attachments.length, (index) {
                      final attachment = _attachments[index];
                      return CupertinoListTile(
                        leading: const Icon(CupertinoIcons.doc),
                        title: Text(
                          attachment.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: _isSending
                              ? null
                              : () => _removeAttachment(index),
                          child: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            size: 20,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
