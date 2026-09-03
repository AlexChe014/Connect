import 'dart:async';
import 'dart:io';

import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/models/chat/pinned_chat_message.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/screens/chat_settings_screen.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/utils/chat_file_share.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/widgets/app_empty_state.dart';
import 'package:connect/widgets/app_loading.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:connect/widgets/chat_active_call_banner.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:connect/widgets/chat_message_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar, showModalBottomSheet;
import 'package:flutter/services.dart' show HapticFeedback;
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
  final _callService = ChatCallService.instance;

  MessageReference? _replyingTo;
  ChatMessage? _editingMessage;
  bool _joiningCall = false;

  final _scrollTargetKey = GlobalKey();
  int? _scrollToReversedIndex;
  bool _didInitialScroll = false;

  bool _searchActive = false;
  final _searchCtrl = TextEditingController();
  List<int> _searchMatches = const [];
  int _searchCursor = -1;
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  /// Локальные реакции на сообщения (не синхронизируются с сервером, пока нет API).
  final Map<String, List<String>> _localReactions = {};
  final Map<String, GlobalKey> _messageKeys = {};
  bool _sendingAttachment = false;

  void _toggleReaction(ChatMessage m, String emoji) {
    setState(() {
      final current = List<String>.from(_localReactions[m.id] ?? m.reactions);
      if (current.contains(emoji)) {
        current.remove(emoji);
      } else {
        current.add(emoji);
      }
      _localReactions[m.id] = current;
    });
  }

  @override
  void initState() {
    super.initState();
    _service.addListener(_onMsg);
    _callService.addListener(_onCallState);
    _callService.watchChat(widget.chat.id);
    _service
        .loadMessages(widget.chat.id, force: true)
        .whenComplete(() => _service.markChatRead(widget.chat.id));
  }

  @override
  void dispose() {
    _service.removeListener(_onMsg);
    _callService.removeListener(_onCallState);
    _callService.unwatchChat(widget.chat.id);
    _textCtrl.dispose();
    _searchCtrl.dispose();
    _focus.dispose();
    _highlightTimer?.cancel();
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

  void _onCallState() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startVideoCall() async {
    if (_callService.isStartingCall || _joiningCall) return;

    try {
      await _callService.startCallFromChat(_c);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось начать видеозвонок';
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Ошибка'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _joinActiveCall() async {
    final call = _callService.activeCallFor(widget.chat.id);
    if (call == null || _joiningCall) return;

    setState(() => _joiningCall = true);
    try {
      await _callService.joinActiveCall(call);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось подключиться к звонку';
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Ошибка'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _joiningCall = false);
    }
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

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(
        builder: (context) => ChatSettingsScreen(chat: _c),
      ),
    );
    if (result == 'search' && mounted) {
      _activateSearch();
    }
  }

  void _activateSearch() {
    setState(() {
      _searchActive = true;
      _searchMatches = const [];
      _searchCursor = -1;
    });
  }

  void _closeSearch() {
    _highlightTimer?.cancel();
    setState(() {
      _searchActive = false;
      _searchCtrl.clear();
      _searchMatches = const [];
      _searchCursor = -1;
      _highlightedMessageId = null;
    });
    _focus.unfocus();
  }

  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    final list = _service.messagesFor(widget.chat.id);
    final matches = <int>[];
    if (query.isNotEmpty) {
      for (var i = 0; i < list.length; i++) {
        final m = list[i];
        if (m.isSystem) continue;
        final text = m.text;
        if (text == null || text.isEmpty) continue;
        if (HtmlTextUtils.toPlainText(text).toLowerCase().contains(query)) {
          matches.add(i);
        }
      }
    }
    setState(() {
      _searchMatches = matches;
      _searchCursor = matches.isEmpty ? -1 : matches.length - 1;
    });
    _gotoCurrentSearchMatch();
  }

  void _gotoCurrentSearchMatch() {
    if (_searchCursor < 0 || _searchCursor >= _searchMatches.length) return;
    final list = _service.messagesFor(widget.chat.id);
    final chronoIdx = _searchMatches[_searchCursor];
    if (chronoIdx >= list.length) return;
    final reversedIdx = list.length - 1 - chronoIdx;
    setState(() {
      _scrollToReversedIndex = reversedIdx;
      _highlightedMessageId = list[chronoIdx].id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _performSearchScroll());
  }

  void _performSearchScroll() {
    if (!mounted) return;
    final ctx = _scrollTargetKey.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _performSearchScroll(),
      );
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  void _prevSearchResult() {
    if (_searchCursor <= 0) return;
    setState(() => _searchCursor--);
    _gotoCurrentSearchMatch();
  }

  void _nextSearchResult() {
    if (_searchCursor >= _searchMatches.length - 1) return;
    setState(() => _searchCursor++);
    _gotoCurrentSearchMatch();
  }

  @override
  Widget build(BuildContext context) {
    final list = _service.messagesFor(widget.chat.id);
    final loading = _service.isMessagesLoading(widget.chat.id);
    final loadError = _service.messagesError(widget.chat.id);
    final c = _c;
    final activeCall = _callService.activeCallFor(widget.chat.id);
    final startingCall = _callService.isStartingCall;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context)
            .withValues(alpha: 0.94),
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
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
        trailing: startingCall
            ? const Padding(
                padding: EdgeInsets.only(right: 8),
                child: CupertinoActivityIndicator(),
              )
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _startVideoCall,
                child: const Icon(
                  CupertinoIcons.video_camera,
                  color: CupertinoColors.activeBlue,
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
              if (_searchActive) _buildSearchBar(context),
              if (activeCall != null && !_searchActive)
                ChatActiveCallBanner(
                  call: activeCall,
                  isGroup: c.isGroup,
                  peerName: c.title,
                  joining: _joiningCall,
                  onJoin: _joinActiveCall,
                ),
              if (!_searchActive) _buildPinnedBar(context),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _focus.unfocus,
                  child: loading && list.isEmpty
                      ? const AppPageLoader()
                      : loadError != null && list.isEmpty
                      ? AppEmptyState(
                          icon: CupertinoIcons.exclamationmark_triangle,
                          message: loadError,
                          onRetry: () => _service.loadMessages(
                            widget.chat.id,
                            force: true,
                          ),
                        )
                      : list.isEmpty
                      ? const AppEmptyState(
                          icon: CupertinoIcons.chat_bubble_2,
                          message: 'Пока нет сообщений — напишите первым',
                        )
                      : ListView.builder(
                          reverse: true,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
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
                                c.isGroup &&
                                !m.isOutgoing &&
                                !m.isSystem &&
                                (previous == null ||
                                    !_sameChatAuthor(previous, m));
                            final localReactions = _localReactions[m.id];
                            final displayMessage = localReactions == null
                                ? m
                                : m.copyWithReactions(localReactions);
                            final tile = _MessageTile(
                              m: displayMessage,
                              showAuthorHeader: showAuthorHeader,
                              showAvatarInHeader: showAuthorHeader,
                              showTime: _showMessageTime(m, next),
                              highlighted: m.id == _highlightedMessageId,
                              onReact: (emoji) => _toggleReaction(m, emoji),
                              onOpenFile: _openChatFile,
                              onLongMenu: (action) {
                                if (action == _MsgAction.reply) {
                                  setState(() {
                                    _replyingTo = _refFromMessage(m);
                                    _focus.requestFocus();
                                  });
                                } else if (action == _MsgAction.forward) {
                                  _openForwardTarget(m);
                                } else if (action == _MsgAction.edit) {
                                  _beginEditMessage(m);
                                } else if (action == _MsgAction.delete) {
                                  _deleteMessage(m);
                                } else if (action == _MsgAction.pin) {
                                  _togglePinMessage(m);
                                }
                              },
                            );
                            final wrapped = KeyedSubtree(
                              key: _keyForMessage(m.id),
                              child: tile,
                            );
                            if (i == _scrollToReversedIndex) {
                              return KeyedSubtree(
                                key: _scrollTargetKey,
                                child: wrapped,
                              );
                            }
                            return wrapped;
                          },
                        ),
                ),
              ),
              if (_editingMessage != null)
                _EditBanner(
                  text: _previewSnippet(_editingMessage!),
                  onClose: _cancelEdit,
                )
              else if (_replyingTo != null)
                _ReplyBanner(
                  ref: _replyingTo!,
                  onClose: () => setState(() => _replyingTo = null),
                ),
              _Composer(
                textCtrl: _textCtrl,
                focus: _focus,
                onSend: _send,
                onAttach: _openAttachMenu,
                isEditing: _editingMessage != null,
                isSendingAttachment: _sendingAttachment,
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

  Widget _buildSearchBar(BuildContext context) {
    final total = _searchMatches.length;
    final pos = total == 0 ? 0 : _searchMatches.length - _searchCursor;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              autofocus: true,
              placeholder: 'Поиск по чату',
              onChanged: _onSearchChanged,
            ),
          ),
          if (_searchCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              '$pos/$total',
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: _searchCursor > 0 ? _prevSearchResult : null,
              child: const Icon(CupertinoIcons.chevron_up, size: 20),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: _searchCursor < total - 1 ? _nextSearchResult : null,
              child: const Icon(CupertinoIcons.chevron_down, size: 20),
            ),
          ],
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: _closeSearch,
            child: const Icon(CupertinoIcons.xmark_circle_fill, size: 20),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final t = _textCtrl.text;
    if (t.trim().isEmpty) return;
    if (_editingMessage != null) {
      await _saveEdit();
      return;
    }
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
    final success = await _service.forwardMessage(
      id,
      m,
      sourceChatId: widget.chat.id,
    );
    if (!mounted) return;
    if (!success) {
      _showSnack(_service.lastActionError ?? 'Не удалось переслать сообщение');
    }
  }

  Future<void> _openAttachMenu() async {
    if (_sendingAttachment) return;
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

    List<int>? bytes;
    var name = 'file';

    try {
      if (choice == 'gallery') {
        final x = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 88,
        );
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name;
      } else if (choice == 'video') {
        final x = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 5),
        );
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name;
      } else if (choice == 'camera') {
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 88,
        );
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name;
      } else if (choice == 'file') {
        final r = await FilePicker.platform.pickFiles(withData: true);
        if (r == null || r.files.isEmpty) return;
        final f = r.files.single;
        name = f.name;
        bytes = f.bytes;
        if (bytes == null && f.path != null && !kIsWeb) {
          bytes = await File(f.path!).readAsBytes();
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Не удалось выбрать файл');
      return;
    }

    if (bytes == null || bytes.isEmpty) return;

    setState(() => _sendingAttachment = true);
    try {
      await _service.sendMedia(
        widget.chat.id,
        bytes: bytes,
        fileName: name,
        replyTo: _replyingTo,
      );
      if (_replyingTo != null && mounted) setState(() => _replyingTo = null);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Не удалось отправить файл');
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  /// Как в Telegram/WhatsApp: редактирование происходит прямо в поле ввода —
  /// текст сообщения подставляется в композер, над ним появляется плашка
  /// "Изменить сообщение", а отправка сохраняет правку вместо нового сообщения.
  void _beginEditMessage(ChatMessage m) {
    if (!m.canStillEdit) {
      _showSnack('Редактирование доступно в течение 15 минут после отправки');
      return;
    }
    setState(() {
      _replyingTo = null;
      _editingMessage = m;
      _textCtrl.text = m.text ?? '';
      _textCtrl.selection = TextSelection.collapsed(
        offset: _textCtrl.text.length,
      );
    });
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _textCtrl.clear();
    });
  }

  Future<void> _saveEdit() async {
    final m = _editingMessage;
    if (m == null) return;
    final newText = _textCtrl.text.trim();
    if (newText.isEmpty) return;

    final success = await _service.updateMessage(widget.chat.id, m.id, newText);
    if (!mounted) return;
    if (success) {
      setState(() {
        _editingMessage = null;
        _textCtrl.clear();
      });
    } else {
      _showSnack(_service.lastActionError ?? 'Не удалось обновить сообщение');
    }
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

  GlobalKey _keyForMessage(String id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  Future<void> _togglePinMessage(ChatMessage m) async {
    final success = m.isPinned
        ? await _service.unpinMessage(widget.chat.id, m.id)
        : await _service.pinMessage(widget.chat.id, m.id);
    if (!mounted) return;
    if (!success) {
      _showSnack(
        _service.lastActionError ??
            (m.isPinned
                ? 'Не удалось открепить сообщение'
                : 'Не удалось закрепить сообщение'),
      );
    }
  }

  Future<void> _openChatFile(ChatFile file) async {
    try {
      await ChatFileShare.share(file);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Не удалось скачать файл');
    }
  }

  void _jumpToMessage(String messageId) {
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx == null) {
      _showSnack('Сообщение ещё не загружено в историю');
      return;
    }
    setState(() => _highlightedMessageId = messageId);
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  Widget _buildPinnedBar(BuildContext context) {
    final pinned = _service.pinnedMessagesFor(widget.chat.id);
    if (pinned.isEmpty) return const SizedBox.shrink();
    final first = pinned.first;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (pinned.length == 1) {
          _jumpToMessage(first.message.id);
        } else {
          _showPinnedList(pinned);
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.pin_fill,
              size: 16,
              color: CupertinoColors.systemOrange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pinned.length == 1
                        ? 'Закреплённое сообщение'
                        : 'Закреплено: ${pinned.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.systemOrange,
                    ),
                  ),
                  Text(
                    _previewSnippet(first.message),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ],
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
    );
  }

  Future<void> _showPinnedList(List<PinnedChatMessage> pinned) async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Закреплённые сообщения'),
        actions: [
          for (final item in pinned)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, item.message.id),
              child: Text(
                _previewSnippet(item.message),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _jumpToMessage(selected);
  }
}

