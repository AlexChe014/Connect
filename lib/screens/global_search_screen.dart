import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../models/chat.dart';
import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/staff_user.dart';
import '../repositories/mail_repository.dart';
import '../repositories/users_repository.dart';
import '../services/chat_service.dart';
import '../services/disk_search_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/chat_avatar.dart';
import 'chat_conversation_screen.dart';
import 'disk_screen.dart';
import 'employee_detail_screen.dart';
import 'mail_message_screen.dart';

/// Сквозной поиск по людям, чатам, почте и «Диску».
///
/// Раньше поиск был размазан по отдельным экранам (почта, чаты, сотрудники,
/// создание группы) — свой собственный `CupertinoSearchTextField` в каждом,
/// без единой точки входа. Этот экран объединяет их: один запрос
/// параллельно уходит в 4 независимых источника (чаты — локально по уже
/// загруженному списку, люди — `/user/filter`, почта — `/mail/search`,
/// «Диск» — best-effort обход дерева папок, т.к. у Nextcloud-модуля на
/// бэкенде нет своего поиска).
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  String _query = '';

  List<Chat> _chats = const [];

  bool _isLoadingPeople = false;
  List<StaffUser> _people = const [];

  bool _isLoadingMail = false;
  List<MailSearchResult> _mail = const [];

  bool _isLoadingDisk = false;
  List<DiskSearchHit> _disk = const [];
  bool _diskTruncated = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  bool get _isBusy => _isLoadingPeople || _isLoadingMail || _isLoadingDisk;

  bool get _hasAnyResult =>
      _chats.isNotEmpty ||
      _people.isNotEmpty ||
      _mail.isNotEmpty ||
      _disk.isNotEmpty;

  void _runSearch() {
    final q = _searchCtrl.text.trim();
    _generation++;
    final gen = _generation;
    final runRemote = q.length >= 2;

    setState(() {
      _query = q;
      _chats = q.isEmpty ? const [] : _searchChats(q);
      _people = const [];
      _mail = const [];
      _disk = const [];
      _diskTruncated = false;
      _isLoadingPeople = runRemote;
      _isLoadingMail = runRemote;
      _isLoadingDisk = runRemote;
    });

    if (!runRemote) return;

    UsersRepository.instance
        .getPage(q: q)
        .then((page) {
          if (!mounted || gen != _generation) return;
          setState(() {
            _people = page.data.take(8).toList(growable: false);
            _isLoadingPeople = false;
          });
        })
        .catchError((_) {
          if (!mounted || gen != _generation) return;
          setState(() => _isLoadingPeople = false);
        });

    MailRepository.instance
        .searchMessages(q)
        .then((page) {
          if (!mounted || gen != _generation) return;
          setState(() {
            _mail = page.results.take(8).toList(growable: false);
            _isLoadingMail = false;
          });
        })
        .catchError((_) {
          if (!mounted || gen != _generation) return;
          setState(() => _isLoadingMail = false);
        });

    DiskSearchService.instance
        .search(q, isCancelled: () => gen != _generation)
        .then((outcome) {
          if (!mounted || gen != _generation) return;
          setState(() {
            _disk = outcome.hits;
            _diskTruncated = outcome.truncated;
            _isLoadingDisk = false;
          });
        })
        .catchError((_) {
          if (!mounted || gen != _generation) return;
          setState(() => _isLoadingDisk = false);
        });
  }

  List<Chat> _searchChats(String q) {
    final query = q.toLowerCase();
    return ChatService.instance.chats
        .where((c) {
          if (c.title.toLowerCase().contains(query)) return true;
          if ((c.lastMessagePreview ?? '').toLowerCase().contains(query)) {
            return true;
          }
          return c.memberNames.any((n) => n.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoSearchTextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      placeholder: 'Люди, чаты, письма, файлы…',
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_query.isEmpty) {
      return const AppEmptyState(
        message: 'Введите имя, название чата, тему письма или файл',
        icon: CupertinoIcons.search,
      );
    }
    if (!_isBusy && !_hasAnyResult) {
      return const AppEmptyState(
        message: 'Ничего не найдено',
        icon: CupertinoIcons.search,
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_chats.isNotEmpty)
          _buildSection(context, 'Чаты', _chats.map(_buildChatTile).toList()),
        if (_isLoadingPeople || _people.isNotEmpty)
          _buildSection(
            context,
            'Люди',
            _isLoadingPeople && _people.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: AppLoadingIndicator(),
                    ),
                  ]
                : _people.map(_buildPersonTile).toList(),
          ),
        if (_isLoadingMail || _mail.isNotEmpty)
          _buildSection(
            context,
            'Почта',
            _isLoadingMail && _mail.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: AppLoadingIndicator(),
                    ),
                  ]
                : _mail.map(_buildMailTile).toList(),
          ),
        if (_isLoadingDisk || _disk.isNotEmpty)
          _buildSection(context, 'Диск', [
            if (_isLoadingDisk && _disk.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: AppLoadingIndicator(),
              )
            else
              ..._disk.map(_buildDiskTile),
            if (!_isLoadingDisk && _diskTruncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Text(
                  'Показаны первые результаты — уточните запрос',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
          ]),
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: _withDividers(context, tiles)),
          ),
        ],
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context, List<Widget> tiles) {
    final result = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        result.add(
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 56),
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        );
      }
      result.add(tiles[i]);
    }
    return result;
  }

  Widget _buildChatTile(Chat chat) {
    return CupertinoListTile(
      leading: ChatAvatar(chat: chat, radius: 18),
      title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: (chat.lastMessagePreview ?? '').isEmpty
          ? null
          : Text(
              chat.lastMessagePreview!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel,
      ),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      ),
    );
  }

  Widget _buildPersonTile(StaffUser user) {
    final subtitleParts = [
      user.position,
      user.department,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();

    return CupertinoListTile(
      leading: MemberAvatar(
        displayName: user.fullName,
        avatarUrl: user.avatarUrl,
        radius: 18,
      ),
      title: Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel,
      ),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => EmployeeDetailScreen(user: user)),
      ),
    );
  }

  Widget _buildMailTile(MailSearchResult result) {
    final message = result.message;
    final subtitleParts = [
      message.from,
      result.connectionName,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();

    return CupertinoListTile(
      leading: Icon(
        message.hasAttachments ? CupertinoIcons.paperclip : CupertinoIcons.mail,
        color: CupertinoColors.systemBlue,
      ),
      title: Text(
        message.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: message.isRead ? FontWeight.normal : FontWeight.w600,
        ),
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: message.date == null
          ? null
          : Text(
              DateFormat('d MMM', 'ru_RU').format(message.date!.toLocal()),
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.tertiaryLabel,
              ),
            ),
      onTap: () => _openMailMessage(result),
    );
  }

  Future<void> _openMailMessage(MailSearchResult result) async {
    final connection = MailConnection(
      id: result.connectionId,
      email: result.connectionName ?? '',
      name: result.connectionName,
    );

    // Открытие письма из поиска минует MailInboxScreen, где обычно
    // подгружается список папок для «Переместить в папку» — без него кнопка
    // молча скрывается в MailMessageScreen, поэтому подгружаем здесь.
    var folders = <MailFolder>[];
    try {
      folders = await MailRepository.instance.getMailboxes(result.connectionId);
    } catch (_) {
      // Письмо всё равно можно прочитать — просто без перемещения в папку.
    }
    if (!mounted) return;

    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => MailMessageScreen(
          connection: connection,
          messageId: result.message.id,
          initialMessage: result.message,
          folders: folders,
        ),
      ),
    );
  }

  Widget _buildDiskTile(DiskSearchHit hit) {
    return CupertinoListTile(
      leading: Icon(
        hit.isFolder ? CupertinoIcons.folder_fill : CupertinoIcons.doc_fill,
        color: hit.isFolder
            ? CupertinoColors.systemYellow
            : CupertinoColors.systemBlue,
      ),
      title: Text(hit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: !hit.isFolder && hit.size != null
          ? Text(_formatDiskSize(hit.size!))
          : null,
      trailing: const Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel,
      ),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => DiskScreen(
            path: hit.isFolder ? hit.path : hit.parentPath,
            title: hit.isFolder ? hit.name : null,
          ),
        ),
      ),
    );
  }

  static String _formatDiskSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}
