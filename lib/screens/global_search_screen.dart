import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/chat.dart';
import '../models/mail/mail_connection.dart';
import '../models/bookings/user_booking.dart';
import '../models/mail/mail_folder.dart';
import '../models/news_item.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/mail_repository.dart';
import '../repositories/news_repository.dart';
import '../repositories/users_repository.dart';
import '../services/chat_service.dart';
import '../services/disk_search_service.dart';
import '../utils/booking_time_utils.dart';
import '../utils/file_size_format.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/chat_avatar.dart';
import 'booking_detail_sheet.dart';
import 'chat_conversation_screen.dart';
import 'disk_screen.dart';
import 'employee_detail_screen.dart';
import 'mail_message_screen.dart';
import 'news_detail_screen.dart';

/// Сквозной поиск по людям, чатам, встречам, почте, новостям и «Диску».
///
/// Раньше поиск был размазан по отдельным экранам (почта, чаты, сотрудники,
/// создание группы) — свой собственный `CupertinoSearchTextField` в каждом,
/// без единой точки входа. Этот экран объединяет их: один запрос
/// параллельно уходит в 6 независимых источников (чаты — локально по уже
/// загруженному списку, люди — `/user/filter`, встречи — `/booking/filter`,
/// почта — `/mail/search`, новости — `/dashboard/news/all?q=`,
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

  bool _isLoadingBookings = false;
  List<UserBooking> _bookings = const [];

  bool _isLoadingMail = false;
  List<MailSearchResult> _mail = const [];

  bool _isLoadingNews = false;
  List<NewsItem> _news = const [];

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

  bool get _isBusy =>
      _isLoadingPeople ||
      _isLoadingBookings ||
      _isLoadingMail ||
      _isLoadingNews ||
      _isLoadingDisk;

  bool get _hasAnyResult =>
      _chats.isNotEmpty ||
      _people.isNotEmpty ||
      _bookings.isNotEmpty ||
      _mail.isNotEmpty ||
      _news.isNotEmpty ||
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
      _bookings = const [];
      _mail = const [];
      _news = const [];
      _disk = const [];
      _diskTruncated = false;
      _isLoadingPeople = runRemote;
      _isLoadingBookings = runRemote;
      _isLoadingMail = runRemote;
      _isLoadingNews = runRemote;
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

    final now = DateTime.now();
    BookingsRepository.instance
        .searchBookings(q, from: now.subtract(const Duration(days: 90)))
        .then((items) {
          if (!mounted || gen != _generation) return;
          // Сначала ближайшие предстоящие, затем прошедшие — от свежих.
          final upcoming =
              items.where((b) => b.datetimeEnd.isAfter(now)).toList()
                ..sort((a, b) => a.datetimeStart.compareTo(b.datetimeStart));
          final past = items.where((b) => !b.datetimeEnd.isAfter(now)).toList()
            ..sort((a, b) => b.datetimeStart.compareTo(a.datetimeStart));
          setState(() {
            _bookings = [...upcoming, ...past].take(8).toList(growable: false);
            _isLoadingBookings = false;
          });
        })
        .catchError((_) {
          if (!mounted || gen != _generation) return;
          setState(() => _isLoadingBookings = false);
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

    NewsRepository.instance
        .search(q)
        .then((items) {
          if (!mounted || gen != _generation) return;
          setState(() {
            _news = items;
            _isLoadingNews = false;
          });
        })
        .catchError((_) {
          if (!mounted || gen != _generation) return;
          setState(() => _isLoadingNews = false);
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
      backgroundColor: AppColors.groupedBackground.resolveFrom(context),
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
                      placeholder: 'Люди, чаты, встречи, письма, новости…',
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
        message: 'Введите имя, чат, тему встречи или письма, новость, файл',
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
        if (_isLoadingBookings || _bookings.isNotEmpty)
          _buildSection(
            context,
            'Встречи',
            _isLoadingBookings && _bookings.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: AppLoadingIndicator(),
                    ),
                  ]
                : _bookings.map(_buildBookingTile).toList(),
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
        if (_isLoadingNews || _news.isNotEmpty)
          _buildSection(
            context,
            'Новости',
            _isLoadingNews && _news.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: AppLoadingIndicator(),
                    ),
                  ]
                : _news.map(_buildNewsTile).toList(),
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
              color: AppColors.groupedSurface.resolveFrom(context),
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
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
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
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
      ),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => EmployeeDetailScreen(user: user)),
      ),
    );
  }

  Widget _buildBookingTile(UserBooking booking) {
    final isOver = DateTime.now().isAfter(booking.datetimeEnd);
    final when =
        '${DateFormat('d MMM', 'ru_RU').format(booking.datetimeStart)}, '
        '${BookingTimeUtils.formatHm(booking.datetimeStart)}–'
        '${BookingTimeUtils.formatHm(booking.datetimeEnd)}';
    final place = (booking.objectName ?? '').trim();

    return CupertinoListTile(
      leading: Icon(
        CupertinoIcons.calendar,
        color: isOver
            ? CupertinoColors.systemGrey.resolveFrom(context)
            : CupertinoColors.systemOrange.resolveFrom(context),
      ),
      title: Text(booking.theme, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        place.isEmpty ? when : '$when · $place',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
      ),
      onTap: () => BookingDetailSheet.show(context, bookingId: booking.id),
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
        color: CupertinoColors.systemBlue.resolveFrom(context),
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
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
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

  Widget _buildNewsTile(NewsItem news) {
    final author = news.author?.fullName.trim() ?? '';
    final snippet = news.content.replaceAll(RegExp(r'\s+'), ' ').trim();

    return CupertinoListTile(
      leading: Icon(
        CupertinoIcons.news,
        color: CupertinoColors.systemIndigo.resolveFrom(context),
      ),
      title: Text(news.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: author.isEmpty && snippet.isEmpty
          ? null
          : Text(
              author.isEmpty ? snippet : author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Text(
        DateFormat('d MMM', 'ru_RU').format(news.date.toLocal()),
        style: TextStyle(
          fontSize: 12,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      ),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => NewsDetailScreen(news: news)),
      ),
    );
  }

  Widget _buildDiskTile(DiskSearchHit hit) {
    return CupertinoListTile(
      leading: Icon(
        hit.isFolder ? CupertinoIcons.folder_fill : CupertinoIcons.doc_fill,
        color: hit.isFolder
            ? CupertinoColors.systemBlue.resolveFrom(context)
            : CupertinoColors.systemGrey.resolveFrom(context),
      ),
      title: Text(hit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: !hit.isFolder && hit.size != null
          ? Text(formatFileSize(hit.size!))
          : null,
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
      ),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => DiskScreen(
            path: hit.isFolder ? hit.path : hit.parentPath,
            title: hit.isFolder ? hit.name : null,
            highlightName: hit.isFolder ? null : hit.name,
          ),
        ),
      ),
    );
  }
}