enum _MsgAction { reply, forward, edit, delete, pin }

/// Фиксированный набор быстрых реакций, как в iMessage/Telegram.
const List<String> _kQuickReactions = ['❤️', '👍', '👎', '😂', '‼️', '❓'];

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
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
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

class _EditBanner extends StatelessWidget {
  const _EditBanner({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.pencil,
              size: 18,
              color: CupertinoColors.activeBlue,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Изменить сообщение',
                    style: TextStyle(
                      color: CupertinoColors.activeBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    text,
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
    this.isEditing = false,
    this.isSendingAttachment = false,
  });

  final TextEditingController textCtrl;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool isEditing;
  final bool isSendingAttachment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
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
                onPressed: isSendingAttachment ? null : onAttach,
                child: isSendingAttachment
                    ? const CupertinoActivityIndicator(radius: 10)
                    : Icon(
                        CupertinoIcons.paperclip,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
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
                      isEditing
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.arrow_up_circle_fill,
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
    required this.onReact,
    required this.onOpenFile,
    this.showAuthorHeader = false,
    this.showAvatarInHeader = false,
    this.showTime = true,
    this.highlighted = false,
  });

  final ChatMessage m;
  final void Function(_MsgAction) onLongMenu;
  final void Function(String emoji) onReact;
  final void Function(ChatFile file) onOpenFile;
  final bool showAuthorHeader;
  final bool showAvatarInHeader;
  final bool showTime;
  final bool highlighted;

