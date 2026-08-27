import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;
import 'package:intl/intl.dart';

import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/booking_pickers.dart';
import 'compose_mail_screen.dart';
import 'mail_message_screen.dart';

class MailInboxScreen extends StatefulWidget {
  const MailInboxScreen({super.key, required this.connection});

  final MailConnection connection;

  @override
  State<MailInboxScreen> createState() => _MailInboxScreenState();
}

class _MailInboxScreenState extends State<MailInboxScreen> {
  List<MailFolder> _folders = [];
  List<MailMessage> _messages = [];
  MailFolder? _selectedFolder;
  bool _isLoadingFolders = true;
  bool _isLoadingMessages = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoadingFolders = true);
    try {
      final folders = await MailRepository.instance.getMailboxes(
        widget.connection.id,
      );
      if (!mounted) return;
      MailFolder? selected;
      for (final folder in folders) {
        if (folder.isInbox) {
          selected = folder;
          break;
        }
      }
      selected ??= folders.isNotEmpty ? folders.first : null;
      setState(() {
        _folders = folders;
        _selectedFolder = selected;
        _isLoadingFolders = false;
      });
      await _loadMessages();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingFolders = false);
      await _loadMessages(fallbackToService: true);
    }
  }

  Future<void> _loadMessages({bool fallbackToService = false}) async {
    setState(() => _isLoadingMessages = true);
    try {
      final List<MailMessage> items;
      final folder = _selectedFolder;
      if (!fallbackToService && folder != null && folder.id > 0) {
        items = await MailRepository.instance.getMessagesByFolder(
          connectionId: widget.connection.id,
          folderId: folder.id,
        );
      } else {
        items = await MailRepository.instance.getMessagesByService(
          widget.connection.id,
        );
      }
      if (!mounted) return;
      setState(() {
        _messages = items;
        _isLoadingMessages = false;
      });
    } catch (_) {
      if (!fallbackToService && _selectedFolder != null) {
        try {
          final items = await MailRepository.instance.getMessagesByService(
            widget.connection.id,
          );
          if (!mounted) return;
          setState(() {
            _messages = items;
            _isLoadingMessages = false;
          });
          return;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _isLoadingMessages = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить письма')),
      );
    }
  }

  Future<void> _openCompose({MailMessage? replyTo}) async {
    final sent = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) =>
            ComposeMailScreen(connection: widget.connection, replyTo: replyTo),
      ),
    );
    if (sent == true) await _loadMessages();
  }

  Future<void> _openMessage(MailMessage message) async {
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) => MailMessageScreen(
          connection: widget.connection,
          messageId: message.id,
          initialMessage: message,
          folders: _folders,
        ),
      ),
    );
    if (changed == true) await _loadMessages();
  }

  Future<void> _showFolderPicker() async {
    if (_folders.isEmpty) return;
    final picked = await showBookingOptionSheet<MailFolder>(
      context: context,
      title: 'Папки',
      options: _folders,
      current: _selectedFolder ?? _folders.first,
      labelOf: (folder) => folder.unreadCount != null
          ? '${folder.name} (${folder.unreadCount})'
          : folder.name,
    );
    if (picked == null) return;
    setState(() => _selectedFolder = picked);
    _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM, HH:mm', 'ru_RU');

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.connection.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        trailing: _folders.isEmpty
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _showFolderPicker,
                child: const Icon(CupertinoIcons.folder, size: 24),
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
          child: Stack(
            children: [
              (_isLoadingFolders || _isLoadingMessages) && _messages.isEmpty
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: 8,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          const AppSkeletonCardTile(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Text(
                            widget.connection.email,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadMessages,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                              children: [
                                if (!widget.connection.isActive ||
                                    (widget.connection.lastError ?? '')
                                        .isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemRed
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          CupertinoIcons
                                              .exclamationmark_triangle_fill,
                                          color: CupertinoColors.systemRed,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            widget.connection.lastError ??
                                                'Почтовое подключение неактивно',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: CupertinoColors.systemRed,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_messages.isEmpty && !_isLoadingMessages)
                                  SizedBox(
                                    height:
                                        MediaQuery.sizeOf(context).height *
                                        0.35,
                                    child: AppEmptyState(
                                      icon: CupertinoIcons.tray,
                                      message: _selectedFolder != null
                                          ? 'В папке «${_selectedFolder!.name}» нет писем'
                                          : 'Нет писем',
                                    ),
                                  )
                                else ...[
                                  for (
                                    var i = 0;
                                    i < _messages.length;
                                    i++
                                  ) ...[
                                    if (i > 0) const SizedBox(height: 8),
                                    _MessageTile(
                                      message: _messages[i],
                                      dateFormat: dateFormat,
                                      onTap: () => _openMessage(_messages[i]),
                                    ),
                                  ],
                                  if (_isLoadingMessages)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Center(
                                        child: CupertinoActivityIndicator(),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
              Positioned(
                right: 16,
                bottom: 16,
                child: GestureDetector(
                  onTap: () => _openCompose(),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      CupertinoIcons.square_pencil,
                      color: CupertinoColors.white,
                      size: 24,
                    ),
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

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.dateFormat,
    required this.onTap,
  });

  final MailMessage message;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = !message.isRead;

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUnread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, right: 8),
                  decoration: const BoxDecoration(
                    color: CupertinoColors.activeBlue,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.from.isEmpty
                                ? 'Неизвестный отправитель'
                                : message.from,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (message.date != null)
                          Text(
                            dateFormat.format(message.date!.toLocal()),
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.subject,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (message.previewBody.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        message.previewBody,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (message.hasAttachments) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.paperclip,
                            size: 14,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Вложения',
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
