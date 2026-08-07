import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_icons.dart';
import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
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
      final folders = await MailRepository.instance.getMailboxes(widget.connection.id);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _selectedFolder = folders.isNotEmpty ? folders.first : null;
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
      if (!fallbackToService && folder != null) {
        items = await MailRepository.instance.getMessagesByFolder(
          connectionId: widget.connection.id,
          folderId: folder.id,
        );
      } else {
        items = await MailRepository.instance.getMessagesByService(widget.connection.id);
      }
      if (!mounted) return;
      setState(() {
        _messages = items;
        _isLoadingMessages = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMessages = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить письма')),
      );
    }
  }

  Future<void> _openCompose({MailMessage? replyTo}) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => ComposeMailScreen(
          connection: widget.connection,
          replyTo: replyTo,
        ),
      ),
    );
    if (sent == true) await _loadMessages();
  }

  Future<void> _openMessage(MailMessage message) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
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

  void _showFolderPicker() {
    if (_folders.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Папки',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ..._folders.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                subtitle: folder.unreadCount != null
                    ? Text('Непрочитанных: ${folder.unreadCount}')
                    : null,
                selected: _selectedFolder?.id == folder.id,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedFolder = folder);
                  _loadMessages();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('d MMM, HH:mm', 'ru_RU');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.connection.displayName),
        centerTitle: true,
        actions: [
          if (_folders.isNotEmpty)
            IconButton(
              tooltip: 'Папки',
              onPressed: _showFolderPicker,
              icon: const Icon(Icons.folder_outlined),
            ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _isLoadingMessages ? null : _loadMessages,
            icon: const AppIcon(AppIcons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCompose(),
        child: const AppIcon(AppIcons.compose),
      ),
      body: _isLoadingFolders && _isLoadingMessages
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    widget.connection.email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
                            (widget.connection.lastError ?? '').isNotEmpty)
                          Card(
                            color: theme.colorScheme.errorContainer,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      widget.connection.lastError ??
                                          'Почтовое подключение неактивно',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_messages.isEmpty && !_isLoadingMessages)
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.35,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 48,
                                    color: theme.colorScheme.outline,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _selectedFolder != null
                                        ? 'В папке «${_selectedFolder!.name}» нет писем'
                                        : 'Нет писем',
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          for (var i = 0; i < _messages.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _MessageTile(
                              message: _messages[i],
                              dateFormat: dateFormat,
                              onTap: () => _openMessage(_messages[i]),
                            ),
                          ],
                          if (_isLoadingMessages)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
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
    final theme = Theme.of(context);
    final isUnread = !message.isRead;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
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
                            message.from.isEmpty ? 'Неизвестный отправитель' : message.from,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (message.date != null)
                          Text(
                            dateFormat.format(message.date!.toLocal()),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.subject,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (message.previewBody.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        message.previewBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (message.hasAttachments) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          AppIcon(
                            AppIcons.attachment,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Вложения',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
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
