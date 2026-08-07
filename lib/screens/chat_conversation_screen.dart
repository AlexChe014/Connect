import 'dart:io';

import 'package:connect/config/app_icons.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/screens/chat_settings_screen.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:connect/widgets/chat_message_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

String _formatMsgTime(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

bool _sameChatAuthor(ChatMessage a, ChatMessage b) {
  if (a.isSystem || b.isSystem) return false;
  if (a.isOutgoing && b.isOutgoing) return true;
  if (!a.isOutgoing && !b.isOutgoing && a.authorName == b.authorName) return true;
  return false;
}

bool _showMessageTime(ChatMessage m, ChatMessage? next) {
  if (next == null || !_sameChatAuthor(m, next)) return true;
  return next.createdAt.difference(m.createdAt).inMinutes >= 2;
}

ChatAttachmentKind _kindFromPath(String? path) {
  if (path == null) return ChatAttachmentKind.file;
  final lower = path.toLowerCase();
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|heic|bmp)$').hasMatch(lower)) {
    return ChatAttachmentKind.image;
  }
  if (RegExp(r'\.(mp4|mov|webm|mkv|avi)$').hasMatch(lower)) {
    return ChatAttachmentKind.video;
  }
  return ChatAttachmentKind.file;
}

class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({super.key, required this.chat});

  final Chat chat;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _textCtrl = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  final _service = ChatService.instance;

  MessageReference? _replyingTo;

  final _scrollTargetKey = GlobalKey();
  int? _scrollToReversedIndex;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onMsg);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _service.loadMessages(widget.chat.id, force: true);
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onMsg);
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onMsg() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _scheduleInitialScroll();
    });
  }

  void _scheduleInitialScroll() {
    if (_didInitialScroll) return;

    final list = _service.messagesFor(widget.chat.id);
    if (list.isEmpty || _service.isMessagesLoading(widget.chat.id)) return;

    final unreadIdx = list.indexWhere((m) => !m.isOutgoing && !m.isRead);
    if (unreadIdx < 0 || unreadIdx >= list.length - 1) {
      // reverse: true — по умолчанию открывается снизу (последнее сообщение).
      _didInitialScroll = true;
      return;
    }

    _scrollToReversedIndex = list.length - 1 - unreadIdx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _performInitialScroll());
    });
  }

  void _performInitialScroll() {
    if (_didInitialScroll || !mounted) return;

    final ctx = _scrollTargetKey.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _performInitialScroll());
      return;
    }

    _didInitialScroll = true;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
  }

  Chat get _c => _service.chatById(widget.chat.id) ?? widget.chat;

  @override
  Widget build(BuildContext context) {
    final list = _service.messagesFor(widget.chat.id);
    final loading = _service.isMessagesLoading(widget.chat.id);
    final loadError = _service.messagesError(widget.chat.id);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF4), // Telegram-like light chat background
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => ChatSettingsScreen(chat: _c),
                  ),
                );
              },
              child: ChatAvatar(chat: _c, radius: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  if (_c.isGroup && _c.memberNames.isNotEmpty)
                    Text(
                      '${_c.memberNames.length} участников',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: loading && list.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : loadError != null && list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(loadError, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => _service.loadMessages(
                                  widget.chat.id,
                                  force: true,
                                ),
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : list.isEmpty
                        ? const Center(
                            child: Text('Пока нет сообщений — напишите первым'),
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final chronologicalIndex = list.length - 1 - i;
                              final m = list[chronologicalIndex];
                              final previous = chronologicalIndex > 0
                                  ? list[chronologicalIndex - 1]
                                  : null;
                              final next = chronologicalIndex < list.length - 1
                                  ? list[chronologicalIndex + 1]
                                  : null;
                              final showAuthorHeader = !m.isOutgoing &&
                                  !m.isSystem &&
                                  (previous == null || !_sameChatAuthor(previous, m));
                              final tile = _MessageTile(
                                m: m,
                                showAuthorHeader: showAuthorHeader,
                                showAvatarInHeader: _c.isGroup && showAuthorHeader,
                                showTime: _showMessageTime(m, next),
                                onLongMenu: (action) {
                                  if (action == _MsgAction.reply) {
                                    setState(() {
                                      _replyingTo = _refFromMessage(m);
                                      _focus.requestFocus();
                                    });
                                  } else if (action == _MsgAction.forward) {
                                    _openForwardTarget(m);
                                  } else if (action == _MsgAction.edit) {
                                    _editMessage(m);
                                  } else if (action == _MsgAction.delete) {
                                    _deleteMessage(m);
                                  }
                                },
                              );
                              if (i == _scrollToReversedIndex) {
                                return KeyedSubtree(
                                  key: _scrollTargetKey,
                                  child: tile,
                                );
                              }
                              return tile;
                            },
                          ),
          ),
          if (_replyingTo != null) _ReplyBanner(ref: _replyingTo!, onClose: () => setState(() => _replyingTo = null)),
          _Composer(
            textCtrl: _textCtrl,
            focus: _focus,
            onSend: _send,
            onAttach: _openAttachMenu,
            accent: scheme.primary,
          ),
        ],
      ),
    );
  }

  MessageReference _refFromMessage(ChatMessage m) {
    return MessageReference(
      messageId: m.id,
      authorName: m.authorName,
      textPreview: _previewSnippet(m),
    );
  }

  String _previewSnippet(ChatMessage m) {
    if (m.text != null && m.text!.trim().isNotEmpty) {
      return HtmlTextUtils.toPlainText(m.text!);
    }
    switch (m.attachmentKind) {
      case ChatAttachmentKind.image:
        return '📷 Фото';
      case ChatAttachmentKind.video:
        return '🎬 Видео';
      case ChatAttachmentKind.file:
        return '📎 ${m.fileName ?? 'Файл'}';
      case ChatAttachmentKind.none:
        return 'Сообщение';
    }
  }

  Future<void> _send() async {
    final t = _textCtrl.text;
    if (t.trim().isEmpty) return;
    try {
      await _service.sendText(
        widget.chat.id,
        t,
        replyTo: _replyingTo,
      );
      _textCtrl.clear();
      if (mounted) setState(() => _replyingTo = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить: $e')),
      );
    }
  }

  Future<void> _openForwardTarget(ChatMessage m) async {
    final other = _service.chats.where((c) => c.id != widget.chat.id).toList();
    if (other.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет других чатов для пересылки')),
        );
      }
      return;
    }
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Переслать в…', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: other
                      .map(
                        (c) => ListTile(
                          leading: const AppIcon(AppIcons.chat),
                          title: Text(c.title),
                          onTap: () => Navigator.pop(context, c.id),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (id == null) return;
    _service.forwardMessage(
      id,
      m,
      sourceChatId: widget.chat.id,
    );
  }

  Future<void> _openAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Галерея (фото)'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const AppIcon(AppIcons.videoMeeting),
                title: const Text('Видео'),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              ListTile(
                leading: const AppIcon(AppIcons.cameraOn),
                title: const Text('Камера'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const AppIcon(AppIcons.attachment),
                title: const Text('Файл'),
                onTap: () => Navigator.pop(context, 'file'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null) return;

    String? path;
    String? name;

    if (choice == 'gallery') {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88,
      );
      path = x?.path;
    } else if (choice == 'video') {
      final x = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      path = x?.path;
    } else if (choice == 'camera') {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 88,
      );
      path = x?.path;
    } else if (choice == 'file') {
      final r = await FilePicker.platform.pickFiles();
      if (r != null && r.files.isNotEmpty) {
        final f = r.files.single;
        path = f.path;
        name = f.name;
      }
    }

    if (path == null || path.isEmpty) return;
    final kind = _kindFromPath(path);
    _service.sendMedia(
      widget.chat.id,
      path: path,
      kind: kind,
      fileName: name,
      replyTo: _replyingTo,
    );
    if (_replyingTo != null) setState(() => _replyingTo = null);
  }

  Future<void> _editMessage(ChatMessage m) async {
    final ctrl = TextEditingController(text: m.text ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Редактировать сообщение',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final success = await _service.updateMessage(
      widget.chat.id,
      m.id,
      ctrl.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Сообщение обновлено' : 'Не удалось обновить сообщение',
        ),
      ),
    );
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Сообщение будет удалено безвозвратно.'),
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
    if (ok != true || !mounted) return;

    final success = await _service.deleteMessage(widget.chat.id, m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Сообщение удалено'
              : (_service.lastActionError ?? 'Не удалось удалить сообщение'),
        ),
      ),
    );
  }
}

