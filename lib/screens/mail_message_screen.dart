import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar;
import 'package:intl/intl.dart';

import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/booking_pickers.dart';
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
              subject: message.subject != '(без темы)'
                  ? message.subject
                  : initial.subject,
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить письмо')),
        );
      } else if (fallback.htmlContent == null && fallback.plainBody.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить текст письма')),
        );
      }
    }
  }

  Future<void> _deleteMessage() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить письмо?'),
        content: const Text(
          'Письмо будет удалено без возможности восстановления.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить письмо')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _moveToFolder() async {
    if (widget.folders.isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Список папок пуст')));
      return;
    }

    final folder = await showBookingOptionSheet<MailFolder>(
      context: context,
      title: 'Переместить в папку',
      options: widget.folders,
      current: widget.folders.first,
      labelOf: (f) => f.name,
    );
    if (folder == null || !mounted) return;

    try {
      await MailRepository.instance.moveMessage(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
        folderId: folder.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Письмо перемещено в «${folder.name}»')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Сохранено: ${file.path}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось скачать вложение')),
      );
    }
  }

  Future<void> _reply() async {
    final message = _message;
    if (message == null) return;
    final sent = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) =>
            ComposeMailScreen(connection: widget.connection, replyTo: message),
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 16, color: CupertinoColors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final dateFormat = DateFormat('d MMMM yyyy, HH:mm', 'ru_RU');

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Письмо'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        trailing: message == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: _reply,
                    child: const Icon(CupertinoIcons.reply, size: 22),
                  ),
                  if (widget.folders.isNotEmpty)
                    CupertinoButton(
                      padding: const EdgeInsets.only(left: 16),
                      minimumSize: Size.zero,
                      onPressed: _moveToFolder,
                      child: const Icon(CupertinoIcons.folder, size: 22),
                    ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 16),
                    minimumSize: Size.zero,
                    onPressed: _isDeleting ? null : _deleteMessage,
                    child: _isDeleting
                        ? const CupertinoActivityIndicator()
                        : const Icon(
                            CupertinoIcons.delete,
                            size: 22,
                            color: CupertinoColors.systemRed,
                          ),
                  ),
                ],
              ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 15,
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CupertinoActivityIndicator(radius: 14))
              : message == null
              ? const AppEmptyState(message: 'Письмо не найдено')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.secondarySystemGroupedBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        message.subject,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    CupertinoListSection.insetGrouped(
                      margin: EdgeInsets.zero,
                      children: [
                        CupertinoListTile(
                          title: const Text(
                            'От',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel,
                            ),
                          ),
                          additionalInfo: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              message.from,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if ((message.to ?? '').isNotEmpty)
                          CupertinoListTile(
                            title: const Text(
                              'Кому',
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoColors.secondaryLabel,
                              ),
                            ),
                            additionalInfo: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                message.to!,
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        if (message.date != null)
                          CupertinoListTile(
                            title: const Text(
                              'Дата',
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoColors.secondaryLabel,
                              ),
                            ),
                            additionalInfo: Text(
                              dateFormat.format(message.date!.toLocal()),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.secondarySystemGroupedBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: MailBodyContent(message: message),
                    ),
                    if (message.attachments.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'ВЛОЖЕНИЯ',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CupertinoListSection.insetGrouped(
                        margin: EdgeInsets.zero,
                        children: [
                          for (final attachment in message.attachments)
                            CupertinoListTile(
                              leading: _iconBadge(
                                CupertinoIcons.paperclip,
                                CupertinoColors.systemGrey,
                              ),
                              title: Text(
                                attachment.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: attachment.size != null
                                  ? Text('${attachment.size} байт')
                                  : null,
                              trailing: const Icon(
                                CupertinoIcons.cloud_download,
                                color: CupertinoColors.activeBlue,
                              ),
                              onTap: () => _downloadAttachment(attachment),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
