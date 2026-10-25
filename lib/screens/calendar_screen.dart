import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/app_theme.dart';
import '../models/bookings/create_booking_request.dart';
import '../models/bookings/user_booking.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/app_feedback.dart';
import '../utils/booking_time_utils.dart';
import '../utils/connector_link_join.dart';
import '../utils/ru_plural.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_network_image.dart';
import '../widgets/app_title_bar.dart';
import 'booking_detail_sheet.dart';
import 'bookings_screen.dart';
import 'create_booking_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  int? _userId;
  bool _isLoading = true;
  String? _error;
  final Map<DateTime, List<UserBooking>> _eventsByDay = {};

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _bootstrap();
  }

  /// `id` из ответа бэкенда (часто есть в `/user/get`, но может отсутствовать в кэше логина).
  static int? _parseUserId(Map<String, dynamic>? json) {
    if (json == null) return null;
    final raw = json['id'] ?? json['user_id'];
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  Future<int?> _resolveCurrentUserId() async {
    final storedId = _parseUserId(await AuthService.instance.getStoredUser());
    if (storedId != null) return storedId;
    try {
      final profile = await ProfileRepository.instance.getProfile();
      return _parseUserId(profile);
    } catch (_) {
      return null;
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = await _resolveCurrentUserId();
      if (userId == null) {
        throw ApiException(
          200,
          'Не удалось определить пользователя. Выйдите из аккаунта и войдите снова.',
        );
      }

      _userId = userId;
      await _loadMonth(_focusedDay);

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppFeedback.messageOf(e);
        _isLoading = false;
        _eventsByDay.clear();
      });
    }
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  DateTime _monthEnd(DateTime d) {
    final nextMonth = (d.month == 12)
        ? DateTime(d.year + 1, 1, 1)
        : DateTime(d.year, d.month + 1, 1);
    return nextMonth.subtract(const Duration(seconds: 1));
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _quickBook() async {
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
      await _createMeeting();
    } else {
      await Navigator.of(context).push<bool>(
        CupertinoPageRoute(
          builder: (context) => BookingsScreen(
            showAppBar: true,
            initialDate: _selectedDay ?? DateTime.now(),
          ),
        ),
      );
    }
    // Бронь/встреча могла быть создана на предыдущем экране — обновляем
    // месяц в любом случае, чтобы не тащить через несколько экранов bool-флаг.
    if (mounted) await _loadMonth(_focusedDay);
  }

  Future<void> _createMeeting() async {
    final now = DateTime.now();
    final day = _selectedDay ?? now;
    final start = BookingTimeUtils.isSameDay(day, now)
        ? now
        : DateTime(day.year, day.month, day.day, 9);

    await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (context) => CreateBookingScreen(
          modelType: CreateBookingRequest.meetingModelType,
          modelId: CreateBookingRequest.meetingModelId,
          initialStart: start,
          initialEnd: start.add(
            const Duration(minutes: BookingTimeUtils.slotMinutes),
          ),
        ),
      ),
    );
  }

  /// Номер последнего запроса месяца: при быстром листании ответ за
  /// пролистанный месяц может прийти позже и подменить события.
  int _monthRequest = 0;

  Future<void> _loadMonth(DateTime focusedDay) async {
    final userId = _userId;
    if (userId == null) return;
    final request = ++_monthRequest;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final start = _monthStart(focusedDay);
      final end = _monthEnd(focusedDay);
      final startSeconds = start.millisecondsSinceEpoch ~/ 1000;
      final endSeconds = end.millisecondsSinceEpoch ~/ 1000;

      final items = await BookingsRepository.instance.getBookingsByUserForRange(
        userId: userId,
        datetimeStartSeconds: startSeconds,
        datetimeEndSeconds: endSeconds,
      );

      final map = <DateTime, List<UserBooking>>{};
      for (final b in items) {
        final key = _dayKey(b.datetimeStart);
        (map[key] ??= <UserBooking>[]).add(b);
      }
      for (final list in map.values) {
        list.sort((a, b) => a.datetimeStart.compareTo(b.datetimeStart));
      }

      if (!mounted || request != _monthRequest) return;
      setState(() {
        _eventsByDay
          ..clear()
          ..addAll(map);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || request != _monthRequest) return;
      setState(() {
        _error = AppFeedback.messageOf(
          e,
          fallback: 'Не удалось загрузить события',
        );
        _eventsByDay.clear();
        _isLoading = false;
      });
    }
  }

  List<UserBooking> _eventsForDay(DateTime day) =>
      _eventsByDay[_dayKey(day)] ?? const [];

  /// Возвращает описание, если это ссылка на встречу (http/https), иначе null.
  String? _meetingLinkOrNull(String description) {
    if (!description.startsWith('http://') &&
        !description.startsWith('https://')) {
      return null;
    }
    return Uri.tryParse(description) != null ? description : null;
  }

  void _goToToday() {
    final now = DateTime.now();
    final sameMonth =
        _focusedDay.year == now.year && _focusedDay.month == now.month;
    setState(() {
      _selectedDay = now;
      _focusedDay = now;
    });
    if (!sameMonth) _loadMonth(now);
  }

  Widget _buildCalendarCard(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final weekend = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: AppGlass(
        borderRadius: BorderRadius.circular(26),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: TableCalendar<UserBooking>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            availableGestures: AvailableGestures.horizontalSwipe,
            locale: 'ru_RU',
            startingDayOfWeek: StartingDayOfWeek.monday,
            eventLoader: _eventsForDay,
            daysOfWeekHeight: 24,
            rowHeight: 48,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                color: secondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              weekendStyle: TextStyle(
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              markersMaxCount: 3,
              markerSize: 5,
              markerMargin: const EdgeInsets.symmetric(horizontal: 1),
              // Точки под кружком дня, а не поверх него.
              markersAutoAligned: false,
              markersOffset: const PositionedOffset(bottom: 3),
              markerDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              cellMargin: const EdgeInsets.fromLTRB(6, 2, 6, 10),
              defaultTextStyle: TextStyle(color: label, fontSize: 16),
              weekendTextStyle: TextStyle(color: weekend, fontSize: 16),
              todayDecoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              todayTextStyle: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              selectedDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: false,
              titleTextFormatter: (date, locale) =>
                  _capitalize(DateFormat('LLLL y', locale).format(date)),
              headerPadding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
              leftChevronMargin: EdgeInsets.zero,
              rightChevronMargin: const EdgeInsets.only(right: 4),
              leftChevronPadding: const EdgeInsets.all(8),
              rightChevronPadding: const EdgeInsets.all(8),
              leftChevronVisible: false,
              rightChevronVisible: false,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: label,
              ),
            ),
            onHeaderTapped: (_) => _goToToday(),
            onCalendarCreated: (controller) => _pageController = controller,
            onDaySelected: (selectedDay, focusedDay) {
              if (!isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
              _loadMonth(focusedDay);
            },
          ),
        ),
      ),
    );
  }

  PageController? _pageController;

  /// Стрелки месяца и «Сегодня» — поверх шапки календаря справа,
  /// стеклянными круглыми кнопками, как в «Календаре» iOS 26.
  Widget _buildMonthControls(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final now = DateTime.now();
    final isCurrentMonth =
        _focusedDay.year == now.year && _focusedDay.month == now.month;
    final isTodaySelected =
        _selectedDay != null && isSameDay(_selectedDay, now);

    Widget circle(IconData icon, VoidCallback onTap) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(34, 34),
        onPressed: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: label),
        ),
      );
    }

    return Positioned(
      top: 12,
      right: 26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCurrentMonth || !isTodaySelected) ...[
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 34),
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius: BorderRadius.circular(17),
              onPressed: _goToToday,
              child: Text(
                'Сегодня',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: label,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          circle(
            CupertinoIcons.chevron_left,
            () => _pageController?.previousPage(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
            ),
          ),
          const SizedBox(width: 6),
          circle(
            CupertinoIcons.chevron_right,
            () => _pageController?.nextPage(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openBooking(UserBooking b) async {
    final changed = await BookingDetailSheet.show(context, bookingId: b.id);
    if (changed == true && mounted) await _loadMonth(_focusedDay);
  }

  Widget _buildEventsList(BuildContext context) {
    if (_error != null) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: AppEmptyState(
            icon: CupertinoIcons.exclamationmark_circle,
            message: _error!,
            onRetry: _bootstrap,
          ),
        ),
      );
    }

    final selectedDay = _selectedDay;
    if (selectedDay == null) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 160,
          child: AppEmptyState(
            icon: CupertinoIcons.calendar,
            message: 'Выберите день',
          ),
        ),
      );
    }

    final items = _eventsForDay(selectedDay);
    final header = _capitalize(
      DateFormat('EEEE, d MMMM', 'ru_RU').format(selectedDay),
    );

    return SliverPadding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      sliver: SliverList.list(
        children: [
          AppGlassSectionLabel(
            items.isEmpty ? header : '$header · ${_eventsCount(items.length)}',
          ),
          if (items.isEmpty)
            _EmptyDayCard(isLoading: _isLoading, onAdd: _quickBook)
          else
            AppGlassSection(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: items
                  .map(
                    (b) => _EventTile(
                      booking: b,
                      meetingLinkOrNull: _meetingLinkOrNull,
                      onTap: () => _openBooking(b),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  static String _eventsCount(int n) =>
      '$n ${ruPlural(n, 'событие', 'события', 'событий')}';

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground.resolveFrom(context),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: label,
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: CustomScrollView(
                  slivers: [
                    AppSliverTitleBar(
                      title: const Text('Календарь'),
                      blur: blur,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: CupertinoActivityIndicator(),
                            ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            onPressed: _quickBook,
                            child: Icon(
                              CupertinoIcons.add_circled,
                              size: AppSliverTitleBar.iconSize,
                              color: label,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Stack(
                        children: [
                          _buildCalendarCard(context),
                          _buildMonthControls(context),
                        ],
                      ),
                    ),
                    _buildEventsList(context),
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

/// Пустой день — стеклянная карточка с быстрым добавлением, а не
/// просто надпись на фоне.
class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard({required this.isLoading, required this.onAdd});

  final bool isLoading;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
          child: Column(
            children: [
              Icon(CupertinoIcons.calendar, size: 30, color: secondary),
              const SizedBox(height: 8),
              Text(
                isLoading ? 'Загрузка…' : 'На этот день событий нет',
                style: TextStyle(fontSize: 15, color: secondary),
              ),
              const SizedBox(height: 14),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(18),
                onPressed: isLoading ? null : onAdd,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.plus,
                      size: 16,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Добавить',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
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

/// Событие дня: время столбиком слева, цветная полоса (серая — если
/// событие уже прошло), тема, объект и кнопка подключения.
class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.booking,
    required this.meetingLinkOrNull,
    required this.onTap,
  });

  final UserBooking booking;
  final String? Function(String) meetingLinkOrNull;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final tertiary = CupertinoColors.tertiaryLabel.resolveFrom(context);

    final description = booking.description?.trim() ?? '';
    final bookingLink = booking.link?.trim() ?? '';
    final meetingLink = bookingLink.isNotEmpty
        ? bookingLink
        : meetingLinkOrNull(description);
    // Если ссылка пришла отдельным полем (а не была текстом описания),
    // описание — самостоятельный текст и его тоже нужно показать.
    final hasSeparateDescription =
        description.isNotEmpty && description != meetingLink;
    final objectName = (booking.objectName ?? '').trim();
    final imageUrl = booking.objectImageUrl;
    // Сервер помечает is_passed уже после начала встречи, а опоздавшим
    // нужно подключаться до её окончания.
    final isOver = DateTime.now().isAfter(booking.datetimeEnd);
    final isNow = !isOver && DateTime.now().isAfter(booking.datetimeStart);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isOver
                      ? CupertinoColors.systemGrey3.resolveFrom(context)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (booking.isPrivate) ...[
                          Icon(
                            CupertinoIcons.lock_fill,
                            size: 13,
                            color: secondary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            booking.theme,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isOver ? secondary : label,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isNow
                          ? 'Сейчас · до ${BookingTimeUtils.formatHm(booking.datetimeEnd)}'
                          : '${BookingTimeUtils.formatHm(booking.datetimeStart)}'
                                ' – ${BookingTimeUtils.formatHm(booking.datetimeEnd)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isNow ? AppColors.primary : secondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (objectName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (imageUrl != null) ...[
                            AppNetworkImage(
                              url: imageUrl,
                              width: 18,
                              height: 18,
                              borderRadius: 5,
                              errorIcon: CupertinoIcons.location_solid,
                            ),
                            const SizedBox(width: 6),
                          ] else ...[
                            Icon(
                              CupertinoIcons.location_solid,
                              size: 13,
                              color: secondary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              objectName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: secondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (hasSeparateDescription) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                    ],
                    if (meetingLink != null && !isOver) ...[
                      const SizedBox(height: 8),
                      _JoinMeetingChip(url: meetingLink, isLive: isNow),
                    ],
                  ],
                ),
              ),
              Center(
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 15,
                  color: tertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinMeetingChip extends StatelessWidget {
  const _JoinMeetingChip({required this.url, this.isLive = false});

  final String url;

  /// Встреча уже идёт — кнопка залита, чтобы бросалась в глаза.
  final bool isLive;

  Future<void> _open(BuildContext context) => joinMeetingLink(context, url);

  @override
  Widget build(BuildContext context) {
    final foreground = isLive ? CupertinoColors.white : AppColors.primary;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: Size.zero,
      color: isLive
          ? AppColors.primary
          : AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      onPressed: () => _open(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.video_camera_solid, size: 15, color: foreground),
          const SizedBox(width: 6),
          Text(
            isLive ? 'Подключиться · идёт' : 'Подключиться',
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