enum _MsgAction { reply, forward, edit, delete }

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.ref, required this.onClose});

  final MessageReference ref;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outline)),
        ),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ref.authorName,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    ref.textPreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const AppIcon(AppIcons.close),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.textCtrl,
    required this.focus,
    required this.onSend,
    required this.onAttach,
    required this.accent,
  });

  final TextEditingController textCtrl;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: onAttach,
                icon: AppIcon(
                  AppIcons.profileAdd,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
                tooltip: 'Вложения',
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.18),
                    ),
                  ),
                  child: TextField(
                    controller: textCtrl,
                    focusNode: focus,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onSend,
                    child: const AppIcon(AppIcons.send, size: 20, color: Colors.white),
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
    required this.m,
    required this.onLongMenu,
    this.showAuthorHeader = false,
    this.showAvatarInHeader = false,
    this.showTime = true,
  });

  final ChatMessage m;
  final void Function(_MsgAction) onLongMenu;
  final bool showAuthorHeader;
  final bool showAvatarInHeader;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    if (m.isSystem) {
      final systemColor = Theme.of(context).colorScheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: Center(
          child: ChatMessageText(
            text: m.text ?? '',
            color: systemColor,
            fontSize: 12,
          ),
        ),
      );
    }

    final align = m.isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final scheme = Theme.of(context).colorScheme;
    final bubble = m.isOutgoing ? const Color(0xFF1677FF) : Colors.white;
    final onBubble = m.isOutgoing ? Colors.white : const Color(0xFF111111);

    return Align(
      alignment: m.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Column(
          crossAxisAlignment: align,
          children: [
            if (showAuthorHeader && !m.isOutgoing)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showAvatarInHeader) ...[
                      MemberAvatar(
                        displayName: m.authorName,
                        avatarUrl: m.authorAvatarUrl,
                        radius: 12,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      m.authorName,
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            GestureDetector(
              onLongPress: () {
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            leading: const AppIcon(AppIcons.reply, size: 22),
                            title: const Text('Ответить', style: TextStyle(fontSize: 15)),
                            onTap: () {
                              Navigator.pop(context);
                              onLongMenu(_MsgAction.reply);
                            },
                          ),
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            leading: const AppIcon(AppIcons.share, size: 22),
                            title: const Text('Переслать', style: TextStyle(fontSize: 15)),
                            onTap: () {
                              Navigator.pop(context);
                              onLongMenu(_MsgAction.forward);
                            },
                          ),
                          if (m.isOutgoing &&
                              m.attachmentKind == ChatAttachmentKind.none &&
                              (m.text?.trim().isNotEmpty ?? false)) ...[
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              leading: const Icon(Icons.edit_outlined, size: 22),
                              title: const Text('Редактировать', style: TextStyle(fontSize: 15)),
                              onTap: () {
                                Navigator.pop(context);
                                onLongMenu(_MsgAction.edit);
                              },
                            ),
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              leading: Icon(
                                Icons.delete_outline,
                                size: 22,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(
                                'Удалить',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                onLongMenu(_MsgAction.delete);
                              },
                            ),
                          ],
                          const SizedBox(height: 4),
                        ],
                      ),
                    );
                  },
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: bubble,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(m.isOutgoing ? 18 : 6),
                    bottomRight: Radius.circular(m.isOutgoing ? 6 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: onBubble),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.forwardOf != null) _ForwardBlock(ref: m.forwardOf!, onBubble: onBubble),
                      if (m.replyTo != null)
                        _ReplyBlock(ref: m.replyTo!, isOutgoing: m.isOutgoing),
                      if (m.attachmentKind == ChatAttachmentKind.image &&
                          m.localMediaPath != null &&
                          !kIsWeb)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(m.localMediaPath!),
                            width: 220,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image),
                          ),
                        )
                      else if (m.attachmentKind == ChatAttachmentKind.image &&
                          m.remoteMediaUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            m.remoteMediaUrl!,
                            width: 220,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image),
                          ),
                        )
                      else if (m.attachmentKind == ChatAttachmentKind.image && kIsWeb)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('(изображение)'),
                        ),
                      if (m.attachmentKind == ChatAttachmentKind.video)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_circle_outline, size: 28),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                m.fileName ?? 'Видео',
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      if (m.attachmentKind == ChatAttachmentKind.file)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file, size: 24),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                m.fileName ?? 'Файл',
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      if (m.text != null && m.text!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: ChatMessageText(
                            text: m.text!,
                            color: onBubble,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (showTime) ...[
              const SizedBox(height: 2),
              Text(
                _formatMsgTime(m.createdAt),
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _ForwardBlock extends StatelessWidget {
  const _ForwardBlock({required this.ref, required this.onBubble});

  final MessageReference ref;
  final Color onBubble;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: onBubble.withValues(alpha: 0.12),
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.tertiary,
              width: 3,
            ),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref.sourceChatTitle != null
                  ? 'Переслано из «${ref.sourceChatTitle!}»'
                  : 'Переслано от ${ref.authorName}',
              style: TextStyle(
                fontSize: 11,
                color: onBubble.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              ref.textPreview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyBlock extends StatelessWidget {
  const _ReplyBlock({required this.ref, this.isOutgoing = false});

  final MessageReference ref;
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final accent = isOutgoing ? Colors.white : s.primary;
    final fill = isOutgoing
        ? Colors.white.withValues(alpha: 0.22)
        : s.primary.withValues(alpha: 0.12);
    final textColor = isOutgoing ? Colors.white : const Color(0xFF111111);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: fill,
          border: Border(
            left: BorderSide(color: accent, width: 3),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref.authorName,
              style: TextStyle(
                fontSize: 12,
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              ref.textPreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: textColor.withValues(alpha: isOutgoing ? 0.95 : 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
