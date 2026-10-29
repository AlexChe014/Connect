import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_call_record.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/models/chat/chat_sticker.dart';
import 'package:connect/models/chat/pinned_chat_message.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/screens/chat_media_gallery_screen.dart';
import 'package:connect/screens/chat_settings_screen.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/services/chat_file_downloads.dart';
import 'package:connect/services/chat_realtime_service.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/services/chat_user_names.dart';
import 'package:connect/services/chat_voice_player.dart';
import 'package:connect/services/chat_voice_recorder.dart';
import 'package:connect/services/crash_reporting_service.dart';
import 'package:connect/utils/chat_file_share.dart';
import 'package:connect/utils/chat_mapper.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/utils/ru_plural.dart';
import 'package:connect/config/app_theme.dart';
import 'package:connect/widgets/app_empty_state.dart';
import 'package:connect/widgets/app_glass.dart';
import 'package:connect/widgets/app_loading.dart';
import 'package:connect/widgets/chat_active_call_banner.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:connect/widgets/chat_download_ring.dart';
import 'package:connect/widgets/chat_message_text.dart';
import 'package:connect/widgets/chat_link_preview.dart';
import 'package:connect/widgets/chat_voice_message.dart';
import 'package:connect/widgets/mail_glass.dart' show MailGlassIconButton;
import 'package:connect/widgets/message_context_menu.dart';
import 'package:connect/widgets/read_receipt.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/material.dart'
    show Colors, ScaffoldMessenger, SnackBar, showModalBottomSheet;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:connect/services/haptics_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

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

bool _sameDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

/// «Сегодня», «Вчера», «12 сентября» или «12 сентября 2025» — для плашки
/// с датой между сообщениями разных дней.
String _formatDayLabel(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  if (_sameDay(l, now)) return 'Сегодня';
  if (_sameDay(l, now.subtract(const Duration(days: 1)))) return 'Вчера';
  final pattern = l.year == now.year ? 'd MMMM' : 'd MMMM y';
  return DateFormat(pattern, 'ru_RU').format(l);
}

bool _showMessageTime(ChatMessage m, ChatMessage? next) {
  if (next == null || !_sameChatAuthor(m, next)) return true;
  if (!_sameDay(m.createdAt, next.createdAt)) return true;
  return next.createdAt.difference(m.createdAt).inMinutes >= 2;
}

