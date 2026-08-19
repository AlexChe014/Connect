import 'dart:io';

import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/screens/chat_settings_screen.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/widgets/app_empty_state.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:connect/widgets/chat_message_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar, showModalBottomSheet;
import 'package:image_picker/image_picker.dart';

String _formatMsgTime(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

bool _sameChatAuthor(ChatMessage a, ChatMessage b) {
  if (a.isSystem || b.isSystem) return false;
  if (a.isOutgoing && b.isOutgoing) return true;
  if (!a.isOutgoing && !b.isOutgoing && a.authorName == b.authorName) {
    return true;
  }
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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _performInitialScroll(),
      );
    });
  }

  void _performInitialScroll() {
    if (_didInitialScroll || !mounted) return;

    final ctx = _scrollTargetKey.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _performInitialScroll(),
      );
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

  void _openSettings() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => ChatSettingsScreen(chat: _c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _service.messagesFor(widget.chat.id);
    final loading = _service.isMessagesLoading(widget.chat.id);
    final loadError = _service.messagesError(widget.chat.id);
    final c = _c;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground.withValues(
          alpha: 0.94,
        ),
        border: null,
        middle: GestureDetector(
          onTap: _openSettings,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatAvatar(chat: c, radius: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                    ),
                    if (c.isGroup && c.memberNames.isNotEmpty)
                      Text(
                        '${c.memberNames.length} участников',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
          child: Column(
            children: [
              Expanded(
                child: loading && list.isEmpty
                    ? const Center(child: CupertinoActivityIndicator(radius: 14))
                    : loadError != null && list.isEmpty
                    ? AppEmptyState(
                        icon: CupertinoIcons.exclamationmark_triangle,
                        message: loadError,
                        onRetry: () =>
                            _service.loadMessages(widget.chat.id, force: true),
                      )
                    : list.isEmpty
                    ? const AppEmptyState(
                        icon: CupertinoIcons.chat_bubble_2,
                        message: 'Пока нет сообщений — напишите первым',
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
                          final showAuthorHeader =
                              !m.isOutgoing &&
                              !m.isSystem &&
                              (previous == null ||
                                  !_sameChatAuthor(previous, m));
                          final tile = _MessageTile(
                            m: m,
                            showAuthorHeader: showAuthorHeader,
                            showAvatarInHeader: c.isGroup && showAuthorHeader,
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
              if (_replyingTo != null)
                _ReplyBanner(
                  ref: _replyingTo!,
                  onClose: () => setState(() => _replyingTo = null),
                ),
              _Composer(
                textCtrl: _textCtrl,
                focus: _focus,
                onSend: _send,
                onAttach: _openAttachMenu,
              ),
            ],
          ),
        ),
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

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final t = _textCtrl.text;
    if (t.trim().isEmpty) return;
    try {
      await _service.sendText(widget.chat.id, t, replyTo: _replyingTo);
      _textCtrl.clear();
      if (mounted) setState(() => _replyingTo = null);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Не удалось отправить: $e');
    }
  }

  Future<void> _openForwardTarget(ChatMessage m) async {
    final other = _service.chats.where((c) => c.id != widget.chat.id).toList();
    if (other.isEmpty) {
      _showSnack('Нет других чатов для пересылки');
      return;
    }
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Переслать в…',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: other.length,
                    itemBuilder: (context, i) {
                      final chat = other[i];
                      return _ForwardTargetTile(
                        chat: chat,
                        onTap: () => Navigator.pop(context, chat.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (id == null) return;
    _service.forwardMessage(id, m, sourceChatId: widget.chat.id);
  }

  Future<void> _openAttachMenu() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'gallery'),
            child: const Text('Галерея (фото)'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'video'),
            child: const Text('Видео'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Text('Камера'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'file'),
            child: const Text('Файл'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
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
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Редактировать сообщение'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            maxLines: 4,
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
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
    _showSnack(
      success ? 'Сообщение обновлено' : 'Не удалось обновить сообщение',
    );
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Сообщение будет удалено безвозвратно.'),
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
    if (ok != true || !mounted) return;

    final success = await _service.deleteMessage(widget.chat.id, m.id);
    if (!mounted) return;
    _showSnack(
      success
          ? 'Сообщение удалено'
          : (_service.lastActionError ?? 'Не удалось удалить сообщение'),
    );
  }
}

enum _MsgAction { reply, forward, edit, delete }

class _ForwardTargetTile extends StatelessWidget {
  const _ForwardTargetTile({required this.chat, required this.onTap});

  final Chat chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
            children: [
              ChatAvatar(chat: chat, radius: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.ref, required this.onClose});

  final MessageReference ref;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        border: Border(
          top: BorderSide(color: CupertinoColors.separator.resolveFrom(context)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ref.authorName,
                    style: const TextStyle(
                      color: CupertinoColors.activeBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    ref.textPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onClose,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 20,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(color: CupertinoColors.separator.resolveFrom(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: onAttach,
                child: Icon(
                  CupertinoIcons.paperclip,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemGroupedBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: CupertinoTextField(
                    controller: textCtrl,
                    focusNode: focus,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    placeholder: 'Сообщение',
                    decoration: const BoxDecoration(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ListenableBuilder(
                listenable: textCtrl,
                builder: (context, _) {
                  final hasText = textCtrl.text.trim().isNotEmpty;
                  return CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    onPressed: hasText ? onSend : null,
                    child: Icon(
                      CupertinoIcons.arrow_up_circle_fill,
                      size: 30,
                      color: hasText
                          ? CupertinoColors.activeBlue
                          : CupertinoColors.systemGrey3.resolveFrom(context),
                    ),
                  );
                },
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

  Future<void> _showActions(BuildContext context) async {
    final canEdit =
        m.isOutgoing &&
        m.attachmentKind == ChatAttachmentKind.none &&
        (m.text?.trim().isNotEmpty ?? false);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              onLongMenu(_MsgAction.reply);
            },
            child: const Text('Ответить'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              onLongMenu(_MsgAction.forward);
            },
            child: const Text('Переслать'),
          ),
          if (canEdit) ...[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onLongMenu(_MsgAction.edit);
              },
              child: const Text('Редактировать'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                onLongMenu(_MsgAction.delete);
              },
              child: const Text('Удалить'),
            ),
          ],
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (m.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: Center(
          child: ChatMessageText(
            text: m.text ?? '',
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontSize: 12,
          ),
        ),
      );
    }

    final align = m.isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bubble = m.isOutgoing
        ? CupertinoColors.activeBlue
        : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          );
    final onBubble = m.isOutgoing
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);

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
                      style: const TextStyle(
                        color: CupertinoColors.activeBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            GestureDetector(
              onLongPress: () => _showActions(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                      color: CupertinoColors.black.withValues(alpha: 0.04),
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
                      if (m.forwardOf != null)
                        _ForwardBlock(ref: m.forwardOf!, onBubble: onBubble),
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
                                const Icon(CupertinoIcons.exclamationmark_triangle),
                          ),
                        )
                      else if (m.attachmentKind == ChatAttachmentKind.image &&
                          m.remoteMediaUrl != null)
                        AppNetworkImage(
                          url: m.remoteMediaUrl,
                          width: 220,
                          borderRadius: 8,
                        )
                      else if (m.attachmentKind == ChatAttachmentKind.image &&
                          kIsWeb)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('(изображение)'),
                        ),
                      if (m.attachmentKind == ChatAttachmentKind.video)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.play_circle,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(m.fileName ?? 'Видео', maxLines: 2),
                            ),
                          ],
                        ),
                      if (m.attachmentKind == ChatAttachmentKind.file)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.doc, size: 24),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(m.fileName ?? 'Файл', maxLines: 2),
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
                style: TextStyle(
                  fontSize: 10,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
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
          border: const Border(
            left: BorderSide(color: CupertinoColors.systemPurple, width: 3),
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
    final accent = isOutgoing ? CupertinoColors.white : CupertinoColors.activeBlue;
    final fill = isOutgoing
        ? CupertinoColors.white.withValues(alpha: 0.22)
        : CupertinoColors.activeBlue.withValues(alpha: 0.12);
    final textColor = isOutgoing
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: fill,
          border: Border(left: BorderSide(color: accent, width: 3)),
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
