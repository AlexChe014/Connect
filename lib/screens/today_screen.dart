import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/bonus_program/point_operation.dart';
import '../models/bookings/create_booking_request.dart';
import '../models/bookings/user_booking.dart';
import '../repositories/bonus_program_repository.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../services/document_pending_service.dart';
import '../services/notification_unread_service.dart';
import '../services/survey_pending_service.dart';
import '../utils/booking_time_utils.dart';
import '../utils/connector_link_join.dart';
import '../utils/media_url_utils.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/chat_avatar.dart';
import 'bonus_program_screen.dart';
import 'booking_detail_sheet.dart';
import 'bookings_screen.dart';
import 'calendar_screen.dart';
import 'create_booking_screen.dart';
import 'documents_signing_screen.dart';
import 'global_search_screen.dart';
import 'news_feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'surveys_screen.dart';

/// Вкладка «Главная»: сводка дня над лентой — ближайшая встреча, что ждёт
/// действия, свежие баллы, а ниже вся лента целиком. Ничего не создаёт
/// сам, только собирает данные разделов; каждый блок грузится отдельно
/// и прячется, если в нём пусто.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.openNewsId});

  /// Новость из пуша — открывает лента.
  final String? openNewsId;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  /// За сколько до начала кнопка «Подключиться» становится главной.
  static const _joinLead = Duration(minutes: 10);

  /// Насколько вперёд ищем «следующее» событие для пустого дня.
  static const _lookAheadDays = 14;

  /// Сколько встреч после ближайшей показываем строками.
  static const _scheduleLimit = 3;

  /// Сколько капсула баллов показывает «+N» вместо баланса.
  static const _bonusFreshness = Duration(hours: 48);

  Map<String, dynamic>? _profile;
  int? _userId;

  List<UserBooking> _events = const [];
  bool _eventsLoading = true;
  bool _eventsFailed = false;

  PointOperation? _recentCredit;
  int? _points;

  Timer? _clock;
  int _eventsRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final l in _badgeSources) {
      l.addListener(_onBadgesChanged);
    }
    // «Через 25 мин» и момент, когда загорается «Подключиться».
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) setState(() {});
    });
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final l in _badgeSources) {
      l.removeListener(_onBadgesChanged);
    }
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Утром открыли вчерашнее приложение — день уже другой.
    if (state == AppLifecycleState.resumed) unawaited(_loadEvents());
  }

  List<Listenable> get _badgeSources => [
    DocumentPendingService.instance,
    SurveyPendingService.instance,
    NotificationUnreadService.instance,
  ];

  void _onBadgesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAll() =>
      Future.wait([_loadProfile(), _loadEvents(), _loadBonus()]);

  /// Лента обновляется сама — здесь только блоки над ней.
  Future<void> _refresh() async {
    unawaited(SurveyPendingService.instance.refreshQuietly());
    unawaited(NotificationUnreadService.instance.refresh());
    unawaited(DocumentPendingService.instance.refreshKnownServices());
    await _loadAll();
  }

  static int? _parseUserId(Map<String, dynamic>? json) {
    final raw = json?['id'] ?? json?['user_id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  Future<void> _loadProfile() async {
    final stored = await AuthService.instance.getStoredUser();
    if (mounted && stored != null) {
      setState(() => _profile = stored);
      _userId ??= _parseUserId(stored);
    }
    try {
      final api = await ProfileRepository.instance.getProfile();
      if (!mounted || api.isEmpty) return;
      setState(() => _profile = api);
      _userId ??= _parseUserId(api);
    } catch (_) {
      // Остаёмся на закэшированном профиле.
    }
  }

  Future<void> _loadEvents() async {
    final request = ++_eventsRequest;
    if (_events.isEmpty) setState(() => _eventsLoading = true);
    try {
      if (_userId == null) await _loadProfile();
      final userId = _userId;
      if (userId == null) throw StateError('no user id');

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: _lookAheadDays));
      final items = await BookingsRepository.instance.getBookingsByUserForRange(
        userId: userId,
        datetimeStartSeconds: start.millisecondsSinceEpoch ~/ 1000,
        datetimeEndSeconds: end.millisecondsSinceEpoch ~/ 1000,
      );
      items.sort((a, b) => a.datetimeStart.compareTo(b.datetimeStart));
      if (!mounted || request != _eventsRequest) return;
      setState(() {
        _events = items;
        _eventsLoading = false;
        _eventsFailed = false;
      });
    } catch (_) {
      if (!mounted || request != _eventsRequest) return;
      setState(() {
        _eventsLoading = false;
        _eventsFailed = _events.isEmpty;
      });
    }
  }

  /// Баланс для капсулы баллов и свежее начисление, если оно было за
  /// [_bonusFreshness]. Нет бонусной программы — нет и капсулы.
  Future<void> _loadBonus() async {
    try {
      final balance = await BonusProgramRepository.instance.getBalance();
      if (mounted) setState(() => _points = balance.points);
    } catch (_) {
      if (mounted) setState(() => _points = null);
      return;
    }
    try {
      final history = await BonusProgramRepository.instance.getHistory();
      final cutoff = DateTime.now().subtract(_bonusFreshness);
      PointOperation? credit;
      for (final op in history.data) {
        final at = op.completedAt ?? op.createdAt;
        if (op.isCredit && op.pointsDelta != 0 && at != null) {
          if (at.toLocal().isAfter(cutoff)) credit = op;
          break;
        }
      }
      if (mounted) setState(() => _recentCredit = credit);
    } catch (_) {}
  }

  // ── События ─────────────────────────────────────────────────────────

  List<UserBooking> get _todayEvents {
    final now = DateTime.now();
    return _events
        .where((e) => BookingTimeUtils.isSameDay(e.datetimeStart, now))
        .toList();
  }

  /// Сегодняшние встречи, которые ещё не закончились.
  List<UserBooking> get _upcomingToday {
    final now = DateTime.now();
    return _todayEvents.where((e) => now.isBefore(e.datetimeEnd)).toList();
  }

  /// Первое событие после сегодняшнего дня — подсказка для пустого дня.
  UserBooking? get _nextAfterToday {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    for (final e in _events) {
      if (!e.datetimeStart.isBefore(tomorrow)) return e;
    }
    return null;
  }

  static String? _meetingLink(UserBooking b) {
    final link = b.link?.trim() ?? '';
    if (link.isNotEmpty) return link;
    final description = b.description?.trim() ?? '';
    if (description.startsWith('http://') ||
        description.startsWith('https://')) {
      return Uri.tryParse(description) != null ? description : null;
    }
    return null;
  }

  Future<void> _openBooking(UserBooking b) async {
    final changed = await BookingDetailSheet.show(context, bookingId: b.id);
    if (changed == true && mounted) await _loadEvents();
  }

  // ── Навигация ───────────────────────────────────────────────────────

  Future<void> _open(Widget screen) {
    return Navigator.of(
      context,
    ).push<void>(CupertinoPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openProfile() async {
    await _open(const ProfileScreen());
    if (mounted) unawaited(_loadProfile());
  }

  Future<void> _openCalendar() async {
    await _open(const CalendarScreen());
    if (mounted) await _loadEvents();
  }

  /// «＋» в пустом дне — то же меню, что в календаре.
  Future<void> _addEvent() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Новое событие'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'meeting'),
            child: const Text('Создать встречу'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'object'),
            child: const Text('Забронировать объект'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'meeting') {
      final start = DateTime.now();
      await _open(
        CreateBookingScreen(
          modelType: CreateBookingRequest.meetingModelType,
          modelId: CreateBookingRequest.meetingModelId,
          initialStart: start,
          initialEnd: start.add(
            const Duration(minutes: BookingTimeUtils.slotMinutes),
          ),
        ),
      );
    } else {
      await _open(const BookingsScreen(showAppBar: true));
    }
    if (mounted) await _loadEvents();
  }

  // ── Сборка ──────────────────────────────────────────────────────────

  String get _greeting {
    final hour = DateTime.now().hour;
    final hello = switch (hour) {
      >= 5 && < 12 => 'Доброе утро',
      >= 12 && < 17 => 'Добрый день',
      >= 17 && < 23 => 'Добрый вечер',
      _ => 'Доброй ночи',
    };
    final name = (_profile?['name'] as String?)?.trim() ?? '';
    return name.isEmpty ? hello : '$hello, $name';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _buildGreeting(BuildContext context) {
    final date = _capitalize(
      DateFormat('EEEE, d MMMM', 'ru_RU').format(DateTime.now()),
    );
    final bonus = _bonusChip(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _greeting,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          if (bonus != null) ...[const SizedBox(width: 12), bonus],
        ],
      ),
    );
  }

  /// Ближайшая встреча крупной карточкой и до трёх следующих строками;
  /// если сегодня больше ничего нет — одна строка с подсказкой.
  List<Widget> _buildEventsBlock(BuildContext context) {
    if (_eventsLoading) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: AppSkeletonBox(height: 72, borderRadius: 22),
        ),
      ];
    }
    if (_eventsFailed) {
      return [
        AppGlassSection(
          children: [
            CupertinoListTile(
              leading: AppIconBadge(
                icon: CupertinoIcons.calendar,
                color: CupertinoColors.systemGrey.resolveFrom(context),
              ),
              title: const Text('Не удалось загрузить расписание'),
              trailing: const Text(
                'Повторить',
                style: TextStyle(color: AppColors.primary),
              ),
              onTap: _loadEvents,
            ),
          ],
        ),
      ];
    }

    final upcoming = _upcomingToday;
    if (upcoming.isEmpty) {
      return [
        _NoMeetingsCard(
          dayIsOver: _todayEvents.isNotEmpty,
          next: _nextAfterToday,
          onOpenNext: _openBooking,
          onOpenCalendar: _openCalendar,
          onAdd: _addEvent,
        ),
      ];
    }

    final featured = upcoming.first;
    final rest = upcoming.skip(1).toList();
    final hidden = rest.length - _scheduleLimit;

    return [
      const AppGlassSectionLabel('Следующее'),
      _FeaturedEventCard(
        booking: featured,
        meetingLink: _meetingLink(featured),
        joinLead: _joinLead,
        onTap: () => _openBooking(featured),
      ),
      if (rest.isNotEmpty)
        AppGlassSection(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          children: [
            for (final b in rest.take(_scheduleLimit))
              _ScheduleRow(booking: b, onTap: () => _openBooking(b)),
            if (hidden > 0)
              CupertinoListTile(
                title: Text(
                  'Ещё $hidden',
                  style: const TextStyle(color: AppColors.primary),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: _openCalendar,
              ),
          ],
        ),
    ];
  }

  /// «Ждут вас» — капсулы в одну строку, только непустые. Опросы первыми:
  /// бывают редко, но у них есть срок. Чатов и почты нет — их счётчики
  /// и так на вкладках нижнего меню. Баллы — справа от приветствия.
  List<Widget> _buildPendingBlock(BuildContext context) {
    _PendingChip? counter(
      IconData icon,
      Color color,
      String label,
      int count,
      Widget screen,
    ) {
      if (count <= 0) return null;
      return _PendingChip(
        icon: icon,
        color: color,
        value: count > 99 ? '99+' : '$count',
        label: label,
        onTap: () => _open(screen),
      );
    }

    final pending = [
      counter(
        CupertinoIcons.chart_bar_square_fill,
        CupertinoColors.systemPurple.resolveFrom(context),
        'Опросы',
        SurveyPendingService.instance.pendingCount,
        const SurveysScreen(),
      ),
      counter(
        CupertinoIcons.signature,
        CupertinoColors.systemOrange.resolveFrom(context),
        'Подпись',
        DocumentPendingService.instance.totalCount,
        const DocumentsSigningScreen(),
      ),
      counter(
        CupertinoIcons.bell_fill,
        CupertinoColors.systemRed.resolveFrom(context),
        'Уведомления',
        NotificationUnreadService.instance.unreadCount,
        const NotificationsScreen(),
      ),
    ].nonNulls.toList();

    // Нечего делать — нет и ряда: пустота сама говорит «всё разобрано».
    if (pending.isEmpty) return const [SizedBox(height: 8)];
    final items = pending;

    return [
      const AppGlassSectionLabel('Ждут вас'),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // Место под тень капсул, иначе её срежет край списка.
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          clipBehavior: Clip.none,
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) => Center(child: items[index]),
        ),
      ),
    ];
  }

  /// Баланс баллов, а после свежего начисления — «+50 баллов».
  /// Нет бонусной программы — нет и капсулы.
  Widget? _bonusChip(BuildContext context) {
    final points = _points;
    if (points == null) return null;
    final credit = _recentCredit;
    final shown = credit != null ? credit.pointsDelta.abs() : points;
    return _BonusPill(
      value: credit != null
          ? '+${NumberFormat.decimalPattern('ru_RU').format(shown)}'
          : NumberFormat.decimalPattern('ru_RU').format(shown),
      onTap: () async {
        await _open(const BonusProgramScreen());
        if (mounted) unawaited(_loadBonus());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final name = userDisplayNameFromJson(_profile ?? const {});

    return NewsFeedScreen(
      title: 'Главная',
      openNewsId: widget.openNewsId,
      onRefresh: _refresh,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => _open(const GlobalSearchScreen()),
            child: Icon(
              CupertinoIcons.search,
              size: AppSliverTitleBar.iconSize,
              color: label,
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _openProfile,
            child: MemberAvatar(
              displayName: name,
              avatarUrl: MediaUrlUtils.normalizeFirstUrl(_profile?['media']),
              radius: 16,
            ),
          ),
        ],
      ),
      headerSlivers: [
        SliverList.list(
          children: [
            _buildGreeting(context),
            ..._buildEventsBlock(context),
            ..._buildPendingBlock(context),
            const SizedBox(height: 4),
          ],
        ),
      ],
    );
  }
}