class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({super.key, required this.chat});

  final Chat chat;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen>
    with WidgetsBindingObserver {
  final _textCtrl = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  final _service = ChatService.instance;
  final _callService = ChatCallService.instance;

  MessageReference? _replyingTo;
  ChatMessage? _editingMessage;

  /// Что было набрано в композере до правки — вернётся после неё.
  String _draftBeforeEdit = '';
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
  final _listCtrl = ScrollController();

  /// Последний построенный `itemBuilder`-ом индекс (в перевёрнутом списке) —
  /// по нему [_scrollToMessage] понимает, в какую сторону листать.
  int _lastBuiltIndex = 0;
  bool _jumpingToPinned = false;
  Timer? _liveRefresh;
  DateTime _lastLiveRefresh = DateTime.now();
  Timer? _draftSaveTimer;

  /// Локальные реакции на сообщения (не синхронизируются с сервером, пока нет API).
  final Map<String, List<String>> _localReactions = {};
  final Map<String, GlobalKey> _messageKeys = {};
  bool _sendingAttachment = false;

  final _voice = ChatVoiceRecorder.instance;
  Offset _voiceDrag = Offset.zero;

  /// Палец ещё на микрофоне — если отпустили раньше, чем запись
  /// стартовала (диалог доступа), её сразу отменяем.
  bool _voicePressed = false;
  bool _voiceStarting = false;
  bool _voiceCancelled = false;

  /// Смахнули вверх на замок — запись идёт без пальца, отправка кнопкой.
  bool _voiceLocked = false;

  /// Остановили запись на замке — слушаем перед отправкой.
  ChatVoiceRecording? _voiceDraft;

  /// Выбранные сообщения; режим выбора включён, пока набор не пуст.
  final Set<String> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;

  /// Пользователь отлистал больше экрана вверх — показываем кнопку «вниз».
  bool _showScrollDown = false;

  /// Первое непрочитанное при входе — над ним плашка «Новые сообщения».
  /// Берётся до [ChatService.markChatRead], иначе флаги уже сброшены.
  String? _unreadDividerId;
  bool _unreadCaptured = false;

  /// Входящие ниже экрана — счётчик на кнопке «вниз».
  int _unseenBelow = 0;
  String? _tailMessageId;
  bool _jumpingToDate = false;

  /// Набирают `@имя` в группе: начало `@` в тексте и подходящие участники.
  int? _mentionStart;
  List<ChatMemberSummary> _mentionSuggestions = const [];
  bool _sendingText = false;

  /// Высоты плавающих стеклянных панелей над лентой (поиск, звонок,
  /// закреп) и под ней (ответ/правка, поле ввода) — на столько лента
  /// отступает, чтобы крайние сообщения не прятались под стеклом.
  double _topOverlayHeight = 0;
  double _bottomOverlayHeight = 0;

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
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_onMsg);
    _callService.addListener(_onCallState);
    _callService.watchChat(widget.chat.id);
    _service.setActiveChat(widget.chat.id);
    _voice.onMaxDuration = _finishVoice;
    unawaited(_voice.warmUp());
    _service
        .loadMessages(widget.chat.id, force: true)
        .whenComplete(() => _service.markChatRead(widget.chat.id));
    // Подстраховка к сокету: без него — опрос раз в 4 с, с ним — раз в
    // 30 с (закрепы, пропущенные события). Каждый опрос — три запроса.
    _liveRefresh = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final now = DateTime.now();
      // Секунда запаса: тики таймера плавают и иначе пропускался бы каждый.
      final interval = ChatRealtimeService.instance.isConnected
          ? const Duration(seconds: 29)
          : const Duration(seconds: 3);
      if (now.difference(_lastLiveRefresh) < interval) return;
      _lastLiveRefresh = now;
      unawaited(
        _service.loadMessages(widget.chat.id, force: true, showLoading: false),
      );
    });
    final draft = widget.chat.draftText;
    if (draft != null && draft.isNotEmpty) {
      _textCtrl.text = draft;
      _textCtrl.selection = TextSelection.collapsed(offset: draft.length);
    }
    _textCtrl.addListener(_onDraftTextChanged);
    _textCtrl.addListener(_onMentionInput);
    _listCtrl.addListener(_onListScroll);
  }

  /// Лента перевёрнута: верх истории — это maxScrollExtent. Догружаем
  /// старые сообщения заранее, за пару экранов до края.
  void _onListScroll() {
    if (!_listCtrl.hasClients) return;
    final pos = _listCtrl.position;
    final showScrollDown = pos.pixels > pos.viewportDimension;
    if (showScrollDown != _showScrollDown) {
      setState(() => _showScrollDown = showScrollDown);
    }
    if (_unseenBelow > 0 && pos.pixels < 40) {
      setState(() => _unseenBelow = 0);
    }
    if (pos.maxScrollExtent - pos.pixels > pos.viewportDimension * 2) return;
    final chatId = widget.chat.id;
    if (!_service.hasOlderMessages(chatId) || _service.isLoadingOlder(chatId)) {
      return;
    }
    unawaited(_service.loadOlderMessages(chatId));
  }

  /// Лента перевёрнута: низ (свежие сообщения) — это offset 0.
  void _scrollToBottom() {
    if (_unseenBelow > 0) setState(() => _unseenBelow = 0);
    if (!_listCtrl.hasClients || _listCtrl.offset <= 0) return;
    final far = _listCtrl.offset > _listCtrl.position.viewportDimension * 3;
    if (far) {
      // Долгая анимация через всю историю строила бы каждое сообщение.
      _listCtrl.jumpTo(0);
    } else {
      _listCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  static final _mentionTokenRe = RegExp(r'(?:^|\s)@([^\s@]{0,30})$');

  /// Слово с `@` перед курсором — подсказываем участников группы.
  void _onMentionInput() {
    final value = _textCtrl.value;
    final cursor = value.selection.baseOffset;
    int? start;
    var suggestions = const <ChatMemberSummary>[];
    if (_c.isGroup && value.selection.isCollapsed && cursor >= 0) {
      final match = _mentionTokenRe.firstMatch(value.text.substring(0, cursor));
      if (match != null) {
        final query = match.group(1)!.toLowerCase();
        start = cursor - query.length - 1;
        final self = _service.selfUserId;
        suggestions = _c.members
            .where(
              (m) =>
                  m.userId != self &&
                  m.displayName.trim().isNotEmpty &&
                  (query.isEmpty ||
                      m.displayName
                          .toLowerCase()
                          .split(RegExp(r'\s+'))
                          .any((w) => w.startsWith(query))),
            )
            .take(6)
            .toList();
      }
    }
    if (start == _mentionStart &&
        listEquals(suggestions, _mentionSuggestions)) {
      return;
    }
    setState(() {
      _mentionStart = suggestions.isEmpty ? null : start;
      _mentionSuggestions = suggestions;
    });
  }

  void _insertMention(ChatMemberSummary member) {
    final start = _mentionStart;
    final value = _textCtrl.value;
    final cursor = value.selection.baseOffset;
    if (start == null || cursor < start) return;
    final insert = '@${member.displayName.trim()} ';
    _textCtrl.value = TextEditingValue(
      text: value.text.replaceRange(start, cursor, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    AppHaptics.selection();
  }

  /// Имя участника → id: по ним в тексте подсвечиваются `@упоминания`.
  Map<String, int> get _mentionTargets {
    final c = _c;
    if (!c.isGroup) return const {};
    return {
      for (final m in c.members)
        if (m.displayName.trim().isNotEmpty) m.displayName.trim(): m.userId,
    };
  }

  void _onDraftTextChanged() {
    if (_editingMessage != null) return;
    _draftSaveTimer?.cancel();
    final text = _textCtrl.text;
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_service.setDraftText(widget.chat.id, text));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveRefresh?.cancel();
    _service.removeListener(_onMsg);
    _callService.removeListener(_onCallState);
    _callService.unwatchChat(widget.chat.id);
    _service.clearActiveChat(widget.chat.id);
    _draftSaveTimer?.cancel();
    if (_editingMessage == null) {
      unawaited(_service.setDraftText(widget.chat.id, _textCtrl.text));
    }
    if (_voice.onMaxDuration == _finishVoice) _voice.onMaxDuration = null;
    unawaited(_voice.cancel());
    _discardVoiceDraft();
    _textCtrl.removeListener(_onDraftTextChanged);
    _textCtrl.removeListener(_onMentionInput);
    _textCtrl.dispose();
    _searchCtrl.dispose();
    _focus.dispose();
    _highlightTimer?.cancel();
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final chatId = widget.chat.id;
    if (state == AppLifecycleState.resumed) {
      _service.setActiveChat(chatId);
      unawaited(
        _service
            .loadMessages(chatId, force: true, showLoading: false)
            .whenComplete(() => _service.markChatRead(chatId)),
      );
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Свёрнутое приложение не читает переписку: иначе пришедшие по сокету
      // или пушу сообщения сразу отмечались бы прочитанными у собеседника.
      _service.clearActiveChat(chatId);
    }
  }

  void _onMsg() {
    if (!mounted) return;
    // Синхронно: сразу после загрузки сервис помечает чат прочитанным,
    // и к следующему кадру флаги непрочитанных уже сброшены.
    _captureUnreadAnchor();
    _countNewIncoming();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _scheduleInitialScroll();
      // Страница догрузилась, а пользователь так и стоит у верха — следующую.
      if (!_service.olderLoadFailed(widget.chat.id)) _onListScroll();
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

  void _captureUnreadAnchor() {
    if (_unreadCaptured) return;
    final list = _service.messagesFor(widget.chat.id);
    if (list.isEmpty || _service.isMessagesLoading(widget.chat.id)) return;
    _unreadCaptured = true;
    _tailMessageId = list.last.id;
    final idx = list.indexWhere((m) => !m.isOutgoing && !m.isRead);
    if (idx < 0) return;
    _unreadDividerId = list[idx].id;
    if (idx < list.length - 1) {
      _unseenBelow = list
          .skip(idx)
          .where((m) => !m.isOutgoing && !m.isSystem)
          .length;
    }
  }

  /// Пришли новые входящие, пока лента отлистана вверх.
  void _countNewIncoming() {
    if (!_unreadCaptured) return;
    final list = _service.messagesFor(widget.chat.id);
    if (list.isEmpty) return;
    final tail = list.last.id;
    if (tail == _tailMessageId) return;
    final prevIdx = _tailMessageId == null
        ? -1
        : list.lastIndexWhere((m) => m.id == _tailMessageId);
    _tailMessageId = tail;
    if (prevIdx < 0 || !_showScrollDown) return;
    _unseenBelow += list
        .skip(prevIdx + 1)
        .where((m) => !m.isOutgoing && !m.isSystem)
        .length;
  }

  void _scheduleInitialScroll() {
    if (_didInitialScroll) return;

    final list = _service.messagesFor(widget.chat.id);
    if (list.isEmpty || _service.isMessagesLoading(widget.chat.id)) return;

    final unreadIdx = _unreadDividerId == null
        ? -1
        : list.indexWhere((m) => m.id == _unreadDividerId);
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
    unawaited(_scrollToMessage(list[chronoIdx].id));
  }

  /// Прокручивает ленту к сообщению и подсвечивает его. Список ленивый —
  /// виджет далёкого сообщения ещё не построен, поэтому сначала прыгаем
  /// в примерную позицию, а потом шагами по экрану, пока он не появится.
  Future<bool> _scrollToMessage(String messageId) async {
    setState(() => _highlightedMessageId = messageId);
    for (var attempt = 0; attempt < 80; attempt++) {
      if (!mounted) return false;
      final ctx = _messageKeys[messageId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
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
        return true;
      }

      final list = _service.messagesFor(widget.chat.id);
      final chronoIdx = list.indexWhere((m) => m.id == messageId);
      if (chronoIdx < 0 || !_listCtrl.hasClients) break;
      final target = list.length - 1 - chronoIdx;
      final pos = _listCtrl.position;
      double next;
      if (attempt == 0 && list.length > 1) {
        next = pos.maxScrollExtent * target / (list.length - 1);
      } else {
        final step = pos.viewportDimension * 0.9;
        next = pos.pixels + (_lastBuiltIndex < target ? step : -step);
      }
      next = next.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (attempt > 0 && next == pos.pixels) break;
      _listCtrl.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted) setState(() => _highlightedMessageId = null);
    return false;
  }

  /// Тап по плашке даты — календарь, как в Telegram.
  Future<void> _pickDate(DateTime current) async {
    if (_jumpingToDate) return;
    final now = DateTime.now();
    var picked = current.toLocal();
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Отмена'),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Перейти',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: picked.isAfter(now) ? now : picked,
                  maximumDate: now,
                  dateOrder: DatePickerDateOrder.dmy,
                  onDateTimeChanged: (d) => picked = d,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) await _jumpToDate(picked);
  }

  /// Первое сообщение выбранного дня или ближайшее после него; старую
  /// историю догружаем страницами, пока не дойдём до даты.
  Future<void> _jumpToDate(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final chatId = widget.chat.id;
    setState(() => _jumpingToDate = true);
    try {
      for (var page = 0; page < 40; page++) {
        final list = _service.messagesFor(chatId);
        if (list.isEmpty || !list.first.createdAt.toLocal().isAfter(start)) {
          break;
        }
        if (!_service.hasOlderMessages(chatId)) break;
        await _service.loadOlderMessages(chatId);
        if (!mounted) return;
        if (_service.olderLoadFailed(chatId)) {
          _showSnack('Не удалось загрузить историю');
          return;
        }
      }
      final list = _service.messagesFor(chatId);
      if (list.isEmpty) return;
      final target = list.firstWhere(
        (m) => !m.createdAt.toLocal().isBefore(start),
        orElse: () => list.last,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (!_sameDay(target.createdAt, start) &&
          target.createdAt.toLocal().isAfter(start)) {
        _showSnack(
          'В этот день сообщений нет — показываю ближайшие после него',
        );
      }
      await _scrollToMessage(target.id);
    } finally {
      if (mounted) setState(() => _jumpingToDate = false);
    }
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
    final mentionTargets = _mentionTargets;
    final activeCall = _callService.bannerCallFor(widget.chat.id);
    final startingCall = _callService.isStartingCall;

    return PopScope(
      // Назад в режиме выбора снимает выбор, а не закрывает чат.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground.resolveFrom(context),
        navigationBar: CupertinoNavigationBar(
          // Прозрачная: сообщения растворяются под ней в [_EdgeFade],
          // а не обрезаются кромкой размытой полосы.
          backgroundColor: AppColors.groupedBackground
              .resolveFrom(context)
              .withValues(alpha: 0),
          automaticBackgroundVisibility: false,
          enableBackgroundFilterBlur: false,
          border: null,
          leading: _selecting
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _clearSelection,
                  child: const Text('Отмена'),
                )
              // Стеклянный кружок в высоту капсулы с именем — как кнопка
              // звонка справа.
              : MailGlassIconButton(
                  icon: CupertinoIcons.chevron_back,
                  size: 40,
                  onPressed: () => Navigator.maybePop(context),
                ),
          middle: _selecting
              ? Text('Выбрано: ${_selectedIds.length}')
              : _ChatTitleCapsule(chat: c, onTap: _openSettings),
          trailing: _selecting
              ? null
              : startingCall
              ? AppGlass(
                  borderRadius: BorderRadius.circular(20),
                  shadows: AppGlass.controlShadow,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: CupertinoActivityIndicator(),
                  ),
                )
              : MailGlassIconButton(
                  icon: CupertinoIcons.video_camera,
                  size: 40,
                  onPressed: _startVideoCall,
                ),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 15,
          ),
          child: Builder(
            // Свой context — под скаффолдом, где в MediaQuery уже учтена
            // высота полупрозрачной шапки.
            builder: (context) => Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _focus.unfocus,
                    child: loading && list.isEmpty
                        ? const AppPageLoader()
                        : loadError != null && list.isEmpty
                        ? AppEmptyState(
                            icon: CupertinoIcons.cloud,
                            title: 'Не удалось загрузить сообщения',
                            message: loadError,
                            retryLabel: 'Попробовать снова',
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
                            controller: _listCtrl,
                            reverse: true,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              10,
                              MediaQuery.paddingOf(context).top +
                                  _topOverlayHeight +
                                  10,
                              10,
                              _bottomOverlayHeight + 10,
                            ),
                            itemCount:
                                list.length +
                                (_service.hasOlderMessages(widget.chat.id)
                                    ? 1
                                    : 0),
                            itemBuilder: (context, i) {
                              if (i >= list.length) {
                                // Конец перевёрнутого списка — верх истории.
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: CupertinoActivityIndicator(),
                                );
                              }
                              _lastBuiltIndex = i;
                              final chronologicalIndex = list.length - 1 - i;
                              final m = list[chronologicalIndex];
                              final previous = chronologicalIndex > 0
                                  ? list[chronologicalIndex - 1]
                                  : null;
                              final next = chronologicalIndex < list.length - 1
                                  ? list[chronologicalIndex + 1]
                                  : null;
                              final startsNewDay =
                                  previous == null ||
                                  !_sameDay(previous.createdAt, m.createdAt);
                              final showAuthorHeader =
                                  c.isGroup &&
                                  !m.isOutgoing &&
                                  !m.isSystem &&
                                  (previous == null ||
                                      startsNewDay ||
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
                                selectionMode: _selecting,
                                selected: _selectedIds.contains(m.id),
                                onToggleSelect: () => _toggleSelected(m),
                                onOpenAuthor: _openAuthorChat,
                                mentions: mentionTargets,
                                onReact: (emoji) => _toggleReaction(m, emoji),
                                onOpenFile: _openChatFile,
                                onOpenImages: (images, index) =>
                                    _openChatImages(m, images, index),
                                onLongMenu: (action) {
                                  if (action == _MsgAction.reply) {
                                    setState(() {
                                      _replyingTo = _refFromMessage(m);
                                      _focus.requestFocus();
                                    });
                                  } else if (action == _MsgAction.copy) {
                                    _copyMessage(m);
                                  } else if (action == _MsgAction.forward) {
                                    _openForwardTarget([m]);
                                  } else if (action == _MsgAction.select) {
                                    _toggleSelected(m);
                                  } else if (action == _MsgAction.edit) {
                                    _beginEditMessage(m);
                                  } else if (action == _MsgAction.delete) {
                                    _deleteMessage(m);
                                  } else if (action == _MsgAction.pin) {
                                    _togglePinMessage(m);
                                  }
                                },
                              );
                              final keyed = KeyedSubtree(
                                key: _keyForMessage(m.id),
                                child: tile,
                              );
                              final unreadDivider = m.id == _unreadDividerId;
                              final wrapped = startsNewDay || unreadDivider
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (startsNewDay)
                                          _DaySeparator(
                                            label: _formatDayLabel(m.createdAt),
                                            onTap: () => _pickDate(m.createdAt),
                                          ),
                                        if (unreadDivider)
                                          const _UnreadDivider(),
                                        keyed,
                                      ],
                                    )
                                  : keyed;
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
                _EdgeFade.top(
                  height:
                      MediaQuery.paddingOf(context).top +
                      _topOverlayHeight +
                      24,
                ),
                _EdgeFade.bottom(height: _bottomOverlayHeight + 24),
                if (_jumpingToDate)
                  Positioned(
                    top:
                        MediaQuery.paddingOf(context).top +
                        _topOverlayHeight +
                        12,
                    left: 0,
                    right: 0,
                    child: const Center(
                      child: _GlassCapsule(
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.all(10),
                        child: CupertinoActivityIndicator(radius: 9),
                      ),
                    ),
                  ),
                if (_showScrollDown)
                  Positioned(
                    right: 12,
                    bottom: _bottomOverlayHeight + 10,
                    child: _ScrollDownButton(
                      onTap: _scrollToBottom,
                      unseen: _unseenBelow,
                    ),
                  ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top,
                  left: 0,
                  right: 0,
                  child: _MeasureHeight(
                    onChange: (h) {
                      if (mounted && h != _topOverlayHeight) {
                        setState(() => _topOverlayHeight = h);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _MeasureHeight(
                    onChange: (h) {
                      if (mounted && h != _bottomOverlayHeight) {
                        setState(() => _bottomOverlayHeight = h);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selecting)
                          _SelectionBar(
                            onForward: _forwardSelected,
                            onCopy: _selectedTextMessages().isEmpty
                                ? null
                                : _copySelected,
                            onDelete: _canDeleteSelected
                                ? _deleteSelected
                                : null,
                          )
                        else if (_editingMessage != null)
                          _EditBanner(
                            text: _previewSnippet(_editingMessage!),
                            onClose: _cancelEdit,
                          )
                        else if (_replyingTo != null)
                          _ReplyBanner(
                            ref: _replyingTo!,
                            onClose: () => setState(() => _replyingTo = null),
                          ),
                        if (!_selecting && _mentionSuggestions.isNotEmpty)
                          _MentionSuggestions(
                            members: _mentionSuggestions,
                            onSelect: _insertMention,
                          ),
                        if (!_selecting)
                          _Composer(
                            textCtrl: _textCtrl,
                            focus: _focus,
                            onSend: _send,
                            onAttach: _openAttachMenu,
                            onStickers:
                                _editingMessage != null ||
                                    !ChatStickers.imagesAvailable
                                ? null
                                : _openStickerPicker,
                            isEditing: _editingMessage != null,
                            isSendingAttachment: _sendingAttachment,
                            onVoiceStart:
                                _editingMessage != null || _sendingAttachment
                                ? null
                                : _startVoice,
                            onVoiceMove: _moveVoice,
                            onVoiceEnd: _endVoice,
                            onVoiceSend: _finishVoice,
                            onVoiceCancel: _cancelLockedVoice,
                            onVoiceStop: _stopVoiceToDraft,
                            voiceDraft: _voiceDraft,
                            onVoiceDraftSend: _sendVoiceDraft,
                            onVoiceDraftDelete: () {
                              AppHaptics.medium();
                              setState(_discardVoiceDraft);
                            },
                            voiceDrag: _voiceDrag,
                            voiceLocked: _voiceLocked,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
    final voice = ChatMapper.voiceSnippet(m);
    if (voice != null) return voice;
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
    // Новое сообщение сразу сменяет предыдущее, а не ждёт его в очереди.
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSearchBar(BuildContext context) {
    final total = _searchMatches.length;
    final pos = total == 0 ? 0 : _searchMatches.length - _searchCursor;
    return _GlassCapsule(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
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
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
    if (_editingMessage != null) {
      await _saveEdit();
      return;
    }
    if (_sendingText) return;
    final t = _textCtrl.text;
    if (t.trim().isEmpty) return;
    final replyTo = _replyingTo;
    _sendingText = true;
    AppHaptics.light();
    _textCtrl.clear();
    if (mounted) setState(() => _replyingTo = null);
    _scrollToBottom();
    try {
      await _service.sendText(widget.chat.id, t, replyTo: replyTo);
    } catch (e) {
      if (mounted) {
        _textCtrl.text = t;
        AppHaptics.error();
        _showSnack(
          e is ApiException ? e.message : 'Не удалось отправить сообщение',
        );
      }
    } finally {
      _sendingText = false;
    }
  }

  Future<void> _openStickerPicker() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.groupedBackground.resolveFrom(context),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: SafeArea(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: ChatStickers.ids.length,
            itemBuilder: (context, i) {
              final id = ChatStickers.ids[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, id),
                child: _ChatSticker(id: id),
              );
            },
          ),
        ),
      ),
    );
    if (id == null || !mounted) return;
    final replyTo = _replyingTo;
    setState(() => _replyingTo = null);
    _scrollToBottom();
    try {
      await _service.sendSticker(widget.chat.id, id, replyTo: replyTo);
    } catch (e) {
      if (mounted) {
        _showSnack(
          e is ApiException ? e.message : 'Не удалось отправить стикер',
        );
      }
    }
  }

  Future<void> _openForwardTarget(List<ChatMessage> messages) async {
    final other = _service.chats.where((c) => c.id != widget.chat.id).toList();
    if (other.isEmpty) {
      _showSnack('Нет других чатов для пересылки');
      return;
    }
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.groupedBackground.resolveFrom(context),
      builder: (context) => _ForwardTargetSheet(chats: other),
    );
    if (ids == null || ids.isEmpty) return;
    final success = await _service.forwardMessages(
      ids,
      messages,
      sourceChatId: widget.chat.id,
    );
    if (!mounted) return;
    if (success) _clearSelection();
    _showSnack(
      success
          ? (messages.length > 1
                ? 'Сообщения пересланы'
                : 'Сообщение переслано')
          : (_service.lastActionError ?? 'Не удалось переслать сообщение'),
    );
  }

  Future<void> _startVoice() async {
    if (_voiceLocked) return;
    if (_callService.isBusy) {
      _showSnack('Во время звонка записать голосовое нельзя');
      return;
    }
    _voicePressed = true;
    _voiceCancelled = false;
    // Повторное касание, пока прошлый старт ещё идёт: второй не запускаем.
    if (_voiceStarting || _voice.isRecording) return;
    _voiceStarting = true;
    _focus.unfocus();
    final bool ok;
    try {
      ok = await _voice.start();
    } finally {
      _voiceStarting = false;
    }
    if (!mounted) return;
    if (!ok) {
      _voicePressed = false;
      _showSnack('Нет доступа к микрофону — разрешите его в Настройках');
      return;
    }
    if (!_voicePressed) {
      // Отпустили раньше, чем рекордер успел включиться — это был тап.
      await _voice.cancel();
      _showVoiceHint();
      return;
    }
    AppHaptics.medium();
  }

  void _showVoiceHint() => _showSnack(
    'Удерживайте микрофон, чтобы записать голосовое, '
    'или смахните вверх на замок',
  );

  void _moveVoice(Offset d) {
    if (!_voice.isRecording || _voiceCancelled || _voiceLocked) return;
    if (d.dx <= -_voiceCancelDistance) {
      _voiceCancelled = true;
      AppHaptics.medium();
      unawaited(_voice.cancel());
      setState(() => _voiceDrag = Offset.zero);
      return;
    }
    if (d.dy <= -_voiceLockDistance) {
      AppHaptics.medium();
      setState(() {
        _voiceLocked = true;
        _voiceDrag = Offset.zero;
      });
      return;
    }
    // Ведут в одну сторону — вторую подсказку не дёргаем.
    final horizontal = d.dx.abs() > d.dy.abs();
    setState(
      () => _voiceDrag = Offset(
        horizontal ? d.dx.clamp(-_voiceCancelDistance, 0) : 0,
        horizontal ? 0 : d.dy.clamp(-_voiceLockDistance, 0),
      ),
    );
  }

  /// Палец отпустили. На замке запись продолжается.
  Future<void> _endVoice() async {
    _voicePressed = false;
    if (_voiceDrag != Offset.zero) setState(() => _voiceDrag = Offset.zero);
    if (_voiceLocked || _voiceCancelled || !_voice.isRecording) return;
    await _finishVoice();
  }

  void _cancelLockedVoice() {
    AppHaptics.medium();
    setState(() => _voiceLocked = false);
    unawaited(_voice.cancel());
  }

  /// Останавливает запись и отправляет — по отпусканию, кнопкой на замке
  /// или по лимиту длительности.
  Future<void> _finishVoice() async {
    if (_voiceLocked) setState(() => _voiceLocked = false);
    if (!_voice.isRecording) return;
    final recording = await _voice.stop();
    if (!mounted) {
      unawaited(recording?.file.delete().catchError((_) => recording.file));
      return;
    }
    if (recording == null) {
      _showVoiceHint();
      return;
    }
    await _sendVoiceRecording(recording);
  }

  /// «Стоп» на замке: запись не уходит сразу, её можно прослушать.
  Future<void> _stopVoiceToDraft() async {
    if (_voiceLocked) setState(() => _voiceLocked = false);
    if (!_voice.isRecording) return;
    final recording = await _voice.stop();
    if (!mounted) {
      unawaited(recording?.file.delete().catchError((_) => recording.file));
      return;
    }
    if (recording == null) {
      _showVoiceHint();
      return;
    }
    setState(() => _voiceDraft = recording);
  }

  Future<void> _sendVoiceDraft() async {
    final draft = _voiceDraft;
    if (draft == null) return;
    setState(() => _voiceDraft = null);
    if (ChatVoicePlayer.instance.isCurrent(ChatVoicePlayer.draftId)) {
      unawaited(ChatVoicePlayer.instance.stop());
    }
    await _sendVoiceRecording(draft);
  }

  void _discardVoiceDraft() {
    final draft = _voiceDraft;
    if (draft == null) return;
    _voiceDraft = null;
    if (ChatVoicePlayer.instance.isCurrent(ChatVoicePlayer.draftId)) {
      unawaited(ChatVoicePlayer.instance.stop());
    }
    unawaited(draft.file.delete().catchError((_) => draft.file));
  }

  Future<void> _sendVoiceRecording(ChatVoiceRecording recording) async {
    setState(() => _sendingAttachment = true);
    _scrollToBottom();
    try {
      await _service.sendMedia(
        widget.chat.id,
        files: [
          (bytes: await recording.file.readAsBytes(), name: recording.fileName),
        ],
        replyTo: _replyingTo,
      );
      if (_replyingTo != null && mounted) setState(() => _replyingTo = null);
    } catch (e) {
      debugPrint('voice: send failed: $e');
      if (mounted) {
        _showSnack(
          e is ApiException ? e.message : 'Не удалось отправить голосовое',
        );
      }
    } finally {
      unawaited(recording.file.delete().catchError((_) => recording.file));
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  bool _openingAuthorChat = false;

  /// Личный чат с автором пересланного сообщения — уже существующий или
  /// новый. Свой собственный и текущий личный чат не открываем.
  Future<void> _openAuthorChat(int userId) async {
    if (_openingAuthorChat || userId == _service.selfUserId) return;
    final c = _c;
    if (!c.isGroup && c.peerUserId == userId) return;
    _openingAuthorChat = true;
    try {
      final chat =
          _service.findDirectChatForUser(userId) ??
          await _service.createDirect(
            fullName: ChatUserNames.instance.nameFor(userId) ?? 'Пользователь',
            peerUserId: userId,
          );
      if (!mounted) return;
      if (chat == null) {
        _showSnack('Не удалось открыть чат');
        return;
      }
      await Navigator.of(context).push<void>(
        CupertinoPageRoute<void>(
          builder: (context) => ChatConversationScreen(chat: chat),
        ),
      );
    } finally {
      _openingAuthorChat = false;
    }
  }

  bool _isSelectable(ChatMessage m) => m.canForward;

  void _toggleSelected(ChatMessage m) {
    if (!_isSelectable(m)) return;
    if (!_selectedIds.contains(m.id) &&
        _selectedIds.length >= _maxForwardMessages) {
      _showSnack('Можно выбрать не больше $_maxForwardMessages сообщений');
      return;
    }
    AppHaptics.selection();
    setState(() {
      if (!_selectedIds.remove(m.id)) _selectedIds.add(m.id);
    });
    if (_selecting) _focus.unfocus();
  }

  void _clearSelection() {
    if (!_selecting) return;
    setState(_selectedIds.clear);
  }

  /// Выбранные сообщения в хронологическом порядке.
  List<ChatMessage> _selectedMessages() => [
    for (final m in _service.messagesFor(widget.chat.id))
      if (_selectedIds.contains(m.id)) m,
  ];

  List<ChatMessage> _selectedTextMessages() => [
    for (final m in _selectedMessages())
      if (!m.isSticker && (m.text?.trim().isNotEmpty ?? false)) m,
  ];

  bool get _canDeleteSelected {
    final selected = _selectedMessages();
    return selected.isNotEmpty &&
        selected.every((m) => m.isOutgoing && m.canStillDelete);
  }

  void _forwardSelected() {
    final selected = _selectedMessages();
    if (selected.isEmpty) return;
    _openForwardTarget(selected);
  }

  Future<void> _copySelected() async {
    final texts = [
      for (final m in _selectedTextMessages())
        HtmlTextUtils.toMultilineText(m.text!),
    ].where((t) => t.isNotEmpty).toList();
    if (texts.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: texts.join('\n\n')));
    AppHaptics.light();
    if (!mounted) return;
    _clearSelection();
    _showSnack(texts.length > 1 ? 'Тексты скопированы' : 'Текст скопирован');
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedMessages();
    if (selected.isEmpty) return;
    final n = selected.length;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          n > 1
              ? 'Удалить $n ${ruPlural(n, 'сообщение', 'сообщения', 'сообщений')}?'
              : 'Удалить сообщение?',
        ),
        content: Text(
          n > 1
              ? 'Сообщения будут удалены безвозвратно.'
              : 'Сообщение будет удалено безвозвратно.',
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
    if (ok != true || !mounted) return;

    var failed = 0;
    for (final m in selected) {
      if (!await _service.deleteMessage(widget.chat.id, m.id)) failed++;
    }
    if (!mounted) return;
    _clearSelection();
    _showSnack(
      failed == 0
          ? (n > 1 ? 'Сообщения удалены' : 'Сообщение удалено')
          : (_service.lastActionError ??
                'Не удалось удалить $failed '
                    '${ruPlural(failed, 'сообщение', 'сообщения', 'сообщений')}'),
    );
  }

  Future<void> _openAttachMenu() async {
    if (_sendingAttachment) return;
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'gallery'),
            child: const Text('Фото из галереи'),
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

    final picked = <XFile>[];
    try {
      if (choice == 'gallery') {
        picked.addAll(
          await _picker.pickMultiImage(
            maxWidth: 1600,
            imageQuality: 88,
            limit: _maxAttachmentsPerMessage,
          ),
        );
      } else if (choice == 'video') {
        final x = await _picker.pickVideo(source: ImageSource.gallery);
        if (x != null) picked.add(x);
      } else if (choice == 'camera') {
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 88,
        );
        if (x != null) picked.add(x);
      } else if (choice == 'file') {
        // Без withData: файл читается с диска только после проверки
        // размера, а не целиком в память ещё в пикере.
        final r = await FilePicker.platform.pickFiles(withData: kIsWeb);
        final f = r?.files.singleOrNull;
        if (f != null) {
          final path = f.path;
          final data = f.bytes;
          if (path != null && !kIsWeb) {
            picked.add(XFile(path, name: f.name, length: f.size));
          } else if (data != null) {
            picked.add(XFile.fromData(data, name: f.name, length: f.size));
          }
        }
      }
    } catch (e) {
      debugPrint('attach: pick failed: $e');
      if (!mounted) return;
      _showSnack('Не удалось выбрать файл');
      return;
    }
    if (picked.isEmpty) return;

    // Размер — до чтения в память: пятиминутное видео весит сотни МБ,
    // и узнавать о лимите после долгой загрузки обидно.
    final tooBig = <String>[];
    for (final x in picked) {
      if (await x.length() > ChatFile.maxSizeBytes) tooBig.add(x.name);
    }
    if (tooBig.isNotEmpty) {
      if (!mounted) return;
      _showSnack(
        tooBig.length == 1 && picked.length == 1
            ? 'Файл больше 10 МБ — такой в чат не отправить'
            : 'Больше 10 МБ: ${tooBig.join(', ')}',
      );
      return;
    }

    setState(() => _sendingAttachment = true);
    _scrollToBottom();
    try {
      final files = <({List<int> bytes, String name})>[];
      for (final x in picked) {
        files.add((bytes: await x.readAsBytes(), name: x.name));
      }
      await _service.sendMedia(
        widget.chat.id,
        files: files,
        replyTo: _replyingTo,
      );
      if (_replyingTo != null && mounted) setState(() => _replyingTo = null);
    } catch (e) {
      debugPrint('attach: send failed: $e');
      if (!mounted) return;
      _showSnack(e is ApiException ? e.message : 'Не удалось отправить файл');
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
    if (_editingMessage == null) _draftBeforeEdit = _textCtrl.text;
    setState(() {
      _replyingTo = null;
      _editingMessage = m;
      // Сообщения с портала приходят HTML-ем — в поле ввода только текст.
      _textCtrl.text = HtmlTextUtils.toMultilineText(m.text ?? '');
      _textCtrl.selection = TextSelection.collapsed(
        offset: _textCtrl.text.length,
      );
    });
    _focus.requestFocus();
  }

  void _cancelEdit() => setState(_finishEdit);

  void _finishEdit() {
    _editingMessage = null;
    _textCtrl.text = _draftBeforeEdit;
    _textCtrl.selection = TextSelection.collapsed(
      offset: _draftBeforeEdit.length,
    );
    _draftBeforeEdit = '';
  }

  Future<void> _saveEdit() async {
    final m = _editingMessage;
    if (m == null) return;
    final newText = _textCtrl.text.trim();
    if (newText.isEmpty) return;

    final success = await _service.updateMessage(widget.chat.id, m.id, newText);
    if (!mounted) return;
    if (success) {
      setState(_finishEdit);
    } else {
      _showSnack(_service.lastActionError ?? 'Не удалось обновить сообщение');
    }
  }

  Future<void> _copyMessage(ChatMessage m) async {
    final text = HtmlTextUtils.toMultilineText(m.text ?? '');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    AppHaptics.light();
    if (mounted) _showSnack('Текст скопирован');
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
    } catch (e, st) {
      CrashReportingService.recordNonFatal(e, st, reason: 'chat_file_download');
      if (!mounted) return;
      _showSnack('Не удалось скачать файл');
    }
  }

  void _openChatImages(ChatMessage m, List<ChatFile> images, int index) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => MediaViewer(
          items: [
            for (final file in images)
              m.copyWith(
                attachmentKind: ChatAttachmentKind.image,
                remoteMediaUrl: ChatRoutes.fileUrl(file.id),
                fileName: file.originalName,
                files: [file],
              ),
          ],
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  Future<void> _jumpToMessage(String messageId) async {
    if (_jumpingToPinned) return;
    final chatId = widget.chat.id;
    var loaded = _service.messagesFor(chatId).any((m) => m.id == messageId);
    if (!loaded) {
      setState(() => _jumpingToPinned = true);
      try {
        loaded = await _service.ensureMessageLoaded(chatId, messageId);
      } catch (e, st) {
        CrashReportingService.recordNonFatal(e, st, reason: 'chat_jump_load');
      } finally {
        if (mounted) setState(() => _jumpingToPinned = false);
      }
      if (!mounted) return;
      if (!loaded) {
        _showSnack('Не удалось найти сообщение в истории');
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final ok = await _scrollToMessage(messageId);
    if (!ok && mounted) _showSnack('Не удалось перейти к сообщению');
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
      child: _GlassCapsule(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.pin_fill,
              size: 16,
              color: CupertinoColors.label.resolveFrom(context),
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
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
            if (_jumpingToPinned)
              const CupertinoActivityIndicator(radius: 8)
            else
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

/// Сколько фото из галереи уходит одним сообщением.
const int _maxAttachmentsPerMessage = 10;

/// Насколько увести палец влево, чтобы отменить запись голосового.
const double _voiceCancelDistance = 110;
const double _voiceLockDistance = 80;

/// Лимиты `POST /chat/messages/forward` (в Node — те же 100 и 20).
const int _maxForwardMessages = 100;
const int _maxForwardChats = 20;

enum _MsgAction { reply, copy, forward, select, edit, delete, pin }

/// Реакции пока только локальные — собеседник их не видит и они пропадают
/// с экрана, поэтому выключены до API на бэкенде (см. docs/BACKEND_CHAT_FIXES.md).
const bool _kReactionsEnabled = false;

/// Фиксированный набор быстрых реакций, как в iMessage/Telegram.
const List<String> _kQuickReactions = ['❤️', '👍', '👎', '😂', '‼️', '❓'];

/// Полоска быстрых реакций над пузырём в меню долгого нажатия.
class _ReactionsBar extends StatelessWidget {
  const _ReactionsBar({required this.active, required this.onReact});

  final List<String> active;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return AppGlass(
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in _kQuickReactions)
              GestureDetector(
                onTap: () => onReact(emoji),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: active.contains(emoji)
                        ? CupertinoColors.tertiarySystemFill.resolveFrom(
                            context,
                          )
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Лист «Переслать в…»: можно отметить несколько чатов.
class _ForwardTargetSheet extends StatefulWidget {
  const _ForwardTargetSheet({required this.chats});

  final List<Chat> chats;

  @override
  State<_ForwardTargetSheet> createState() => _ForwardTargetSheetState();
}

class _ForwardTargetSheetState extends State<_ForwardTargetSheet> {
  final List<String> _picked = [];

  void _toggle(String id) {
    if (!_picked.contains(id) && _picked.length >= _maxForwardChats) {
      AppHaptics.medium();
      return;
    }
    AppHaptics.selection();
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                _picked.isEmpty
                    ? 'Переслать в…'
                    : 'Выбрано чатов: ${_picked.length}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: widget.chats.length,
                itemBuilder: (context, i) {
                  final chat = widget.chats[i];
                  return _ForwardTargetTile(
                    chat: chat,
                    selected: _picked.contains(chat.id),
                    onTap: () => _toggle(chat.id),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: CupertinoButton.filled(
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.pop(context, List.of(_picked)),
                child: const Text('Переслать'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Круглая галочка выбора, как в «Сообщениях».
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Icon(
      selected
          ? CupertinoIcons.checkmark_alt_circle_fill
          : CupertinoIcons.circle,
      size: 24,
      color: selected
          ? AppColors.outgoingBubble
          : CupertinoColors.tertiaryLabel.resolveFrom(context),
    );
  }
}

/// Панель действий над выбранными сообщениями вместо поля ввода.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.onForward, this.onCopy, this.onDelete});

  final VoidCallback onForward;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    Widget action(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool destructive = false,
    }) {
      final color = onTap == null
          ? CupertinoColors.tertiaryLabel.resolveFrom(context)
          : destructive
          ? CupertinoColors.destructiveRed.resolveFrom(context)
          : CupertinoColors.label.resolveFrom(context);
      return Expanded(
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: const Size.square(44),
          onPressed: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: AppGlass(
          borderRadius: BorderRadius.circular(22),
          shadows: AppGlass.controlShadow,
          child: Row(
            children: [
              action(
                CupertinoIcons.arrowshape_turn_up_right,
                'Переслать',
                onForward,
              ),
              action(CupertinoIcons.doc_on_doc, 'Копировать', onCopy),
              action(
                CupertinoIcons.trash,
                'Удалить',
                onDelete,
                destructive: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForwardTargetTile extends StatelessWidget {
  const _ForwardTargetTile({
    required this.chat,
    required this.selected,
    required this.onTap,
  });

  final Chat chat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.groupedSurface.resolveFrom(context),
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
              _SelectionCheck(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плавающая стеклянная плашка над/под лентой: закреп, поиск,
/// ответ и правка — в одном стиле с полем ввода.
class _GlassCapsule extends StatelessWidget {
  const _GlassCapsule({
    required this.margin,
    required this.padding,
    required this.child,
  });

  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: AppGlass(
        borderRadius: BorderRadius.circular(18),
        shadows: AppGlass.controlShadow,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Сообщает высоту ребёнка после каждой раскладки — по ней лента
/// отступает от плавающих панелей сверху и снизу.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onChange, required super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onChange);

  ValueChanged<double> onChange;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _lastHeight) return;
    _lastHeight = height;
    // setState во время раскладки нельзя — отдаём высоту после кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(height));
  }
}

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.ref, required this.onClose});

  final MessageReference ref;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _GlassCapsule(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: CupertinoColors.label.resolveFrom(context),
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
                  style: TextStyle(
                    color: CupertinoColors.label.resolveFrom(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  ref.textPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
    );
  }
}

class _EditBanner extends StatelessWidget {
  const _EditBanner({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _GlassCapsule(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.pencil,
            size: 18,
            color: CupertinoColors.label.resolveFrom(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Изменить сообщение',
                  style: TextStyle(
                    color: CupertinoColors.label.resolveFrom(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
    );
  }
}

/// Имя собеседника в стеклянной капсуле: отделяет шапку от ленты
/// сообщений и подсказывает, что по нажатию откроются настройки чата.
class _ChatTitleCapsule extends StatelessWidget {
  const _ChatTitleCapsule({required this.chat, required this.onTap});

  final Chat chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final online = chat.peerIsOnline;
    final (String? status, Color statusColor) = chat.isGroup
        ? (
            chat.members.isEmpty
                ? null
                : '${chat.members.length} ${ruPlural(chat.members.length, 'участник', 'участника', 'участников')}',
            secondary,
          )
        : switch (online) {
            true => ('в сети', AppColors.primary),
            false => ('не в сети', secondary),
            null => (null, secondary),
          };

    return GestureDetector(
      onTap: onTap,
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatAvatar(chat: chat, radius: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if (status != null)
                      Text(
                        status,
                        maxLines: 1,
                        style: TextStyle(fontSize: 12, color: statusColor),
                      ),
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

/// Мягкое затухание ленты у края экрана — как scroll edge effect в iOS 26:
/// под шапкой и полем ввода сообщения растворяются в фоне.
/// Круглая стеклянная кнопка «к последним сообщениям».
class _ScrollDownButton extends StatelessWidget {
  const _ScrollDownButton({required this.onTap, this.unseen = 0});

  final VoidCallback onTap;

  /// Новые входящие ниже экрана; 0 — бейдж скрыт.
  final int unseen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          AppGlass(
            borderRadius: BorderRadius.circular(20),
            shadows: AppGlass.controlShadow,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                CupertinoIcons.chevron_down,
                size: 20,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
          if (unseen > 0)
            Positioned(
              top: -9,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.outgoingBubble,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unseen > 99 ? '99+' : '$unseen',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Участники группы под набранным `@` — как в Telegram.
class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({required this.members, required this.onSelect});

  final List<ChatMemberSummary> members;
  final ValueChanged<ChatMemberSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
      child: AppGlass(
        borderRadius: BorderRadius.circular(18),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in members)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  onPressed: () => onSelect(m),
                  child: Row(
                    children: [
                      MemberAvatar(
                        displayName: m.displayName,
                        avatarUrl: m.avatarUrl,
                        radius: 14,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          m.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ),
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

/// «Новые сообщения» над первым непрочитанным при входе в чат.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AppGlass(
        borderRadius: BorderRadius.circular(12),
        shadows: null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            'Новые сообщения',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade.top({required this.height}) : fromTop = true;
  const _EdgeFade.bottom({required this.height}) : fromTop = false;

  final double height;
  final bool fromTop;

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.groupedBackground.resolveFrom(context);
    return Positioned(
      top: fromTop ? 0 : null,
      bottom: fromTop ? null : 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [bg, bg.withValues(alpha: 0.85), bg.withValues(alpha: 0)],
              stops: const [0, 0.6, 1],
            ),
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
    this.onStickers,
    this.isEditing = false,
    this.isSendingAttachment = false,
    this.onVoiceStart,
    this.onVoiceMove,
    this.onVoiceEnd,
    this.onVoiceSend,
    this.onVoiceCancel,
    this.onVoiceStop,
    this.voiceDraft,
    this.onVoiceDraftSend,
    this.onVoiceDraftDelete,
    this.voiceDrag = Offset.zero,
    this.voiceLocked = false,
  });

  final TextEditingController textCtrl;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  /// Открывает панель стикеров; `null` — кнопка скрыта (например, при правке).
  final VoidCallback? onStickers;
  final bool isEditing;
  final bool isSendingAttachment;

  /// Запись голосового: нажали микрофон / ведут палец / отпустили.
  /// `null` — микрофон скрыт (например, при правке).
  final VoidCallback? onVoiceStart;
  final ValueChanged<Offset>? onVoiceMove;
  final VoidCallback? onVoiceEnd;

  /// Запись на замке: отправить / отменить кнопками.
  final VoidCallback? onVoiceSend;
  final VoidCallback? onVoiceCancel;

  /// «Стоп» на замке — к прослушиванию перед отправкой.
  final VoidCallback? onVoiceStop;

  /// Записанное голосовое на прослушивании; `null` — его нет.
  final ChatVoiceRecording? voiceDraft;
  final VoidCallback? onVoiceDraftSend;
  final VoidCallback? onVoiceDraftDelete;

  /// Куда ушёл палец: влево — к отмене, вверх — к замку.
  final Offset voiceDrag;
  final bool voiceLocked;

  @override
  Widget build(BuildContext context) {
    final iconColor = CupertinoColors.label.resolveFrom(context);
    return ValueListenableBuilder<Duration?>(
      valueListenable: ChatVoiceRecorder.instance.elapsed,
      builder: (context, recorded, _) =>
          _buildRow(context, iconColor, recorded),
    );
  }

  Widget _buildRow(BuildContext context, Color iconColor, Duration? recorded) {
    // Плавающие стеклянные капсулы над фоном чата, как в iOS 26.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (recorded != null)
              Expanded(
                child: _VoiceRecordingIndicator(
                  elapsed: recorded,
                  dragDx: voiceDrag.dx,
                  onCancel: voiceLocked ? onVoiceCancel : null,
                  onStop: voiceLocked ? onVoiceStop : null,
                ),
              )
            else if (voiceDraft != null) ...[
              AppGlass(
                borderRadius: BorderRadius.circular(20),
                shadows: AppGlass.controlShadow,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(40),
                  onPressed: onVoiceDraftDelete,
                  child: Icon(
                    CupertinoIcons.trash,
                    size: 20,
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppGlass(
                  borderRadius: BorderRadius.circular(20),
                  shadows: AppGlass.controlShadow,
                  child: SizedBox(
                    height: 40,
                    child: ChatVoiceDraft(
                      path: voiceDraft!.file.path,
                      duration: voiceDraft!.duration,
                      levels: voiceDraft!.levels,
                    ),
                  ),
                ),
              ),
            ] else ...[
              AppGlass(
                borderRadius: BorderRadius.circular(20),
                shadows: AppGlass.controlShadow,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(40),
                  onPressed: isSendingAttachment ? null : onAttach,
                  child: isSendingAttachment
                      ? const CupertinoActivityIndicator(radius: 9)
                      : Icon(
                          CupertinoIcons.paperclip,
                          size: 21,
                          color: iconColor,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppGlass(
                  borderRadius: BorderRadius.circular(20),
                  shadows: AppGlass.controlShadow,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
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
                        vertical: 10,
                      ),
                      onSubmitted: (_) => onSend(),
                      suffix: onStickers == null
                          ? null
                          : CupertinoButton(
                              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                              minimumSize: Size.zero,
                              onPressed: onStickers,
                              child: Icon(
                                CupertinoIcons.smiley,
                                size: 22,
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: textCtrl,
              builder: (context, _) {
                final hasText = textCtrl.text.trim().isNotEmpty;
                if (voiceDraft != null) {
                  return GestureDetector(
                    onTap: isSendingAttachment ? null : onVoiceDraftSend,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.outgoingBubble,
                      ),
                      child: const Icon(
                        CupertinoIcons.arrow_up,
                        size: 20,
                        color: CupertinoColors.white,
                      ),
                    ),
                  );
                }
                if ((!hasText || recorded != null) && onVoiceStart != null) {
                  return _VoiceRecordButton(
                    recording: recorded != null,
                    locked: voiceLocked,
                    dragDy: voiceDrag.dy,
                    onStart: onVoiceStart!,
                    onMove: onVoiceMove,
                    onEnd: onVoiceEnd,
                    onSend: onVoiceSend,
                  );
                }
                return GestureDetector(
                  onTap: hasText ? onSend : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasText
                          ? AppColors.outgoingBubble
                          : CupertinoColors.tertiarySystemFill.resolveFrom(
                              context,
                            ),
                    ),
                    child: Icon(
                      isEditing
                          ? CupertinoIcons.checkmark
                          : CupertinoIcons.arrow_up,
                      size: 20,
                      color: hasText
                          ? CupertinoColors.white
                          : CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Микрофон: удерживать — запись, отпустить — отправка, влево — отмена,
/// вверх на замок — запись без пальца (тогда кнопка отправляет).
class _VoiceRecordButton extends StatefulWidget {
  const _VoiceRecordButton({
    required this.recording,
    required this.locked,
    required this.dragDy,
    required this.onStart,
    this.onMove,
    this.onEnd,
    this.onSend,
  });

  final bool recording;
  final bool locked;
  final double dragDy;
  final VoidCallback onStart;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onEnd;
  final VoidCallback? onSend;

  @override
  State<_VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<_VoiceRecordButton> {
  /// Палец, который держит запись. На сырых событиях, а не через
  /// LongPress: распознаватель мог проиграть арену или отвалиться от
  /// лишнего сдвига, и запись не начиналась с первого раза.
  int? _pointer;
  Offset _origin = Offset.zero;

  /// Касание началось уже на замке — по отпусканию это «Отправить».
  bool _sendTap = false;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _origin = e.position;
    _sendTap = widget.locked;
    if (!_sendTap) widget.onStart();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _sendTap) return;
    widget.onMove?.call(e.position - _origin);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_sendTap) {
      _sendTap = false;
      if (e is PointerUpEvent && widget.locked) widget.onSend?.call();
      return;
    }
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.recording;
    final locked = widget.locked;
    final button = AnimatedScale(
      scale: recording && !locked ? 1.35 : 1,
      duration: const Duration(milliseconds: 160),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording && !locked
              ? CupertinoColors.systemRed.resolveFrom(context)
              : AppColors.outgoingBubble,
        ),
        child: Icon(
          locked ? CupertinoIcons.arrow_up : CupertinoIcons.mic_fill,
          size: 20,
          color: CupertinoColors.white,
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: button,
        ),
        // Замок над микрофоном, пока палец держит запись.
        Positioned(
          bottom: 40 + 22,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: recording && !locked ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Transform.translate(
                offset: Offset(0, widget.dragDy * 0.5),
                child: _VoiceLockHint(
                  progress: (-widget.dragDy / _voiceLockDistance).clamp(0, 1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Капсула «замок + стрелка вверх», как в Telegram.
class _VoiceLockHint extends StatelessWidget {
  const _VoiceLockHint({required this.progress});

  /// 0 — палец на месте, 1 — дотянули до замка.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return AppGlass(
      borderRadius: BorderRadius.circular(18),
      shadows: AppGlass.controlShadow,
      child: SizedBox(
        width: 36,
        height: 64 - progress * 20,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              progress >= 1
                  ? CupertinoIcons.lock_fill
                  : CupertinoIcons.lock_open_fill,
              size: 18,
              color: Color.lerp(secondary, AppColors.outgoingBubble, progress),
            ),
            if (progress < 0.6) ...[
              const SizedBox(height: 6),
              Opacity(
                opacity: 1 - progress / 0.6,
                child: Icon(
                  CupertinoIcons.chevron_up,
                  size: 13,
                  color: secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Вместо поля ввода во время записи: точка, таймер и «‹ Отмена».
class _VoiceRecordingIndicator extends StatelessWidget {
  const _VoiceRecordingIndicator({
    required this.elapsed,
    required this.dragDx,
    this.onCancel,
    this.onStop,
  });

  final Duration elapsed;
  final double dragDx;

  /// Запись на замке — вместо подсказки свайпа кнопка «Отмена».
  final VoidCallback? onCancel;

  /// Запись на замке — остановить и прослушать.
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return AppGlass(
      borderRadius: BorderRadius.circular(20),
      shadows: AppGlass.controlShadow,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 14),
            ValueListenableBuilder<double>(
              valueListenable: ChatVoiceRecorder.instance.level,
              builder: (context, level, _) => Container(
                width: 10 + level * 4,
                height: 10 + level * 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              ChatVoiceMessage.formatDuration(elapsed),
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.label.resolveFrom(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (onCancel != null)
              Expanded(
                child: Center(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 40),
                    onPressed: onCancel,
                    child: Text(
                      'Отмена',
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Transform.translate(
                  offset: Offset(dragDx * 0.6, 0),
                  child: Opacity(
                    opacity: (1 + dragDx / _voiceCancelDistance).clamp(0.2, 1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.chevron_left,
                          size: 14,
                          color: secondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Влево — отмена',
                          style: TextStyle(fontSize: 14, color: secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (onStop != null)
              CupertinoButton(
                padding: const EdgeInsets.only(right: 10),
                minimumSize: const Size(40, 40),
                onPressed: onStop,
                child: Icon(
                  CupertinoIcons.stop_circle_fill,
                  size: 28,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
              ),
          ],
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
    required this.onOpenImages,
    this.showAuthorHeader = false,
    this.showAvatarInHeader = false,
    this.showTime = true,
    this.highlighted = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.onOpenAuthor,
    this.mentions = const {},
  });

  final ChatMessage m;

  /// Участники группы для подсветки `@имя`; тап — личный чат.
  final Map<String, int> mentions;

  /// Тап по имени в «Переслано от …» — личный чат с автором оригинала.
  final ValueChanged<int>? onOpenAuthor;
  final void Function(_MsgAction) onLongMenu;
  final void Function(String emoji) onReact;
  final Future<void> Function(ChatFile file) onOpenFile;
  final void Function(List<ChatFile> images, int index) onOpenImages;
  final bool showAuthorHeader;
  final bool showAvatarInHeader;
  final bool showTime;
  final bool highlighted;

  /// Режим выбора: тап по строке переключает [selected], а меню, свайп
  /// и открытие вложений выключены.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  /// Только картинки, без текста/цитаты/пересылки — такой пузырь рисуется
  /// почти без отступов, чтобы фото заполняло его целиком.
  bool get _isMediaOnly {
    if (m.forwardOf != null || m.replyTo != null || m.isPinned) return false;
    if (m.text != null && m.text!.trim().isNotEmpty) return false;
    if (m.files.isNotEmpty) return m.files.every((f) => f.isImage);
    return m.attachmentKind == ChatAttachmentKind.image &&
        ((m.localMediaPath != null && !kIsWeb) || m.remoteMediaUrl != null);
  }

  List<Widget> _buildAttachments(BuildContext context, Color onBubble) {
    if (m.isSticker) {
      return [_ChatSticker(id: m.stickerId!)];
    }
    if (m.isCall) {
      return [
        _CallRecordContent(
          call: m.call!,
          isOutgoing: m.isOutgoing,
          onBubble: onBubble,
        ),
      ];
    }
    final radius = _isMediaOnly ? 15.0 : 10.0;
    if (m.files.isNotEmpty) {
      final images = m.files.where((f) => f.isImage).toList();
      return [
        for (var i = 0; i < m.files.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          if (m.files[i].voiceNote case final note?)
            ChatVoiceMessage(
              file: m.files[i],
              note: note,
              isOutgoing: m.isOutgoing,
              onBubble: onBubble,
            )
          else if (m.files[i].isImage)
            _ChatImage(
              url: ChatRoutes.fileUrl(m.files[i].id),
              radius: radius,
              onTap: () => onOpenImages(images, images.indexOf(m.files[i])),
            )
          else
            _ChatFileCard(
              file: m.files[i],
              name: m.files[i].originalName,
              subtitle: m.files[i].sizeLabel,
              isVideo: m.files[i].isVideo,
              onBubble: onBubble,
              onTap: () => onOpenFile(m.files[i]),
            ),
        ],
      ];
    }

    if (m.attachmentKind == ChatAttachmentKind.image &&
        m.localMediaPath != null &&
        !kIsWeb) {
      return [_ChatImage(localPath: m.localMediaPath, radius: radius)];
    }
    if (m.attachmentKind == ChatAttachmentKind.image &&
        m.remoteMediaUrl != null) {
      return [_ChatImage(url: m.remoteMediaUrl, radius: radius)];
    }
    if (m.attachmentKind == ChatAttachmentKind.image && kIsWeb) {
      return [
        const Padding(padding: EdgeInsets.all(8), child: Text('(изображение)')),
      ];
    }
    if (m.attachmentKind == ChatAttachmentKind.video ||
        m.attachmentKind == ChatAttachmentKind.file) {
      final isVideo = m.attachmentKind == ChatAttachmentKind.video;
      return [
        _ChatFileCard(
          name: m.fileName ?? (isVideo ? 'Видео' : 'Файл'),
          isVideo: isVideo,
          onBubble: onBubble,
        ),
      ];
    }
    return const [];
  }

  Widget _wrapHighlight(BuildContext context, Widget child) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      color: highlighted
          ? CupertinoColors.systemYellow
                .resolveFrom(context)
                .withValues(alpha: 0.20)
          : Colors.transparent,
      child: child,
    );
  }

  /// [context] — контекст пузыря (или значка реакций): от него меню
  /// берёт прямоугольник, а [preview] рисуется поверх размытого фона.
  Future<void> _showActions(BuildContext context, {Widget? preview}) async {
    if (m.isSending) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final canEdit =
        m.isOutgoing &&
        m.attachmentKind == ChatAttachmentKind.none &&
        (m.text?.trim().isNotEmpty ?? false) &&
        m.canStillEdit;
    final canDelete = m.isOutgoing && m.canStillDelete;

    await showMessageContextMenu(
      context: context,
      anchor: anchor,
      preview: preview,
      alignEnd: m.isOutgoing,
      reactions: !_kReactionsEnabled
          ? null
          : _ReactionsBar(
              active: m.reactions,
              onReact: (emoji) {
                Navigator.of(context, rootNavigator: true).pop();
                onReact(emoji);
              },
            ),
      items: [
        MessageMenuItem(
          label: 'Ответить',
          icon: CupertinoIcons.arrowshape_turn_up_left,
          onTap: () => onLongMenu(_MsgAction.reply),
        ),
        if (!m.isSticker && (m.text?.trim().isNotEmpty ?? false))
          MessageMenuItem(
            label: 'Копировать',
            icon: CupertinoIcons.doc_on_doc,
            onTap: () => onLongMenu(_MsgAction.copy),
          ),
        if (!m.isCall)
          MessageMenuItem(
            label: 'Переслать',
            icon: CupertinoIcons.arrowshape_turn_up_right,
            onTap: () => onLongMenu(_MsgAction.forward),
          ),
        if (m.canForward)
          MessageMenuItem(
            label: 'Выбрать',
            icon: CupertinoIcons.checkmark_circle,
            onTap: () => onLongMenu(_MsgAction.select),
          ),
        if (!m.isSystem)
          MessageMenuItem(
            label: m.isPinned ? 'Открепить' : 'Закрепить',
            icon: m.isPinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
            onTap: () => onLongMenu(_MsgAction.pin),
          ),
        if (canEdit)
          MessageMenuItem(
            label: 'Редактировать',
            icon: CupertinoIcons.pencil,
            onTap: () => onLongMenu(_MsgAction.edit),
          ),
        if (canDelete)
          MessageMenuItem(
            label: 'Удалить',
            icon: CupertinoIcons.trash,
            isDestructive: true,
            onTap: () => onLongMenu(_MsgAction.delete),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!selectionMode) return content;
    final selectable = m.canForward;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selectable ? onToggleSelect : null,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: selectable ? _SelectionCheck(selected: selected) : null,
          ),
          Expanded(child: IgnorePointer(child: content)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
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
              color: AppColors.groupedSurface.resolveFrom(context),
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
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
        ? AppColors.outgoingBubble
        : AppColors.groupedSurface.resolveFrom(context);
    // Стикер рисуется без пузыря — цитата и подписи над ним на фоне чата.
    final onBubble = m.isOutgoing && !m.isSticker
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);
    final attachments = _buildAttachments(context, onBubble);
    // Превью только у обычного текста: у файлов и стикеров своя карточка.
    final text = m.text;
    final linkPreviewUri = attachments.isEmpty && text != null && !m.isDeleted
        ? ChatLinkPreview.firstUrlIn(text)
        : null;
    final hasAboveText =
        m.forwardOf != null ||
        m.replyTo != null ||
        m.isPinned ||
        attachments.isNotEmpty;

    // Тот же пузырь показывается поверх размытого фона в меню долгого нажатия.
    final bubbleBox = Container(
      width: m.isSticker ? _ChatSticker.bubbleSize : null,
      padding: m.isSticker
          ? EdgeInsets.zero
          : _isMediaOnly
          ? const EdgeInsets.all(3)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: m.isSticker
          ? null
          : BoxDecoration(
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
              _ForwardBlock(
                ref: m.forwardOf!,
                onBubble: onBubble,
                onAuthorTap: onOpenAuthor,
              ),
            if (m.replyTo != null)
              _ReplyBlock(
                ref: m.replyTo!,
                isOutgoing: m.isOutgoing && !m.isSticker,
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
                        color: onBubble.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ...attachments,
            if (m.text != null && m.text!.trim().isNotEmpty)
              Padding(
                // Отступ только под цитатой/вложением —
                // иначе над текстом поле больше, чем под ним.
                padding: EdgeInsets.only(top: hasAboveText ? 4 : 0),
                child: ChatMessageText(
                  text: m.text!,
                  color: onBubble,
                  mentions: mentions,
                  onMentionTap: onOpenAuthor,
                ),
              ),
            if (linkPreviewUri != null)
              ChatLinkPreview(uri: linkPreviewUri, onBubble: onBubble),
          ],
        ),
      ),
    );

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
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
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
                    onReply: () {
                      if (m.isSending) return;
                      onLongMenu(_MsgAction.reply);
                    },
                    child: Builder(
                      builder: (bubbleContext) => GestureDetector(
                        onLongPress: () {
                          AppHaptics.medium();
                          _showActions(bubbleContext, preview: bubbleBox);
                        },
                        child: bubbleBox,
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
                            color: AppColors.groupedSurface.resolveFrom(
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
                      m.isSending
                          ? Icon(
                              CupertinoIcons.clock,
                              size: 12,
                              color: CupertinoColors.tertiaryLabel.resolveFrom(
                                context,
                              ),
                            )
                          : ReadReceipt(read: m.readByRecipients),
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
      AppHaptics.medium();
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
                      ? CupertinoColors.label.resolveFrom(context)
                      : CupertinoColors.systemGrey.resolveFrom(context),
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

class _ForwardBlock extends StatelessWidget {
  const _ForwardBlock({
    required this.ref,
    required this.onBubble,
    this.onAuthorTap,
  });

  final MessageReference ref;
  final Color onBubble;
  final ValueChanged<int>? onAuthorTap;

  String _authorName() {
    final id = ref.authorId;
    if (id == null) return ref.authorName;
    final known = ChatUserNames.instance.nameFor(id);
    if (known != null) return known;
    ChatUserNames.instance.ensure(id);
    return ref.authorName;
  }

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
            left: BorderSide(color: onBubble.withValues(alpha: 0.5), width: 3),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: ChatUserNames.instance,
              builder: (context, _) {
                final style = TextStyle(
                  fontSize: 11,
                  color: onBubble.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                );
                if (ref.sourceChatTitle != null) {
                  return Text(
                    'Переслано из «${ref.sourceChatTitle!}»',
                    style: style,
                  );
                }
                final authorId = ref.authorId;
                final label = Text.rich(
                  TextSpan(
                    text: 'Переслано от ',
                    children: [
                      TextSpan(
                        text: _authorName(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  style: style,
                );
                if (authorId == null || onAuthorTap == null) return label;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onAuthorTap!(authorId),
                  child: label,
                );
              },
            ),
            if (ref.textPreview.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                ref.textPreview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
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
    final textColor = isOutgoing
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);
    final accent = textColor;
    final fill = textColor.withValues(alpha: isOutgoing ? 0.16 : 0.06);

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

/// Стикер из набора портала. Квадрат фиксированного размера, чтобы лента
/// не прыгала, пока картинка грузится. Пока картинок нет
/// ([ChatStickers.imagesAvailable]) или код неизвестен — заглушка.
class _ChatSticker extends StatelessWidget {
  const _ChatSticker({required this.id});

  final String id;

  static const double bubbleSize = 150;

  Widget _placeholder(BuildContext context) {
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.smiley, size: 44, color: muted),
            const SizedBox(height: 6),
            Text(
              ChatMapper.stickerSnippet,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatStickers.imagesAvailable || !ChatStickers.isValidId(id)) {
      return _placeholder(context);
    }
    final image = CachedNetworkImage(
      imageUrl: ChatStickers.url(id),
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (context, _) =>
          const Center(child: CupertinoActivityIndicator()),
      errorWidget: (context, _, _) => Center(
        child: Icon(
          CupertinoIcons.smiley,
          size: 32,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      ),
    );
    return AspectRatio(aspectRatio: 1, child: image);
  }
}

/// Содержимое пузыря сообщения-звонка: иконка, «Исходящий/Пропущенный
/// звонок» и длительность.
class _CallRecordContent extends StatelessWidget {
  const _CallRecordContent({
    required this.call,
    required this.isOutgoing,
    required this.onBubble,
  });

  final ChatCallRecord call;
  final bool isOutgoing;
  final Color onBubble;

  @override
  Widget build(BuildContext context) {
    final failed = call.isUnsuccessful;
    final iconColor = failed && !isOutgoing
        ? CupertinoColors.systemRed.resolveFrom(context)
        : onBubble;
    final subtitle = call.subtitle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isOutgoing
              ? CupertinoIcons.phone_arrow_up_right
              : failed
              ? CupertinoIcons.phone_down
              : CupertinoIcons.phone_arrow_down_left,
          size: 22,
          color: iconColor,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                call.title(isOutgoing: isOutgoing),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: onBubble,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: onBubble.withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Фото в пузыре: держит размер, пока грузится (а не полоску в 16 px),
/// и не растягивается выше [_maxHeight] у вертикальных снимков.
class _ChatImage extends StatelessWidget {
  const _ChatImage({this.url, this.localPath, required this.radius, this.onTap})
    : assert(url != null || localPath != null);

  final String? url;
  final String? localPath;
  final double radius;
  final VoidCallback? onTap;

  static const double _width = 240;
  static const double _maxHeight = 320;
  static const double _placeholderHeight = 180;

  Widget _box(BuildContext context, Widget child) {
    return Container(
      width: _width,
      height: _placeholderHeight,
      color: CupertinoColors.systemFill.resolveFrom(context),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _error(BuildContext context) {
    final color = CupertinoColors.secondaryLabel.resolveFrom(context);
    return _box(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.photo, size: 28, color: color),
          const SizedBox(height: 6),
          Text(
            'Не удалось загрузить фото',
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (localPath != null && !kIsWeb) {
      image = Image.file(
        File(localPath!),
        width: _width,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _error(context),
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: url!.trim(),
        httpHeaders: ChatFileShare.imageHeaders(url),
        width: _width,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, _) =>
            _box(context, const CupertinoActivityIndicator()),
        errorWidget: (context, _, _) => _error(context),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _width,
            maxHeight: _maxHeight,
          ),
          child: image,
        ),
      ),
    );
  }
}

/// Документ/видео в пузыре: плашка с иконкой-расширением, именем и размером.
///
/// Если передан [file], скачивание идёт как в Telegram: стрелка «скачать»,
/// во время загрузки — кольцо прогресса с крестиком и «X из Y» под именем,
/// повторный тап останавливает. Скачанный файл открывается сразу из кэша.
class _ChatFileCard extends StatefulWidget {
  const _ChatFileCard({
    required this.name,
    required this.isVideo,
    required this.onBubble,
    this.file,
    this.subtitle,
    this.onTap,
  });

  final String name;
  final String? subtitle;
  final bool isVideo;
  final Color onBubble;
  final ChatFile? file;
  final Future<void> Function()? onTap;

  @override
  State<_ChatFileCard> createState() => _ChatFileCardState();
}

class _ChatFileCardState extends State<_ChatFileCard> {
  final _downloads = ChatFileDownloads.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkCached();
  }

  @override
  void didUpdateWidget(covariant _ChatFileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file?.id != widget.file?.id) _checkCached();
  }

  void _checkCached() {
    final file = widget.file;
    if (file != null) unawaited(_downloads.checkCached(file));
  }

  String get _extension {
    final dot = widget.name.lastIndexOf('.');
    if (dot < 0 || dot == widget.name.length - 1) return '';
    final ext = widget.name.substring(dot + 1).toUpperCase();
    return ext.length > 5 ? '' : ext;
  }

  Future<void> _handleTap() async {
    final file = widget.file;
    if (file != null && _downloads.isDownloading(file.id)) {
      AppHaptics.selection();
      _downloads.cancel(file.id);
      return;
    }
    final onTap = widget.onTap;
    if (onTap == null || _busy) return;
    // С [file] ход загрузки рисует кольцо — свой индикатор не нужен.
    if (file == null) setState(() => _busy = true);
    try {
      await onTap();
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Widget _icon(bool downloaded) {
    final onBubble = widget.onBubble;
    if (_busy) return CupertinoActivityIndicator(color: onBubble, radius: 9);
    final IconData icon;
    if (widget.file != null && !downloaded) {
      icon = CupertinoIcons.arrow_down;
    } else if (widget.isVideo) {
      icon = CupertinoIcons.play_fill;
    } else {
      icon = CupertinoIcons.doc_text_fill;
    }
    return Icon(icon, size: 20, color: onBubble);
  }

  String _details(ChatFileDownloadProgress? progress) {
    final ext = _extension;
    if (progress != null) {
      final received = ChatFile.formatBytes(progress.received);
      final total = progress.total;
      return total == null
          ? received
          : '$received из ${ChatFile.formatBytes(total)}';
    }
    return [
      if (ext.isNotEmpty) ext,
      if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
        widget.subtitle!,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if (file == null) return _buildCard(context, null, true);
    final progress = _downloads.progressOf(file.id);
    return AnimatedBuilder(
      animation: Listenable.merge([progress, _downloads.downloaded]),
      builder: (context, _) => _buildCard(
        context,
        progress.value,
        _downloads.downloaded.value.contains(file.id),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ChatFileDownloadProgress? progress,
    bool downloaded,
  ) {
    final onBubble = widget.onBubble;
    final details = _details(progress);
    final file = widget.file;
    final iconCircle = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: onBubble.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: file == null
          ? _icon(downloaded)
          : ChatDownloadRing(
              fileId: file.id,
              color: onBubble,
              idle: _icon(downloaded),
            ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap == null ? null : _handleTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: onBubble.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconCircle,
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: onBubble,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: TextStyle(
                        fontSize: 12,
                        color: onBubble.withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Плашка с датой по центру ленты — отделяет сообщения разных дней.
class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label, this.onTap});

  final String label;

  /// Тап — выбрать дату и перейти к ней.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: AppGlass(
            borderRadius: BorderRadius.circular(12),
            shadows: null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
