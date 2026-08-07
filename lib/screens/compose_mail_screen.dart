import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_icons.dart';
import '../models/mail/mail_connection.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';

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
  });

  final MailConnection connection;
  final MailMessage? replyTo;

  @override
  State<ComposeMailScreen> createState() => _ComposeMailScreenState();
}

class _ComposeMailScreenState extends State<ComposeMailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final List<_PendingAttachment> _attachments = [];
  bool _isSending = false;

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
      picked.add(
        _PendingAttachment(
          filename: file.name,
          bytes: bytes,
        ),
      );
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _attachments.addAll(picked));
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

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
          connectionId: widget.connection.id,
          to: _toController.text.trim(),
          subject: _subjectController.text.trim(),
          body: _bodyController.text,
          attachments: files,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить письмо')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новое письмо'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSending ? null : _send,
            child: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Отправить'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'От: ${widget.connection.email}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _toController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Кому',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Введите адрес получателя';
                if (!v.contains('@')) return 'Некорректный email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _subjectController,
              decoration: const InputDecoration(
                labelText: 'Тема',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Введите тему письма' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyController,
              minLines: 8,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Сообщение',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isSending ? null : _pickAttachments,
              icon: const AppIcon(AppIcons.attachment),
              label: const Text('Прикрепить файлы'),
            ),
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...List.generate(_attachments.length, (index) {
                final attachment = _attachments[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(attachment.filename),
                    trailing: IconButton(
                      icon: const AppIcon(AppIcons.close),
                      onPressed: _isSending ? null : () => _removeAttachment(index),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