  List<Widget> _buildAttachments(BuildContext context, Color onBubble) {
    if (m.files.isNotEmpty) {
      return [
        for (final file in m.files) ...[
          _buildChatFile(context, file, onBubble),
          const SizedBox(height: 6),
        ],
      ];
    }

    if (m.attachmentKind == ChatAttachmentKind.image &&
        m.localMediaPath != null &&
        !kIsWeb) {
      return [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(m.localMediaPath!),
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(CupertinoIcons.exclamationmark_triangle),
          ),
        ),
      ];
    }
    if (m.attachmentKind == ChatAttachmentKind.image &&
        m.remoteMediaUrl != null) {
      return [
        AppNetworkImage(
          url: m.remoteMediaUrl,
          width: 220,
          borderRadius: 8,
          httpHeaders: ChatFileShare.imageHeaders(m.remoteMediaUrl),
        ),
      ];
    }
    if (m.attachmentKind == ChatAttachmentKind.image && kIsWeb) {
      return [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('(изображение)'),
        ),
      ];
    }
    if (m.attachmentKind == ChatAttachmentKind.video) {
      return [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.play_circle, size: 28),
            const SizedBox(width: 8),
            Flexible(child: Text(m.fileName ?? 'Видео', maxLines: 2)),
          ],
        ),
      ];
    }
    if (m.attachmentKind == ChatAttachmentKind.file) {
      return [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.doc, size: 24),
            const SizedBox(width: 8),
            Flexible(child: Text(m.fileName ?? 'Файл', maxLines: 2)),
          ],
        ),
      ];
    }
    return const [];
  }

  Widget _buildChatFile(BuildContext context, ChatFile file, Color onBubble) {
    final url = ChatRoutes.fileUrl(file.id);
    if (file.isImage) {
      return GestureDetector(
        onTap: () => onOpenFile(file),
        child: AppNetworkImage(
          url: url,
          width: 220,
          borderRadius: 8,
          httpHeaders: ChatFileShare.imageHeaders(url),
        ),
      );
    }

    return GestureDetector(
      onTap: () => onOpenFile(file),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            file.isVideo ? CupertinoIcons.play_circle : CupertinoIcons.doc,
            size: file.isVideo ? 28 : 24,
            color: onBubble,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.originalName, maxLines: 2),
                Text(
                  file.sizeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: onBubble.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapHighlight(BuildContext context, Widget child) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      color: highlighted
          ? CupertinoColors.systemYellow.withValues(alpha: 0.20)
          : const Color(0x00000000),
      child: child,
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final canEdit =
        m.isOutgoing &&
        m.attachmentKind == ChatAttachmentKind.none &&
        (m.text?.trim().isNotEmpty ?? false) &&
        m.canStillEdit;
    final canDelete = m.isOutgoing && m.canStillDelete;

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        message: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _kQuickReactions.map((emoji) {
              final active = m.reactions.contains(emoji);
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onReact(emoji);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: active
                        ? CupertinoColors.activeBlue.withValues(alpha: 0.15)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              );
            }).toList(),
          ),
        ),
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
          if (!m.isSystem)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onLongMenu(_MsgAction.pin);
              },
              child: Text(m.isPinned ? 'Открепить' : 'Закрепить'),
            ),
          if (canEdit)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onLongMenu(_MsgAction.edit);
              },
              child: const Text('Редактировать'),
            ),
          if (canDelete)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                onLongMenu(_MsgAction.delete);
              },
              child: const Text('Удалить'),
            ),
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
      return _wrapHighlight(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          child: Center(
            child: ChatMessageText(
              text: m.text ?? '',
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    if (m.isDeleted) {
      return _wrapHighlight(
        context,
        Align(
          alignment: m.isOutgoing
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.xmark_octagon,
                  size: 15,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'Сообщение удалено',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: CupertinoColors.secondaryLabel.resolveFrom(
                      context,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final align = m.isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bubble = m.isOutgoing
        ? CupertinoColors.activeBlue
        : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final onBubble = m.isOutgoing
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);

    return _wrapHighlight(
      context,
      Align(
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _SwipeToReply(
                    onReply: () => onLongMenu(_MsgAction.reply),
                    child: GestureDetector(
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
                              color: CupertinoColors.black.withValues(
                                alpha: 0.04,
                              ),
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
                                _ForwardBlock(
                                  ref: m.forwardOf!,
                                  onBubble: onBubble,
                                ),
                              if (m.replyTo != null)
                                _ReplyBlock(
                                  ref: m.replyTo!,
                                  isOutgoing: m.isOutgoing,
                                ),
                              if (m.isPinned)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons.pin_fill,
                                        size: 12,
                                        color: onBubble.withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Закреплено',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: onBubble.withValues(
                                            alpha: 0.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ..._buildAttachments(context, onBubble),
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
                  ),
                  if (m.reactions.isNotEmpty)
                    Positioned(
                      bottom: -10,
                      left: m.isOutgoing ? 8 : null,
                      right: m.isOutgoing ? null : 8,
                      child: GestureDetector(
                        onTap: () => _showActions(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemBackground.resolveFrom(
                              context,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: CupertinoColors.separator.resolveFrom(
                                context,
                              ),
                              width: 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: CupertinoColors.black.withValues(
                                  alpha: 0.06,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            m.reactions.join(' '),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (m.reactions.isNotEmpty) const SizedBox(height: 8),
              if (showTime) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.isEdited) ...[
                      Text(
                        'изменено',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: CupertinoColors.tertiaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _formatMsgTime(m.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                    if (m.isOutgoing) ...[
                      const SizedBox(width: 3),
                      _ReadReceipt(read: m.readByRecipients),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Свайп по сообщению справа налево запускает "Ответить" — по аналогии
/// с iMessage/Telegram: пузырь сдвигается за пальцем, при достижении
/// [_threshold] появляется тактильный отклик, а при отпускании после
/// порога вызывается [onReply] и пузырь анимированно возвращается на место.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.onReply, required this.child});

  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _maxDrag = 64;
  static const double _threshold = 48;

  late final AnimationController _controller;
  double _dragExtent = 0;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    final next = (_dragExtent + details.delta.dx).clamp(-_maxDrag, 0.0);
    if (next == _dragExtent) return;
    setState(() => _dragExtent = next);
    final armed = next <= -_threshold;
    if (armed != _armed) {
      _armed = armed;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final shouldReply = _armed;
    final animation = Tween<double>(
      begin: _dragExtent,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    void listener() => setState(() => _dragExtent = animation.value);
    animation.addListener(listener);
    _controller
      ..value = 0
      ..forward().whenCompleteOrCancel(() {
        animation.removeListener(listener);
      });
    _armed = false;
    if (shouldReply) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (-_dragExtent / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          if (progress > 0)
            Positioned(
              right: -28,
              child: Opacity(
                opacity: progress,
                child: Icon(
                  CupertinoIcons.arrowshape_turn_up_left_fill,
                  size: 18,
                  color: _armed
                      ? CupertinoColors.activeBlue
                      : CupertinoColors.systemGrey,
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Индикатор доставки/прочтения исходящего сообщения:
/// одна галочка — доставлено, две синие — прочитано получателем.
class _ReadReceipt extends StatelessWidget {
  const _ReadReceipt({required this.read});

  final bool read;

  @override
  Widget build(BuildContext context) {
    final color = read
        ? CupertinoColors.activeBlue
        : CupertinoColors.tertiaryLabel.resolveFrom(context);

    if (!read) {
      return Icon(CupertinoIcons.checkmark, size: 12, color: color);
    }

    // В Cupertino-наборе иконок нет готовой "двойной галочки" —
    // рисуем её как две перекрывающиеся одинарные (как в WhatsApp/Telegram).
    return SizedBox(
      width: 16,
      height: 12,
      child: Stack(
        children: [
          Icon(CupertinoIcons.checkmark, size: 12, color: color),
          Positioned(
            left: 4,
            child: Icon(CupertinoIcons.checkmark, size: 12, color: color),
          ),
        ],
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
    final accent = isOutgoing
        ? CupertinoColors.white
        : CupertinoColors.activeBlue;
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
