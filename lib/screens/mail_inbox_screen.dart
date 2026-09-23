import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, RefreshIndicator, Scaffold, ScaffoldMessenger, SnackBar;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../services/mail_unread_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import 'compose_mail_screen.dart';
import 'mail_folders_screen.dart';
import 'mail_message_screen.dart';
import 'mail_screen.dart';

class MailInboxScreen extends StatefulWidget {
  const MailInboxScreen({
    super.key,
    required this.connection,
    this.connections = const [],
  });

  final MailConnection connection;

  /// Остальные подключённые ящики пользователя — чтобы показать
  /// переключатель в шапке. Если пуст или содержит только [connection],
  /// переключатель скрыт (переключаться не между чем).
  final List<MailConnection> connections;

  @override
  State<MailInboxScreen> createState() => _MailInboxScreenState();
}

class _MailInboxScreenState extends State<MailInboxScreen> {
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

  /// Кэш id писем в папке(ах) «Спам» — используется, чтобы вычесть их из
  /// сводной ленты «Все входящие» (см. [_filterSpamIfNeeded]): бэкенд в
  /// `/mail/get/service` отдаёт вообще все письма ящика без привязки к
  /// папке в ответе, поэтому единственный способ исключить спам на клиенте —
  /// заранее узнать id спам-писем и отфильтровать по ним.
  Set<int>? _spamMessageIds;
  Future<Set<int>>? _spamMessageIdsFuture;

  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isEditing = false;
  final Set<int> _selectedIds = {};
  bool _isBulkActing = false;