/// Идущая или ближайшая встреча: тема, время, место и «Подключиться».
/// Кнопка залита синим за [joinLead] до начала и пока встреча идёт.
class _FeaturedEventCard extends StatelessWidget {
  const _FeaturedEventCard({
    required this.booking,
    required this.meetingLink,
    required this.joinLead,
    required this.onTap,
  });

  final UserBooking booking;
  final String? meetingLink;
  final Duration joinLead;
  final VoidCallback onTap;

  String _relative(DateTime now) {
    if (now.isAfter(booking.datetimeStart)) {
      return 'идёт · до ${BookingTimeUtils.formatHm(booking.datetimeEnd)}';
    }
    final minutes = booking.datetimeStart.difference(now).inMinutes + 1;
    if (minutes < 60) return 'через $minutes мин';
    final hours = minutes ~/ 60;
    if (hours < 3) {
      final rest = minutes % 60;
      return rest == 0 ? 'через $hours ч' : 'через $hours ч $rest мин';
    }
    return 'в ${BookingTimeUtils.formatHm(booking.datetimeStart)}';
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final now = DateTime.now();
    final isLive = now.isAfter(booking.datetimeStart);
    final joinSoon =
        isLive || booking.datetimeStart.difference(now) <= joinLead;
    final link = meetingLink;
    final objectName = (booking.objectName ?? '').trim();
    final details = [
      '${BookingTimeUtils.formatHm(booking.datetimeStart)}'
          '–${BookingTimeUtils.formatHm(booking.datetimeEnd)}',
      if (objectName.isNotEmpty) objectName,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIconBadge(
                      icon: link != null
                          ? CupertinoIcons.video_camera_solid
                          : CupertinoIcons.calendar,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        booking.theme,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relative(now),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: joinSoon ? AppColors.primary : secondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 42),
                  child: Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: secondary),
                  ),
                ),
                if (link != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      minimumSize: Size.zero,
                      borderRadius: BorderRadius.circular(20),
                      color: joinSoon
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.12),
                      onPressed: () => joinMeetingLink(context, link),
                      child: Text(
                        'Подключиться',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: joinSoon
                              ? CupertinoColors.white
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Пустой день: одна строка вместо блоков, подсказка, что дальше, и «＋».
class _NoMeetingsCard extends StatelessWidget {
  const _NoMeetingsCard({
    required this.dayIsOver,
    required this.next,
    required this.onOpenNext,
    required this.onOpenCalendar,
    required this.onAdd,
  });

  /// Встречи сегодня были, но уже закончились.
  final bool dayIsOver;
  final UserBooking? next;
  final ValueChanged<UserBooking> onOpenNext;
  final VoidCallback onOpenCalendar;
  final VoidCallback onAdd;

  static String _when(DateTime start) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final time = BookingTimeUtils.formatHm(start);
    if (BookingTimeUtils.isSameDay(start, tomorrow)) return 'Завтра в $time';
    final day = DateFormat('EEEE, d MMMM', 'ru_RU').format(start);
    return '${day[0].toUpperCase()}${day.substring(1)}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final next = this.next;
    return AppGlassSection(
      children: [
        CupertinoListTile(
          leading: AppIconBadge(
            icon: dayIsOver
                ? CupertinoIcons.moon_stars_fill
                : CupertinoIcons.sun_max_fill,
            color: dayIsOver
                ? CupertinoColors.systemIndigo.resolveFrom(context)
                : CupertinoColors.systemOrange.resolveFrom(context),
          ),
          title: Text(
            dayIsOver ? 'Встречи на сегодня закончились' : 'Сегодня без встреч',
          ),
          subtitle: next != null
              ? Text(
                  '${_when(next.datetimeStart)} — ${next.theme}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: onAdd,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.plus,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
          onTap: next != null ? () => onOpenNext(next) : onOpenCalendar,
        ),
      ],
    );
  }
}

/// Строка «дальше сегодня»: время слева, тема и место.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.booking, required this.onTap});

  final UserBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final objectName = (booking.objectName ?? '').trim();
    return CupertinoListTile(
      leadingSize: 44,
      leading: Text(
        BookingTimeUtils.formatHm(booking.datetimeStart),
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      title: Text(booking.theme),
      subtitle: objectName.isNotEmpty
          ? Text(objectName, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}

/// Баллы у приветствия: подарок и число на мягкой подложке, без стекла —
/// чтобы не спорить с карточкой встречи.
class _BonusPill extends StatelessWidget {
  const _BonusPill({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pink = CupertinoColors.systemPink.resolveFrom(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
        decoration: BoxDecoration(
          color: pink.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.gift_fill, size: 16, color: pink),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label.resolveFrom(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Капсула «Ждут вас»: цветная иконка, число, подпись.
class _PendingChip extends StatelessWidget {
  const _PendingChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppGlass(
      borderRadius: BorderRadius.circular(19),
      shadows: AppGlass.controlShadow,
      child: CupertinoButton(
        padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
        minimumSize: const Size(0, 38),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
