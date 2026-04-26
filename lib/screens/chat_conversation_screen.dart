import 'dart:io';

import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/chat_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

String _formatMsgTime(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
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

  @override
  void initState() {
    super.initState();
    _service.addListener(_onMsg);
  }

  @override
  void dispose() {
    _service.removeListener(_onMsg);
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onMsg() {
    if (mounted) setState(() {});
  }

  Chat get _c => _service.chatById(widget.chat.id) ?? widget.chat;

  @override
  Widget build(BuildContext context) {
    final list = _service.messagesFor(widget.chat.id);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _c.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (_c.isGroup && _c.memberNames.isNotEmpty)
              Text(
                '${_c.memberNames.length} участников',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('Пока нет сообщений — напишите первым'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      return _MessageTile(
                        m: list[i],
                        onLongMenu: (action) {
                          if (action == _MsgAction.reply) {
                            setState(() {
                              _replyingTo = _refFromMessage(list[i]);
                              _focus.requestFocus();
                            });
                          } else if (action == _MsgAction.forward) {
                            _openForwardTarget(list[i]);
                          }
                        },
                      );
                    },
                  ),
          ),
          if (_replyingTo != null) _ReplyBanner(ref: _replyingTo!, onClose: () => setState(() => _replyingTo = null)),
          _Composer(
            textCtrl: _textCtrl,
            focus: _focus,
            onSend: _send,
            onAttach: _openAttachMenu,
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
    if (m.text != null && m.text!.trim().isNotEmpty) return m.text!.trim();
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

  void _send() {
    final t = _textCtrl.text;
    if (t.trim().isEmpty) return;
    _service.sendText(
      widget.chat.id,
      t,
      replyTo: _replyingTo,
    );
    _textCtrl.clear();
    setState(() => _replyingTo = null);
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
                          leading: const Icon(Icons.chat_bubble_outline),
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
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Видео'),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Камера'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
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
}

enum _MsgAction { reply, forward }

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.ref, required this.onClose});

  final MessageReference ref;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
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
              icon: const Icon(Icons.close),
            ),
          ],
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
  });

  final TextEditingController textCtrl;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: onAttach,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Вложения',
              ),
              Expanded(
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
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              FilledButton(
                onPressed: onSend,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                child: const Icon(Icons.send, size: 20),
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
  });

  final ChatMessage m;
  final void Function(_MsgAction) onLongMenu;

  @override
  Widget build(BuildContext context) {
    final align = m.isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final scheme = Theme.of(context).colorScheme;
    final bubble = m.isOutgoing ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final onBubble = m.isOutgoing ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: m.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Column(
          crossAxisAlignment: align,
          children: [
            if (!m.isOutgoing)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  m.authorName,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
                            leading: const Icon(Icons.reply),
                            title: const Text('Ответить'),
                            onTap: () {
                              Navigator.pop(context);
                              onLongMenu(_MsgAction.reply);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.forward),
                            title: const Text('Переслать'),
                            onTap: () {
                              Navigator.pop(context);
                              onLongMenu(_MsgAction.forward);
                            },
                          ),
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
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(m.isOutgoing ? 12 : 4),
                    bottomRight: Radius.circular(m.isOutgoing ? 4 : 12),
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: onBubble),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.forwardOf != null) _ForwardBlock(ref: m.forwardOf!, onBubble: onBubble),
                      if (m.replyTo != null) _ReplyBlock(ref: m.replyTo!),
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
                      else if (m.attachmentKind == ChatAttachmentKind.image && kIsWeb)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('(изображение)'),
                        ),
                      if (m.attachmentKind == ChatAttachmentKind.video)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_circle_outline, size: 32),
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
                            const Icon(Icons.insert_drive_file, size: 28),
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
                          child: Text(m.text!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatMsgTime(m.createdAt),
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
            const SizedBox(height: 8),
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
  const _ReplyBlock({required this.ref});

  final MessageReference ref;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: s.primary.withValues(alpha: 0.1),
          border: Border(
            left: BorderSide(color: s.primary, width: 3),
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
                color: s.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              ref.textPreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