  List<MailMessage> get _visibleMessages {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _messages;
    return _messages.where((m) {
      return m.subject.toLowerCase().contains(query) ||
          m.from.toLowerCase().contains(query) ||
          m.previewBody.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoadingFolders = true);
    try {
      final folders = await MailRepository.instance.getMailboxes(
        _connection.id,
      );
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _selectedFolder = _buildAllInboxFolder(folders);
        _isLoadingFolders = false;
      });
      // Папки (и их id) могли смениться — кэш id спам-писем не годится.
      _spamMessageIds = null;
      _spamMessageIdsFuture = null;
      await _loadMessages();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingFolders = false);
      await _loadMessages(fallbackToService: true);
    }
  }

  /// «Все входящие» — единая точка входа вместо того, чтобы заставлять
  /// переключаться между Входящими и их вложенными подпапками по отдельности
  /// (см. `_browsableFolders`); счётчики — сумма по всем папкам ящика,
  /// посчитанная на клиенте, т.к. сервер такую сводную папку не отдаёт.
  MailFolder _buildAllInboxFolder(List<MailFolder> folders) {
    int? unread;
    int? total;
    for (final folder in folders) {
      if (folder.unreadCount != null) {
        unread = (unread ?? 0) + folder.unreadCount!;
      }
      if (folder.totalCount != null) {
        total = (total ?? 0) + folder.totalCount!;
      }
    }
    return MailFolder.allInbox(unreadCount: unread, totalCount: total);
  }

  /// Папки для экрана-переключателя: вместо плоского дерева, где Входящие и
  /// все их вложенные подпапки перечислены по отдельности (при глубокой
  /// вложенности список становится нечитаемо длинным), показываем единую
  /// «Все входящие» + остальные папки верхнего уровня (Черновики,
  /// Отправленные, Спам, Корзина, кастомные) — их вложенные подпапки тоже
  /// не дублируем отдельными пунктами, письма из них доступны через
  /// «Все входящие».
  List<MailFolder> get _browsableFolders => [
    _buildAllInboxFolder(_folders),
    for (final folder in _folders)
      if (folder.depth == 0 && !folder.isInbox) folder,
  ];

  /// Забирает id всех писем из папки(ок) «Спам» — по одной странице
  /// `getMessagesByFolder` за раз, пока сервер не скажет `hasMore == false`.
  /// Результат кэшируется в [_spamMessageIds]; при параллельных вызовах
  /// (загрузка + подгрузка следующей страницы) все ждут один и тот же Future.
  /// [_maxSpamPagesPerFolder] — защита от зависания, если сервер вдруг
  /// вечно возвращает `hasMore: true`.
  static const int _maxSpamPagesPerFolder = 50;

  Future<Set<int>> _ensureSpamMessageIds() {
    if (_spamMessageIds != null) return Future.value(_spamMessageIds);
    return _spamMessageIdsFuture ??= _fetchSpamMessageIds().then((ids) {
      _spamMessageIds = ids;
      return ids;
    }).whenComplete(() => _spamMessageIdsFuture = null);
  }

  Future<Set<int>> _fetchSpamMessageIds() async {
    final spamFolders = _folders.where((f) => f.isSpam);
    final ids = <int>{};
    for (final folder in spamFolders) {
      var page = 1;
      for (var i = 0; i < _maxSpamPagesPerFolder; i++) {
        final MailMessagePage result;
        try {
          result = await MailRepository.instance.getMessagesByFolder(
            connectionId: _connection.id,
            folderId: folder.id,
            page: page,
          );
        } catch (_) {
          // Папка «Спам» не прочиталась — лучше показать письма как есть,
          // чем вовсе не показать «Все входящие» из-за побочного запроса.
          break;
        }
        ids.addAll(result.messages.map((m) => m.id));
        if (!result.hasMore) break;
        page = result.nextPage;
      }
    }
    return ids;
  }

  /// «Все входящие» построено поверх `getMessagesByService`, который
  /// отдаёт вообще все письма ящика (в т.ч. спам) одним списком без пометки
  /// папки — поэтому спам вычитается на клиенте по id, полученным из
  /// [_ensureSpamMessageIds]. К письмам, загруженным напрямую по папке
  /// (`getMessagesByFolder`), фильтр не применяется — там пользователь и
  /// так открыл конкретную папку явно, включая саму папку «Спам».
  Future<List<MailMessage>> _filterSpamIfNeeded(
    List<MailMessage> messages, {
    required bool usingService,
  }) async {
    if (!usingService) return messages;
    try {
      final spamIds = await _ensureSpamMessageIds();
      if (spamIds.isEmpty) return messages;
      return messages.where((m) => !spamIds.contains(m.id)).toList();
    } catch (_) {
      return messages;
    }
  }

  Future<void> _loadMessages({
    bool fallbackToService = false,
    bool forceSync = false,
  }) async {
    setState(() => _isLoadingMessages = true);
    if (forceSync) {
      // Спам за это время мог пополниться/опустеть — не показываем письма
      // по устаревшему списку id.
      _spamMessageIds = null;
      _spamMessageIdsFuture = null;
      try {
        // getMessagesByFolder/getMessagesByService читают локальное зеркало
        // почты, которое обновляет фоновая синхронизация бэкенда — потянуть
        // вниз для обновления недостаточно, чтобы увидеть письма, удалённые
        // из веб-версии почты. /mail/fetch форсирует опрос IMAP прямо сейчас.
        await MailRepository.instance.fetchMessages(_connection.id);
      } catch (_) {
        // Не удалось форсировать синхронизацию — покажем то, что есть локально.
      }
    }
    try {
      final MailMessagePage page;
      final folder = _selectedFolder;
      final usingService =
          fallbackToService || folder == null || folder.id <= 0;
      if (!usingService) {
        page = await MailRepository.instance.getMessagesByFolder(
          connectionId: _connection.id,
          folderId: folder.id,
        );
      } else {
        page = await MailRepository.instance.getMessagesByService(
          _connection.id,
        );
      }
      final filteredMessages = await _filterSpamIfNeeded(
        page.messages,
        usingService: usingService,
      );
      if (!mounted) return;
      setState(() {
        _messages = filteredMessages;
        _hasMoreMessages = page.hasMore;
        _nextPage = page.nextPage;
        _usingServiceFallback = usingService;
        _isLoadingMessages = false;
      });
    } catch (_) {
      if (!fallbackToService && _selectedFolder != null) {
        try {
          final page = await MailRepository.instance.getMessagesByService(
            _connection.id,
          );
          final filteredMessages = await _filterSpamIfNeeded(
            page.messages,
            usingService: true,
          );
          if (!mounted) return;
          final failedFolder = _selectedFolder;
          setState(() {
            _messages = filteredMessages;
            _hasMoreMessages = page.hasMore;
            _nextPage = page.nextPage;
            _usingServiceFallback = true;
            _isLoadingMessages = false;
          });
          // Бэкенд не отдал письма этой конкретной папки (например, «Черновики»
          // с письмом без части заголовков падает на разборе на сервере) — без
          // этого уведомления подмена молча выглядела как переход во «Входящие».
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                'Не удалось загрузить папку «${failedFolder?.displayName}» — '
                'показан общий список писем',
              ),
            ),
          );
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

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _isLoadingMessages) return;
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
      final newMessages = await _filterSpamIfNeeded(
        page.messages,
        usingService: usingService,
      );
      if (!mounted) return;
      final existingIds = _messages.map((m) => m.id).toSet();
      setState(() {
        _messages = [
          ..._messages,
          ...newMessages.where((m) => !existingIds.contains(m.id)),
        ];
        _hasMoreMessages = page.hasMore;
        _nextPage = page.nextPage;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _openCompose({MailMessage? replyTo}) async {
    final sent = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) =>
            ComposeMailScreen(connection: _connection, replyTo: replyTo),
      ),
    );
    if (sent == true) await _loadMessages();
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
        ),
      ),
    );
    // MailMessageScreen помечает письмо прочитанным на сервере при открытии,
    // но возвращает `true` только когда пользователь явно что-то изменил
    // (удалил/переместил/ответил) — обычный возврат назад приходит с `null`.
    // Перезагружаем список и в этом случае, иначе точка-индикатор
    // «непрочитано» не исчезнет сама по себе.
    if (changed == true || wasUnread) await _loadMessages();
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
    if (picked == null) return;
    setState(() => _selectedFolder = picked);
    _loadMessages();
  }

  Future<void> _toggleRead(MailMessage message) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    try {
      final updated = message.isRead
          ? await MailRepository.instance.markUnread(
              connectionId: _connection.id,
              messageId: message.id,
            )
          : await MailRepository.instance.markRead(
              connectionId: _connection.id,
              messageId: message.id,
            );
      if (!mounted || index == -1) return;
      setState(() => _messages[index] = updated);
      MailUnreadService.instance.refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось изменить статус письма')),
      );
    }
  }

  Future<void> _deleteMessage(MailMessage message) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;
    setState(() => _messages.removeAt(index));
    try {
      await MailRepository.instance.deleteMessage(
        connectionId: _connection.id,
        messageId: message.id,
      );
      if (!message.isRead) MailUnreadService.instance.refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.insert(index, message));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить письмо')),
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
      await _loadMessages();
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
      }
      MailUnreadService.instance.refresh();
      if (!mounted) return;
      _setEditing(false);
      await _loadMessages();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить часть писем')),
      );
      _setEditing(false);
      await _loadMessages();
    } finally {
      if (mounted) setState(() => _isBulkActing = false);
    }
  }

  void _selectConnection(MailConnection connection) {
    if (connection.id == _connection.id) return;
    setState(() {
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM, HH:mm', 'ru_RU');

    // Wrapped in a Material Scaffold purely so ScaffoldMessenger has a local
    // Scaffold to attach SnackBars to — this screen is pushed on top of the
    // app's only Scaffold (MainNavigationScreen's), which sits hidden behind
    // it, so error SnackBars would otherwise render invisibly there.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemBackground,
        navigationBar: CupertinoNavigationBar(
          leading: _isEditing
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => _setEditing(false),
                  child: const Text('Отмена'),
                )
              : null,
          middle: Text(
            _selectedFolder == null || _selectedFolder!.isAllInbox
                ? 'Входящие'
                : _selectedFolder!.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: CupertinoColors.systemBackground,
          border: null,
          trailing: _isEditing
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => _setEditing(false),
                  child: const Text(
                    'Готово',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: _openManageMailboxes,
                      child: const Icon(CupertinoIcons.gear, size: 22),
                    ),
                    if (_folders.isNotEmpty)
                      CupertinoButton(
                        padding: const EdgeInsets.only(left: 14),
                        minimumSize: Size.zero,
                        onPressed: _showFolderPicker,
                        child: const Icon(CupertinoIcons.folder, size: 22),
                      ),
                    if (_visibleMessages.isNotEmpty)
                      CupertinoButton(
                        padding: const EdgeInsets.only(left: 14),
                        minimumSize: Size.zero,
                        onPressed: () => _setEditing(true),
                        child: const Text('Изменить'),
                      ),
                  ],
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
                            child: _connections.length > 1
                                ? CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    onPressed: _showAccountPicker,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _connection.email,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: CupertinoColors
                                                  .secondaryLabel
                                                  .resolveFrom(context),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          CupertinoIcons.chevron_down,
                                          size: 12,
                                          color: CupertinoColors.secondaryLabel
                                              .resolveFrom(context),
                                        ),
                                      ],
                                    ),
                                  )
                                : Text(
                                    _connection.email,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: CupertinoColors.secondaryLabel
                                          .resolveFrom(context),
                                    ),
                                  ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: () => _loadMessages(forceSync: true),
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  final metrics = notification.metrics;
                                  if (metrics.pixels >=
                                      metrics.maxScrollExtent - 200) {
                                    _loadMoreMessages();
                                  }
                                  return false;
                                },
                                child: ListView(
                                  padding: EdgeInsets.fromLTRB(
                                    0,
                                    8,
                                    0,
                                    88,
                                  ),
                                  children: [
                                    if (!_connection.isActive ||
                                        (_connection.lastError ?? '')
                                            .isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          12,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemRed
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                                _connection.lastError ??
                                                    'Почтовое подключение неактивно',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color:
                                                      CupertinoColors.systemRed,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (_visibleMessages.isEmpty &&
                                        !_isLoadingMessages)
                                      SizedBox(
                                        height:
                                            MediaQuery.sizeOf(context).height *
                                            0.35,
                                        child: AppEmptyState(
                                          icon: CupertinoIcons.tray,
                                          message: _searchQuery.isNotEmpty
                                              ? 'Ничего не найдено'
                                              : _selectedFolder != null
                                              ? 'В папке «${_selectedFolder!.displayName}» нет писем'
                                              : 'Нет писем',
                                        ),
                                      )
                                    else ...[
                                      for (
                                        var i = 0;
                                        i < _visibleMessages.length;
                                        i++
                                      )
                                        _MessageTile(
                                          message: _visibleMessages[i],
                                          dateFormat: dateFormat,
                                          isLast:
                                              i == _visibleMessages.length - 1,
                                          isEditing: _isEditing,
                                          isSelected: _selectedIds.contains(
                                            _visibleMessages[i].id,
                                          ),
                                          onTap: _isEditing
                                              ? () => _toggleSelected(
                                                  _visibleMessages[i].id,
                                                )
                                              : () => _openMessage(
                                                  _visibleMessages[i],
                                                ),
                                          onToggleRead: () =>
                                              _toggleRead(_visibleMessages[i]),
                                          onDelete: () => _deleteMessage(
                                            _visibleMessages[i],
                                          ),
                                        ),
                                      if (_isLoadingMessages || _isLoadingMore)
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
                          ),
                        ],
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
                      : _SearchComposeBar(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          onCompose: () => _openCompose(),
                        ),
                ),
              ],
            ),
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
    required this.isLast,
    required this.isEditing,
    required this.isSelected,
    required this.onTap,
    required this.onToggleRead,
    required this.onDelete,
  });

  final MailMessage message;
  final DateFormat dateFormat;
  final bool isLast;
  final bool isEditing;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isUnread = !message.isRead;

    final row = Container(
      decoration: BoxDecoration(
        color: isSelected
            ? CupertinoColors.systemBlue.withValues(alpha: 0.08)
            : CupertinoColors.systemBackground.resolveFrom(context),
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: CupertinoColors.separator.resolveFrom(context),
                  width: 0.33,
                ),
              ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEditing)
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 10),
                  child: Icon(
                    isSelected
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    size: 22,
                    color: isSelected
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
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

    if (isEditing) return row;

    return Slidable(
      key: ValueKey(message.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => onToggleRead(),
            backgroundColor: CupertinoColors.activeBlue,
            icon: isUnread
                ? CupertinoIcons.envelope_open
                : CupertinoIcons.envelope_badge,
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: CupertinoColors.systemRed,
            icon: CupertinoIcons.trash,
          ),
        ],
      ),
      child: row,
    );
  }
}

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground
            .resolveFrom(context)
            .withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.33,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: CupertinoSearchTextField(
                  controller: controller,
                  placeholder: 'Поиск писем',
                  onChanged: onChanged,
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.only(left: 6),
                minimumSize: Size.zero,
                onPressed: onCompose,
                child: const Icon(CupertinoIcons.square_pencil, size: 26),
              ),
            ],
          ),
        ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground
            .resolveFrom(context)
            .withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.33,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: isBusy
              ? const Center(child: CupertinoActivityIndicator())
              : Row(
                  children: [
                    _ToolbarAction(
                      icon: CupertinoIcons.envelope_open,
                      label: 'Прочитано',
                      enabled: enabled,
                      onTap: onMarkRead,
                    ),
                    _ToolbarAction(
                      icon: CupertinoIcons.envelope_badge,
                      label: 'Непрочитано',
                      enabled: enabled,
                      onTap: onMarkUnread,
                    ),
                    _ToolbarAction(
                      icon: CupertinoIcons.trash,
                      label: 'Удалить',
                      enabled: enabled,
                      onTap: onDelete,
                      isDestructive: true,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
        : isDestructive
        ? CupertinoColors.systemRed
        : CupertinoColors.activeBlue;
    return Expanded(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: enabled ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
