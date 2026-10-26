import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        RefreshIndicator,
        ScaffoldMessenger,
        SnackBar,
        SnackBarAction,
        SnackBarClosedReason;

import '../config/app_theme.dart';
import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../services/mail_sync_notice_service.dart';
import '../services/mail_unread_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/app_loading.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/mail_glass.dart';
import '../widgets/swipe_actions_row.dart';
import 'compose_mail_screen.dart';
import 'mail_folders_screen.dart';
import 'mail_message_screen.dart';
import 'mail_screen.dart';
import '../services/haptics_service.dart';

class MailInboxScreen extends StatefulWidget {
  const MailInboxScreen({
    super.key,
    required this.connection,
    this.connections = const [],
    this.isTab = false,
  });

  final MailConnection connection;

  /// Экран — корень вкладки «Почта»: без кнопки «назад», а кнопку «Домой»
  /// прячет сама оболочка, пока вкладка активна.
  final bool isTab;

  /// Остальные подключённые ящики пользователя — чтобы показать
  /// переключатель в шапке. Если пуст или содержит только [connection],
  /// переключатель скрыт (переключаться не между чем).
  final List<MailConnection> connections;

  @override
  State<MailInboxScreen> createState() => _MailInboxScreenState();
}

class _MailInboxScreenState extends State<MailInboxScreen>
    with WidgetsBindingObserver {
  late MailConnection _connection = widget.connection;
  late List<MailConnection> _connections = widget.connections.isEmpty
      ? [widget.connection]
      : widget.connections;
  List<MailFolder> _folders = [];
  List<MailMessage> _messages = [];
  MailFolder? _selectedFolder;
  bool _isLoadingFolders = true;
  bool _isLoadingMessages = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = false;
  int _nextPage = 1;
  bool _usingServiceFallback = false;

  /// Подгрузка следующей страницы упала — автоматически больше не
  /// повторяем (раньше запрос уходил на каждое движение прокрутки),
  /// внизу списка кнопка «Повторить».
  bool _loadMoreFailed = false;
  final _scrollController = ScrollController();

  /// Результаты серверного поиска (`/mail/search`) по текущему ящику;
  /// `null` — поиск не запускался или упал, тогда фильтруем загруженное.
  List<MailMessage>? _searchResults;
  bool _isSearching = false;
  bool _searchHasMore = false;
  int _searchNextPage = 1;
  int _searchVersion = 0;
  Timer? _searchDebounce;

  /// Письма, удалённые свайпом, пока у пользователя есть «Вернуть»:
  /// скрыты из списка, на сервер запрос уходит после закрытия снекбара.
  final Set<int> _pendingDeleteIds = {};

  Timer? _refreshTimer;
  int _requestVersion = 0;

  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _swipeGroup = SwipeGroupController();
  bool _isEditing = false;
  final Set<int> _selectedIds = {};
  bool _isBulkActing = false;

  /// Поиск: совпадения среди загруженных писем (в т.ч. по тексту) плюс
  /// найденное сервером во всём ящике — раньше искали только по первым
  /// загруженным страницам.
  List<MailMessage> get _visibleMessages {
    final query = _searchQuery.trim().toLowerCase();
    final visible = _messages.where((m) => !_pendingDeleteIds.contains(m.id));
    if (query.isEmpty) return visible.toList();
    final local = visible.where((m) {
      return m.subject.toLowerCase().contains(query) ||
          m.from.toLowerCase().contains(query) ||
          m.previewBody.toLowerCase().contains(query);
    }).toList();
    final localIds = local.map((m) => m.id).toSet();
    return [
      ...local,
      ...?_searchResults?.where(
        (m) => !localIds.contains(m.id) && !_pendingDeleteIds.contains(m.id),
      ),
    ];
  }

  bool get _isSearchMode => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MailUnreadService.instance.mailChanges.addListener(_refreshVisible);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshVisible(),
    );
    _loadFolders();
    MailSyncNoticeService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Ящик подключили недавно — сервер ещё забирает письма из IMAP.
  bool get _isInitialSync =>
      MailSyncNoticeService.instance.isSyncing(_connection.email);

  Widget _buildSyncNotice(BuildContext context) {
    final blue = CupertinoColors.systemBlue.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: AppGlass(
        borderRadius: BorderRadius.circular(18),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.arrow_down_circle_fill,
                color: blue,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Письма загружаются. Ящик подключён недавно — письма '
                  'появятся в ближайшее время и будут подгружаться '
                  'постепенно.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 24),
                onPressed: () async {
                  await MailSyncNoticeService.instance.dismiss(
                    _connection.email,
                  );
                  if (mounted) setState(() {});
                },
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 15,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    MailUnreadService.instance.mailChanges.removeListener(_refreshVisible);
    _searchController.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _swipeGroup.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshVisible();
  }

  void _refreshVisible() {
    if (!mounted ||
        _isLoadingFolders ||
        _isLoadingMessages ||
        _isLoadingMore ||
        _isEditing ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    unawaited(_loadMessages(keepLoaded: true));
  }

  Future<void> _loadFolders() async {
    final connectionId = _connection.id;
    setState(() => _isLoadingFolders = true);
    await _showCachedFolders(connectionId);
    try {
      final folders = await MailRepository.instance.getMailboxes(connectionId);
      if (!mounted || connectionId != _connection.id) return;
      setState(() {
        _folders = folders;
        _selectedFolder =
            folders.where((f) => f.isInbox).firstOrNull ??
            folders.where((f) => f.id > 0).firstOrNull;
        _isLoadingFolders = false;
      });
      await _loadMessages();
    } catch (_) {
      if (!mounted || connectionId != _connection.id) return;
      setState(() => _isLoadingFolders = false);
      await _loadMessages();
    }
  }

  /// Папки и письма с прошлого раза — на экран сразу, пока идут запросы.
  Future<void> _showCachedFolders(int connectionId) async {
    final folders = await MailRepository.instance.cachedMailboxes(connectionId);
    if (folders == null || !mounted || connectionId != _connection.id) return;
    if (_folders.isNotEmpty) return;
    setState(() {
      _folders = folders;
      _selectedFolder =
          folders.where((f) => f.isInbox).firstOrNull ??
          folders.where((f) => f.id > 0).firstOrNull;
    });
    await _showCachedMessages(connectionId, _selectedFolder, _requestVersion);
  }

  /// Первая страница папки из кэша, пока список пуст (первое открытие,
  /// смена папки). Подгрузку следующих страниц не включаем — она начнётся
  /// от свежей первой страницы.
  Future<void> _showCachedMessages(
    int connectionId,
    MailFolder? folder,
    int version,
  ) async {
    final page = await MailRepository.instance.cachedMessages(
      connectionId,
      folderId: folder?.id,
    );
    if (page == null || page.messages.isEmpty || !mounted) return;
    if (version != _requestVersion ||
        connectionId != _connection.id ||
        _selectedFolder?.id != folder?.id ||
        _messages.isNotEmpty) {
      return;
    }
    setState(() {
      _messages = page.messages;
      _hasMoreMessages = false;
    });
  }

  List<MailFolder> get _browsableFolders =>
      _folders.where((folder) => folder.id > 0).toList();

  /// Перечитывает первую страницу. С [keepLoaded] (фоновое обновление,
  /// возврат из письма) уже подгруженные страницы сохраняются — раньше
  /// автообновление раз в минуту обрезало список до первой страницы, и
  /// долистанные письма пропадали.
  Future<void> _loadMessages({
    bool forceSync = false,
    bool keepLoaded = false,
  }) async {
    if (!mounted) return;
    final version = ++_requestVersion;
    final connectionId = _connection.id;
    final folder = _selectedFolder;
    setState(() {
      _isLoadingMessages = true;
      _isLoadingMore = false;
    });
    if (_messages.isEmpty) {
      unawaited(_showCachedMessages(connectionId, folder, version));
    }
    try {
      if (forceSync) {
        await MailRepository.instance.fetchMessages(connectionId);
      }
      final usingService = folder == null;
      final page = usingService
          ? await MailRepository.instance.getMessagesByService(connectionId)
          : await MailRepository.instance.getMessagesByFolder(
              connectionId: connectionId,
              folderId: folder.id,
            );
      var folders = _folders;
      try {
        folders = await MailRepository.instance.getMailboxes(connectionId);
      } catch (_) {
        // A counter failure must not discard successfully loaded messages.
      }
      if (!mounted || version != _requestVersion) return;
      final tail = keepLoaded ? _olderLoadedMessages(page.messages) : const [];
      setState(() {
        _folders = folders;
        _selectedFolder =
            folders.where((f) => f.id == folder?.id).firstOrNull ?? folder;
        _messages = [...page.messages, ...tail];
        if (tail.isEmpty) {
          _hasMoreMessages = page.hasMore;
          _nextPage = page.nextPage;
        }
        _loadMoreFailed = false;
        _usingServiceFallback = usingService;
        _isLoadingMessages = false;
      });
      unawaited(MailUnreadService.instance.refresh());
      _fillViewportIfNeeded();
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() => _isLoadingMessages = false);
      // Без сети на экране остаётся список из кэша — фоновое обновление
      // не ругается, ошибку показываем только на явное действие.
      if (_messages.isNotEmpty && !forceSync) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            forceSync
                ? 'Не удалось синхронизировать почту. Повторите обновление.'
                : 'Не удалось загрузить письма. Повторите обновление.',
          ),
        ),
      );
    }
  }

  /// Письма со следующих страниц, уже загруженные раньше: всё, что старше
  /// самого старого письма свежей первой страницы. Удалённые на сервере
  /// письма из диапазона первой страницы при этом уходят из списка.
  List<MailMessage> _olderLoadedMessages(List<MailMessage> firstPage) {
    if (firstPage.isEmpty || _messages.length <= firstPage.length) {
      return const [];
    }
    final ids = firstPage.map((m) => m.id).toSet();
    final dates = firstPage.map((m) => m.date).whereType<DateTime>();
    final oldest = dates.isEmpty
        ? null
        : dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final lastKnown = _messages.lastIndexWhere((m) => ids.contains(m.id));
    final result = <MailMessage>[];
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (ids.contains(m.id)) continue;
      final isOlder = oldest != null && m.date != null
          ? m.date!.isBefore(oldest)
          : i > lastKnown;
      if (isOlder) result.add(m);
    }
    return result;
  }

  /// Первая страница может не заполнить экран — тогда прокрутки нет и
  /// подгрузка по скроллу не сработает никогда. Догружаем сами.
  void _fillViewportIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels < 200) {
        _loadMoreMessages();
      }
    });
  }

  Future<void> _loadMoreMessages({bool manual = false}) async {
    if (_loadMoreFailed && !manual) return;
    if (_isSearchMode) {
      final query = _searchQuery.trim();
      if (_isLoadingMore || _isSearching || !_searchHasMore) return;
      if (_searchResults == null) return;
      setState(() => _isLoadingMore = true);
      await _runSearch(query, page: _searchNextPage);
      if (mounted) setState(() => _isLoadingMore = false);
      return;
    }
    if (_isLoadingMore || !_hasMoreMessages || _isLoadingMessages) return;
    final version = _requestVersion;
    setState(() => _isLoadingMore = true);
    try {
      final MailMessagePage page;
      final folder = _selectedFolder;
      final usingService =
          _usingServiceFallback || folder == null || folder.id <= 0;
      if (!usingService) {
        page = await MailRepository.instance.getMessagesByFolder(
          connectionId: _connection.id,
          folderId: folder.id,
          page: _nextPage,
        );
      } else {
        page = await MailRepository.instance.getMessagesByService(
          _connection.id,
          page: _nextPage,
        );
      }
      final newMessages = page.messages;
      if (!mounted || version != _requestVersion) return;
      final existingIds = _messages.map((m) => m.id).toSet();
      setState(() {
        _messages = [
          ..._messages,
          ...newMessages.where((m) => !existingIds.contains(m.id)),
        ];
        _hasMoreMessages = page.hasMore;
        _nextPage = page.nextPage;
        _isLoadingMore = false;
        _loadMoreFailed = false;
      });
      _fillViewportIfNeeded();
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = value;
      _searchResults = null;
      _searchHasMore = false;
      _isSearching = false;
    });
    _searchVersion++;
    final query = value.trim();
    if (query.length < 2) return;
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(query),
    );
  }

  /// Серверный поиск по всем ящикам пользователя — оставляем только
  /// текущий ящик.
  Future<void> _runSearch(String query, {int page = 1}) async {
    final version = page == 1 ? ++_searchVersion : _searchVersion;
    final connectionId = _connection.id;
    if (page == 1) setState(() => _isSearching = true);
    try {
      final result = await MailRepository.instance.searchMessages(
        query,
        page: page,
      );
      if (!mounted ||
          version != _searchVersion ||
          connectionId != _connection.id) {
        return;
      }
      final found = result.results
          .where((r) => r.connectionId == connectionId)
          .map((r) => r.message);
      final existing = page == 1 ? <MailMessage>[] : [...?_searchResults];
      final ids = existing.map((m) => m.id).toSet();
      setState(() {
        _searchResults = [...existing, ...found.where((m) => ids.add(m.id))];
        _searchHasMore = result.hasMore;
        _searchNextPage = result.nextPage;
        _isSearching = false;
      });
      _fillViewportIfNeeded();
    } catch (_) {
      if (!mounted || version != _searchVersion) return;
      // Остаётся поиск по загруженным письмам.
      setState(() {
        _isSearching = false;
        _searchHasMore = false;
      });
    }
  }

  /// Подменяет письмо и в общем списке, и в результатах поиска.
  void _replaceMessage(int id, MailMessage Function(MailMessage) update) {
    List<MailMessage> apply(List<MailMessage> list) => [
      for (final m in list) m.id == id ? update(m) : m,
    ];
    _messages = apply(_messages);
    final results = _searchResults;
    if (results != null) _searchResults = apply(results);
  }

  Future<void> _openCompose({MailMessage? replyTo}) async {
    final sent = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) =>
            ComposeMailScreen(connection: _connection, replyTo: replyTo),
      ),
    );
    if (sent == true && mounted) await _loadMessages(forceSync: true);
  }

  Future<void> _openMessage(MailMessage message) async {
    final wasUnread = !message.isRead;
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) => MailMessageScreen(
          connection: _connection,
          messageId: message.id,
          initialMessage: message,
          folders: _folders,
          currentFolder: _selectedFolder,
          onMove: (folder) => _moveMessage(message, folder),
        ),
      ),
    );
    if (!mounted) return;
    // Статус меняем сразу, не дожидаясь списка с сервера: письмо открыто —
    // значит прочитано (или его вручную вернули в непрочитанные).
    final connectionId = _connection.id;
    setState(
      () => _replaceMessage(
        message.id,
        (m) => MailRepository.instance.withLocalReadState(connectionId, m),
      ),
    );
    // MailMessageScreen помечает письмо прочитанным на сервере при открытии,
    // но возвращает `true` только когда пользователь явно что-то изменил
    // (удалил/переместил/ответил) — обычный возврат назад приходит с `null`.
    // Перезагружаем список и в этом случае, чтобы сверить статус с сервером.
    final readChanged =
        MailRepository.instance
            .withLocalReadState(connectionId, message)
            .isRead !=
        message.isRead;
    if (changed == true || wasUnread || readChanged) {
      await _loadMessages(keepLoaded: true);
    }
  }

  Future<void> _showFolderPicker() async {
    if (_folders.isEmpty) return;
    final picked = await Navigator.of(context).push<MailFolder>(
      CupertinoPageRoute<MailFolder>(
        builder: (context) => MailFoldersScreen(
          folders: _browsableFolders,
          selected: _selectedFolder,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedFolder = picked;
      _messages = [];
      _isLoadingMore = false;
    });
    _loadMessages();
  }

  Future<void> _toggleRead(MailMessage message) async {
    try {
      final connectionId = _connection.id;
      await (message.isRead
          ? MailRepository.instance.markUnread(
              connectionId: connectionId,
              messageId: message.id,
            )
          : MailRepository.instance.markRead(
              connectionId: connectionId,
              messageId: message.id,
            ));
      MailUnreadService.instance.invalidate();
      if (!mounted || connectionId != _connection.id) return;
      setState(
        () => _replaceMessage(message.id, (m) => m.withRead(!message.isRead)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось изменить статус письма')),
      );
    }
  }

  /// Удаление свайпом: письмо сразу пропадает, но несколько секунд его
  /// можно вернуть из снекбара — раньше оно удалялось мгновенно и
  /// безвозвратно от случайного свайпа.
  void _deleteMessage(MailMessage message) {
    final connectionId = _connection.id;
    setState(() => _pendingDeleteIds.add(message.id));
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      unawaited(_commitDelete(message, connectionId));
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            // С action Flutter по умолчанию держит снекбар вечно
            // (persist), а письмо удаляется только после его закрытия.
            persist: false,
            duration: const Duration(seconds: 4),
            content: const Text('Письмо удалено'),
            action: SnackBarAction(label: 'Вернуть', onPressed: () {}),
          ),
        )
        .closed
        .then((reason) {
          if (reason == SnackBarClosedReason.action) {
            if (mounted) {
              setState(() => _pendingDeleteIds.remove(message.id));
            }
            return;
          }
          unawaited(_commitDelete(message, connectionId));
        });
  }

  Future<void> _commitDelete(MailMessage message, int connectionId) async {
    try {
      await MailRepository.instance.deleteMessage(
        connectionId: connectionId,
        messageId: message.id,
      );
      if (!message.isRead) MailUnreadService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
        _searchResults?.removeWhere((m) => m.id == message.id);
        _pendingDeleteIds.remove(message.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendingDeleteIds.remove(message.id));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить письмо')),
      );
    }
  }

  /// Письмо сразу скрывается из списка, перенос идёт в фоне; при ошибке
  /// возвращается на место.
  Future<void> _moveMessage(MailMessage message, MailFolder folder) async {
    final connectionId = _connection.id;
    setState(() => _pendingDeleteIds.add(message.id));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Письмо перемещено в «${folder.displayName}»')),
      );
    try {
      await MailRepository.instance.moveMessage(
        connectionId: connectionId,
        messageId: message.id,
        folderId: folder.id,
      );
      MailUnreadService.instance.invalidate();
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
        _searchResults?.removeWhere((m) => m.id == message.id);
        _pendingDeleteIds.remove(message.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendingDeleteIds.remove(message.id));
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Не удалось переместить письмо')),
        );
    }
  }

  void _setEditing(bool value) {
    setState(() {
      _isEditing = value;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(int messageId) {
    setState(() {
      if (!_selectedIds.remove(messageId)) _selectedIds.add(messageId);
    });
  }

  Future<void> _bulkMarkRead({required bool read}) async {
    if (_selectedIds.isEmpty || _isBulkActing) return;
    final ids = _selectedIds.toList();
    setState(() => _isBulkActing = true);
    try {
      if (read) {
        await MailRepository.instance.markFewRead(
          connectionId: _connection.id,
          ids: ids,
        );
      } else {
        for (final id in ids) {
          await MailRepository.instance.markUnread(
            connectionId: _connection.id,
            messageId: id,
          );
        }
      }
      MailUnreadService.instance.refresh();
      if (!mounted) return;
      _setEditing(false);
      await _loadMessages(keepLoaded: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось изменить статус писем')),
      );
    } finally {
      if (mounted) setState(() => _isBulkActing = false);
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty || _isBulkActing) return;
    final ids = _selectedIds.toList();
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              ids.length == 1
                  ? 'Удалить письмо'
                  : 'Удалить письма (${ids.length})',
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = <int>{};
    setState(() => _isBulkActing = true);
    try {
      // Бэкендовый /mail/delete/few/{connection} не принимает ids (см.
      // deleteFewUrl) и, судя по сигнатуре, удалил бы не то, что выбрано —
      // поэтому массовое удаление делаем последовательными вызовами
      // одиночного, уже проверенного /mail/delete/{connection}/{message}.
      for (final id in ids) {
        await MailRepository.instance.deleteMessage(
          connectionId: _connection.id,
          messageId: id,
        );
        deleted.add(id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Не удалось удалить часть писем')),
        );
      }
    } finally {
      MailUnreadService.instance.refresh();
      if (mounted) {
        // Удалённое убираем сразу: перезагрузка сохраняет подгруженные
        // страницы и без этого вернула бы их из старого списка.
        setState(() {
          _messages.removeWhere((m) => deleted.contains(m.id));
          _searchResults?.removeWhere((m) => deleted.contains(m.id));
        });
        _setEditing(false);
        await _loadMessages(keepLoaded: true);
      }
      if (mounted) setState(() => _isBulkActing = false);
    }
  }

  void _selectConnection(MailConnection connection) {
    if (connection.id == _connection.id) return;
    setState(() {
      _requestVersion++;
      _isLoadingMore = false;
      _connection = connection;
      _folders = [];
      _messages = [];
      _selectedFolder = null;
      _isLoadingFolders = true;
      _hasMoreMessages = false;
      _nextPage = 1;
      _usingServiceFallback = false;
      _searchController.clear();
      _searchQuery = '';
      _searchResults = null;
      _searchHasMore = false;
      _isSearching = false;
      _searchVersion++;
      _loadMoreFailed = false;
      _pendingDeleteIds.clear();
      _isEditing = false;
      _selectedIds.clear();
    });
    _loadFolders();
  }

  Future<void> _showAccountPicker() async {
    if (_connections.length < 2) return;
    final picked = await showCupertinoModalPopup<MailConnection>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Почтовые ящики'),
        actions: [
          for (final c in _connections)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, c),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (c.id == _connection.id)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(CupertinoIcons.check_mark, size: 18),
                    ),
                  Flexible(
                    child: Text(
                      '${c.displayName} · ${c.email}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (picked != null) _selectConnection(picked);
  }

  Future<void> _openManageMailboxes() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const MailScreen(autoOpenInbox: false),
      ),
    );
    if (!mounted) return;
    await _refreshConnections();
  }

  Future<void> _refreshConnections() async {
    try {
      final items = await MailScreen.loadConnectionsForCurrentUser();
      if (!mounted || items.isEmpty) return;
      final stillSelected = items.where((c) => c.id == _connection.id);
      final nextConnection = stillSelected.isNotEmpty
          ? stillSelected.first
          : items.firstWhere((c) => c.isDefault, orElse: () => items.first);
      final changed = nextConnection.id != _connection.id;
      setState(() {
        _connections = items;
        _connection = nextConnection;
      });
      if (changed) await _loadFolders();
    } catch (_) {}
  }

  Future<void> _showMoreMenu() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          if (_visibleMessages.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'select'),
              child: const Text('Выбрать письма'),
            ),
          if (_connections.length > 1)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'account'),
              child: const Text('Сменить ящик'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'manage'),
            child: const Text('Почтовые ящики'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'select':
        _setEditing(true);
      case 'account':
        await _showAccountPicker();
      case 'manage':
        await _openManageMailboxes();
    }
  }

  String get _title {
    if (_isEditing) {
      return _selectedIds.isEmpty
          ? 'Выберите письма'
          : 'Выбрано: ${_selectedIds.length}';
    }
    final folder = _selectedFolder;
    return folder == null || folder.isAllInbox
        ? 'Входящие'
        : folder.displayName;
  }

  Widget _buildNavBar(BuildContext context, {required bool blur}) {
    final label = CupertinoColors.label.resolveFrom(context);
    Widget iconButton(IconData icon, VoidCallback onPressed) => CupertinoButton(
      padding: const EdgeInsets.only(left: 16),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Icon(icon, size: AppSliverTitleBar.iconSize, color: label),
    );

    return AppSliverTitleBar(
      title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
      blur: blur,
      home: !_isEditing,
      leading: _isEditing
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => _setEditing(false),
              child: Text('Отмена', style: TextStyle(color: label)),
            )
          : widget.isTab
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => Navigator.maybePop(context),
              child: Icon(
                CupertinoIcons.back,
                size: AppSliverTitleBar.iconSize,
                color: label,
              ),
            ),
      trailing: _isEditing
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => _setEditing(false),
              child: Text(
                'Готово',
                style: TextStyle(fontWeight: FontWeight.w600, color: label),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_folders.isNotEmpty)
                  iconButton(CupertinoIcons.folder, _showFolderPicker),
                iconButton(CupertinoIcons.ellipsis_circle, _showMoreMenu),
                // Во вкладке нижняя панель уступила место таббару —
                // «написать» переезжает в шапку, как «+» в Чатах.
                if (widget.isTab)
                  iconButton(CupertinoIcons.square_pencil, _openCompose),
              ],
            ),
    );
  }

  /// Адрес ящика под заголовком; при нескольких ящиках — стеклянная
  /// капсула, открывающая переключатель.
  Widget _buildAccountChip(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final text = Text(
      _connection.email,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 14, color: secondary),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _connections.length < 2
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: text,
              )
            : AppGlass(
                borderRadius: BorderRadius.circular(16),
                shadows: AppGlass.controlShadow,
                child: CupertinoButton(
                  padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
                  minimumSize: Size.zero,
                  onPressed: _isEditing ? null : _showAccountPicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: text),
                      const SizedBox(width: 4),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 12,
                        color: secondary,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final red = CupertinoColors.systemRed.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: AppGlass(
        borderRadius: BorderRadius.circular(18),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: red,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _connection.lastError ?? 'Почтовое подключение неактивно',
                  style: TextStyle(fontSize: 13, height: 1.3, color: red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildListSlivers(BuildContext context) {
    if ((_isLoadingFolders || _isLoadingMessages) && _messages.isEmpty) {
      return [
        SliverList.builder(
          itemCount: 8,
          itemBuilder: (context, index) => const AppSkeletonListTile(),
        ),
      ];
    }

    final messages = _visibleMessages;
    if (messages.isEmpty && _isSearching) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      ];
    }
    if (messages.isEmpty && !_isLoadingMessages) {
      return [
        SliverAppEmptyState(
          icon: _searchQuery.isNotEmpty
              ? CupertinoIcons.search
              : _isInitialSync
              ? CupertinoIcons.arrow_down_circle
              : CupertinoIcons.tray,
          message: _searchQuery.isNotEmpty
              ? 'Ничего не найдено'
              : _isInitialSync
              ? 'Письма ещё загружаются\nОни появятся здесь в ближайшее время'
              : _selectedFolder != null
              ? 'В папке «${_selectedFolder!.displayName}» нет писем'
              : 'Нет писем',
        ),
      ];
    }

    final isOutgoingFolder =
        (_selectedFolder?.isSent ?? false) ||
        (_selectedFolder?.isDrafts ?? false);
    final ownEmail = _connection.email.trim().toLowerCase();
    return [
      SliverList.separated(
        itemCount: messages.length,
        separatorBuilder: (context, index) => Container(
          height: 0.5,
          margin: EdgeInsets.only(
            left: _MessageTile.textIndent(isEditing: _isEditing),
          ),
          color: CupertinoColors.separator.resolveFrom(context),
        ),
        itemBuilder: (context, index) {
          final message = messages[index];
          return _MessageTile(
            message: message,
            showUnread: !isOutgoingFolder,
            // В «Отправленных» и «Черновиках» (и у своих писем в поиске)
            // важнее, кому письмо, — раньше там везде стояло своё имя.
            showRecipient:
                isOutgoingFolder ||
                mailEmailOnly(message.from).toLowerCase() == ownEmail,
            isEditing: _isEditing,
            isSelected: _selectedIds.contains(message.id),
            onTap: _isEditing
                ? () => _toggleSelected(message.id)
                : () => _openMessage(message),
            onToggleRead: () => _toggleRead(message),
            onDelete: () => _deleteMessage(message),
            swipeGroup: _swipeGroup,
          );
        },
      ),
      if (_isLoadingMessages || _isLoadingMore || _isSearching)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        )
      else if (_loadMoreFailed)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: CupertinoButton(
                onPressed: () => _loadMoreMessages(manual: true),
                child: Text(
                  'Не удалось загрузить письма. Повторить',
                  style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasConnectionError =
        !_connection.isActive || (_connection.lastError ?? '').isNotEmpty;

    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: AppColors.screenBackground.resolveFrom(context),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: AppHaptics.onRefresh(
                    () => _loadMessages(forceSync: true),
                  ),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      final metrics = notification.metrics;
                      if (metrics.pixels >= metrics.maxScrollExtent - 200) {
                        _loadMoreMessages();
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        _buildNavBar(context, blur: blur),
                        SliverToBoxAdapter(child: _buildAccountChip(context)),
                        if (widget.isTab)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: CupertinoSearchTextField(
                                controller: _searchController,
                                placeholder: 'Поиск писем',
                                onChanged: _onSearchChanged,
                              ),
                            ),
                          ),
                        if (hasConnectionError)
                          SliverToBoxAdapter(child: _buildErrorBanner(context))
                        else if (_isInitialSync && !_isSearchMode)
                          SliverToBoxAdapter(child: _buildSyncNotice(context)),
                        ..._buildListSlivers(context),
                        // Последнее письмо не должно прятаться под панелью.
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: widget.isTab && !_isEditing
                                ? MediaQuery.paddingOf(context).bottom + 16
                                : MailFloatingBar.reservedHeight(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _isEditing
                    ? _EditToolbar(
                        selectedCount: _selectedIds.length,
                        isBusy: _isBulkActing,
                        onMarkRead: () => _bulkMarkRead(read: true),
                        onMarkUnread: () => _bulkMarkRead(read: false),
                        onDelete: _bulkDelete,
                      )
                    : widget.isTab
                    ? const SizedBox.shrink()
                    : _SearchComposeBar(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        onCompose: () => _openCompose(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка письма как в «Почте» iOS: точка «непрочитано», монограмма
/// отправителя, имя и дата, тема, две строки превью.
class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    this.showUnread = true,
    this.showRecipient = false,
    required this.isEditing,
    required this.isSelected,
    required this.onTap,
    required this.onToggleRead,
    required this.onDelete,
    required this.swipeGroup,
  });

  static const double _dotSlot = 18;
  static const double _avatarRadius = 20;
  static const double _checkSlot = 32;

  /// Отступ разделителя — по левому краю текста, как в системных списках.
  static double textIndent({required bool isEditing}) =>
      6 + (isEditing ? _checkSlot : 0) + _dotSlot + _avatarRadius * 2 + 12;

  final MailMessage message;
  final bool showUnread;

  /// Показывать получателя вместо отправителя (свои письма).
  final bool showRecipient;
  final bool isEditing;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final SwipeGroupController swipeGroup;

  @override
  Widget build(BuildContext context) {
    final isUnread = showUnread && !message.isRead;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final recipients = MailMessage.splitAddresses(message.to);
    final person = showRecipient
        ? (recipients.isEmpty ? '' : mailDisplayName(recipients.first))
        : mailDisplayName(message.from);
    final String senderLabel;
    if (person.isEmpty) {
      senderLabel = showRecipient
          ? 'Без получателя'
          : 'Неизвестный отправитель';
    } else if (showRecipient && recipients.length > 1) {
      senderLabel = '$person и ещё ${recipients.length - 1}';
    } else {
      senderLabel = person;
    }

    // Без заливки: под строками просвечивает цветное пятно за шапкой.
    final row = ColoredBox(
      color: isSelected
          ? AppColors.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEditing)
                SizedBox(
                  width: _checkSlot,
                  height: _avatarRadius * 2,
                  child: Center(
                    child: Icon(
                      isSelected
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 24,
                      color: isSelected
                          ? AppColors.primary
                          : CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ),
                ),
              SizedBox(
                width: _dotSlot,
                height: _avatarRadius * 2,
                child: isUnread
                    ? Center(
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              MemberAvatar(
                displayName: person.isEmpty ? '?' : person,
                radius: _avatarRadius,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            senderLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: label,
                            ),
                          ),
                        ),
                        if (message.hasAttachments) ...[
                          const SizedBox(width: 6),
                          Icon(
                            CupertinoIcons.paperclip,
                            size: 14,
                            color: secondary,
                          ),
                        ],
                        if (message.date != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            formatMailListDate(message.date!),
                            style: TextStyle(
                              fontSize: 13,
                              color: isUnread ? AppColors.primary : secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: label,
                      ),
                    ),
                    if (message.previewBody.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        message.previewBody.replaceAll(RegExp(r'\s+'), ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.25,
                          color: secondary,
                        ),
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

    if (isEditing) return row;

    return SwipeActionsRow(
      id: '${message.id}',
      groupController: swipeGroup,
      borderRadius: BorderRadius.zero,
      startActions: [
        SwipeAction(
          icon: isUnread
              ? CupertinoIcons.envelope_open
              : CupertinoIcons.envelope_badge,
          label: isUnread ? 'Прочитано' : 'Непрочит.',
          color: AppColors.primary,
          onTap: onToggleRead,
        ),
      ],
      actions: [
        SwipeAction(
          icon: CupertinoIcons.trash,
          label: 'Удалить',
          color: CupertinoColors.systemRed.resolveFrom(context),
          onTap: onDelete,
        ),
      ],
      child: row,
    );
  }
}

/// Нижняя стеклянная панель: поиск по загруженным письмам и «написать».
class _SearchComposeBar extends StatelessWidget {
  const _SearchComposeBar({
    required this.controller,
    required this.onChanged,
    required this.onCompose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return MailFloatingBar(
      child: Row(
        children: [
          Expanded(
            child: AppGlass(
              borderRadius: BorderRadius.circular(MailFloatingBar.height / 2),
              shadows: AppGlass.controlShadow,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: CupertinoSearchTextField(
                    controller: controller,
                    placeholder: 'Поиск писем',
                    backgroundColor: Colors.transparent,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MailGlassIconButton(
            icon: CupertinoIcons.square_pencil,
            onPressed: onCompose,
          ),
        ],
      ),
    );
  }
}

class _EditToolbar extends StatelessWidget {
  const _EditToolbar({
    required this.selectedCount,
    required this.isBusy,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onDelete,
  });

  final int selectedCount;
  final bool isBusy;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = selectedCount > 0 && !isBusy;
    return MailFloatingBar(
      child: AppGlass(
        borderRadius: BorderRadius.circular(MailFloatingBar.height / 2),
        shadows: AppGlass.controlShadow,
        child: isBusy
            ? const Center(child: CupertinoActivityIndicator())
            : Row(
                children: [
                  MailBarAction(
                    icon: CupertinoIcons.envelope_open,
                    label: 'Прочитано',
                    onPressed: enabled ? onMarkRead : null,
                  ),
                  MailBarAction(
                    icon: CupertinoIcons.envelope_badge,
                    label: 'Непрочитано',
                    onPressed: enabled ? onMarkUnread : null,
                  ),
                  MailBarAction(
                    icon: CupertinoIcons.trash,
                    label: 'Удалить',
                    onPressed: enabled ? onDelete : null,
                    isDestructive: true,
                  ),
                ],
              ),
      ),
    );
  }
}
