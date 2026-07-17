import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_icons.dart';
import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../widgets/mail_body_content.dart';
import 'compose_mail_screen.dart';

class MailMessageScreen extends StatefulWidget {
  const MailMessageScreen({
    super.key,
    required this.connection,
    required this.messageId,
    this.initialMessage,
    this.folders = const [],
  });

  final MailConnection connection;
  final int messageId;
  final MailMessage? initialMessage;
  final List<MailFolder> folders;

  @override
  State<MailMessageScreen> createState() => _MailMessageScreenState();
}

class _MailMessageScreenState extends State<MailMessageScreen> {
  MailMessage? _message;
  bool _isLoading = true;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadMessage();
  }

  Future<void> _loadMessage() async {
    setState(() => _isLoading = true);
    try {
      final message = await MailRepository.instance.getMessage(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
      );
      final initial = widget.initialMessage;
      final resolved = !message.hasBody && initial != null && initial.hasBody
          ? MailMessage(
              id: message.id,
              subject: message.subject != '(без темы)' ? message.subject : initial.subject,
              from: message.from.isNotEmpty ? message.from : initial.from,
              to: message.to ?? initial.to,
              body: initial.body,
              bodyHtml: initial.bodyHtml,
              date: message.date ?? initial.date,
              isRead: message.isRead,
              hasAttachments: message.hasAttachments || initial.hasAttachments,
              attachments: message.attachments.isNotEmpty
                  ? message.attachments
                  : initial.attachments,
            )
          : message;
      if (!mounted) return;
      setState(() {
        _message = resolved;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      final fallback = widget.initialMessage;
      setState(() {
        _message = fallback;
        _isLoading = false;
      });
      if (fallback == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить письмо')),
        );
      } else if (fallback.htmlContent == null && fallback.plainBody.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить текст письма')),
        );
      }
    }
  }

  Future<void> _deleteMessage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить письмо?'),
        content: const Text('Письмо будет удалено без возможности восстановления.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await MailRepository.instance.deleteMessage(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить письмо')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _moveToFolder() async {
    if (widget.folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Список папок пуст')),
      );
      return;
    }

    final folder = await showModalBottomSheet<MailFolder>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Переместить в папку',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ...widget.folders.map(
              (f) => ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(f.name),
                onTap: () => Navigator.pop(context, f),
              ),
            ),
          ],
        ),
      ),
    );
    if (folder == null || !mounted) return;

    try {
      await MailRepository.instance.moveMessage(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
        folderId: folder.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Письмо перемещено в «${folder.name}»')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось переместить письмо')),
      );
    }
  }

  Future<void> _downloadAttachment(MailAttachment attachment) async {
    try {
      final bytes = await MailRepository.instance.downloadAttachment(
        connectionId: widget.connection.id,
        attachmentId: attachment.id,
        filename: attachment.filename,
      );
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/${attachment.filename}');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранено: ${file.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось скачать вложение')),
      );
    }
  }

  Future<void> _reply() async {
    final message = _message;
    if (message == null) return;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => ComposeMailScreen(
          connection: widget.connection,
          replyTo: message,
        ),
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _message;
    final dateFormat = DateFormat('d MMMM yyyy, HH:mm', 'ru_RU');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Письмо'),
        centerTitle: true,
        actions: [
          if (message != null)
            IconButton(
              tooltip: 'Ответить',
              onPressed: _reply,
              icon: const AppIcon(AppIcons.reply),
            ),
          if (widget.folders.isNotEmpty)
            IconButton(
              tooltip: 'Переместить',
              onPressed: _moveToFolder,
              icon: const Icon(Icons.drive_file_move_outline),
            ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: _isDeleting ? null : _deleteMessage,
            icon: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : message == null
              ? const Center(child: Text('Письмо не найдено'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      message.subject,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MetaRow(label: 'От', value: message.from),
                    if ((message.to ?? '').isNotEmpty)
                      _MetaRow(label: 'Кому', value: message.to!),
                    if (message.date != null)
                      _MetaRow(
                        label: 'Дата',
                        value: dateFormat.format(message.date!.toLocal()),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: MailBodyContent(message: message),
                      ),
                    ),
                    if (message.attachments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Вложения',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...message.attachments.map(
                        (attachment) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const AppIcon(AppIcons.attachment),
                            title: Text(attachment.filename),
                            subtitle: attachment.size != null
                                ? Text('${attachment.size} байт')
                                : null,
                            trailing: const AppIcon(AppIcons.download),
                            onTap: () => _downloadAttachment(attachment),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
