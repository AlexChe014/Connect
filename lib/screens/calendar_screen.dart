import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_icons.dart';
import '../models/bookings/user_booking.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_network_image.dart';
import 'booking_detail_sheet.dart';
import 'bookings_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  int? _userId;
  bool _isLoading = false;
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
        throw Exception(
          'Не удалось определить id текущего пользователя. Проверьте авторизацию и ответ профиля (/user/get).',
        );
      }

      _userId = userId;
      await _loadMonth(_focusedDay);

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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
    await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (context) => BookingsScreen(
          showAppBar: true,
          initialDate: _selectedDay ?? DateTime.now(),
        ),
      ),
    );
    // Бронь могла быть создана на предыдущем экране — обновляем месяц
    // в любом случае, чтобы не тащить через несколько экранов bool-флаг.
    if (mounted) await _loadMonth(_focusedDay);
  }

  Future<void> _loadMonth(DateTime focusedDay) async {
    final userId = _userId;
    if (userId == null) return;

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

      if (!mounted) return;
      setState(() {
        _eventsByDay
          ..clear()
          ..addAll(map);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _eventsByDay.clear();
        _isLoading = false;
      });
    }
  }

  List<UserBooking> _eventsForDay(DateTime day) =>
      _eventsByDay[_dayKey(day)] ?? const [];

  String _formatHm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Возвращает описание, если это ссылка на встречу (http/https), иначе null.
  String? _meetingLinkOrNull(String description) {
    if (!description.startsWith('http://') &&
        !description.startsWith('https://')) {
      return null;
    }
    return Uri.tryParse(description) != null ? description : null;
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 16, color: CupertinoColors.white),
    );
  }

  Widget _buildCalendarCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TableCalendar<UserBooking>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          calendarFormat: CalendarFormat.month,
          locale: 'ru_RU',
          startingDayOfWeek: StartingDayOfWeek.monday,
          eventLoader: _eventsForDay,
          daysOfWeekHeight: 24,
          rowHeight: 40,
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            weekendStyle: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            markersMaxCount: 3,
            markerSize: 5,
            markerMargin: const EdgeInsets.only(top: 3),
            markerDecoration: const BoxDecoration(
              color: CupertinoColors.activeBlue,
              shape: BoxShape.circle,
            ),
            defaultTextStyle: TextStyle(
              color: CupertinoColors.label.resolveFrom(context),
            ),
            weekendTextStyle: TextStyle(
              color: CupertinoColors.label.resolveFrom(context),
            ),
            todayDecoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: CupertinoColors.activeBlue, width: 1.5),
            ),
            todayTextStyle: const TextStyle(
              color: CupertinoColors.activeBlue,
              fontWeight: FontWeight.w700,
            ),
            selectedDecoration: const BoxDecoration(
              color: CupertinoColors.activeBlue,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: const TextStyle(
              color: CupertinoColors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            leftChevronIcon: Icon(
              CupertinoIcons.chevron_left,
              size: 20,
              color: cs.primary,
            ),
            rightChevronIcon: Icon(
              CupertinoIcons.chevron_right,
              size: 20,
              color: cs.primary,
            ),
            titleTextStyle: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
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
    );
  }

  Widget _buildEventsList(BuildContext context) {
    if (_error != null) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: AppEmptyState(
            icon: Icons.error_outline,
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
          child: AppEmptyState(icon: AppIcons.date, message: 'Выберите день'),
        ),
      );
    }

    final items = _eventsForDay(selectedDay);
    final header = _capitalize(
      DateFormat('EEEE, d MMMM', 'ru_RU').format(selectedDay),
    );

    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: SizedBox(
            height: 140,
            child: AppEmptyState(
              icon: AppIcons.date,
              message: 'На этот день событий нет',
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      sliver: SliverList.list(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              header,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            children: items
                .map(
                  (b) => _EventTile(
                    booking: b,
                    formatHm: _formatHm,
                    meetingLinkOrNull: _meetingLinkOrNull,
                    iconBadge: _iconBadge,
                    onTap: () async {
                      final changed = await BookingDetailSheet.show(
                        context,
                        bookingId: b.id,
                      );
                      if (changed == true && mounted) {
                        await _loadMonth(_focusedDay);
                      }
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                CupertinoSliverNavigationBar(
                  largeTitle: const Text('Календарь'),
                  backgroundColor: CupertinoColors.systemGroupedBackground
                      .withValues(alpha: 0.9),
                  border: null,
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: _quickBook,
                    child: const Icon(
                      CupertinoIcons.calendar_badge_plus,
                      size: 26,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildCalendarCard(context)),
                _buildEventsList(context),
              ],
            ),
            if (_isLoading)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: CupertinoColors.systemGroupedBackground
                        .resolveFrom(context)
                        .withValues(alpha: 0.5),
                    alignment: Alignment.center,
                    child: const CupertinoActivityIndicator(radius: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.booking,
    required this.formatHm,
    required this.meetingLinkOrNull,
    required this.iconBadge,
    required this.onTap,
  });

  final UserBooking booking;
  final String Function(DateTime) formatHm;
  final String? Function(String) meetingLinkOrNull;
  final Widget Function(IconData, Color) iconBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      '${formatHm(booking.datetimeStart)}—${formatHm(booking.datetimeEnd)}',
      if ((booking.objectName ?? '').trim().isNotEmpty)
        booking.objectName!.trim(),
      if (booking.isPrivate) 'Приватное',
    ];

    final description = booking.description?.trim() ?? '';
    final bookingLink = booking.link?.trim() ?? '';
    final meetingLink = bookingLink.isNotEmpty
        ? bookingLink
        : meetingLinkOrNull(description);
    // Если ссылка пришла отдельным полем (а не была текстом описания),
    // описание — самостоятельный текст и его тоже нужно показать.
    final hasSeparateDescription =
        description.isNotEmpty && description != meetingLink;
    final imageUrl = booking.objectImageUrl;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              imageUrl != null
                  ? AppNetworkImage(
                      url: imageUrl,
                      width: 29,
                      height: 29,
                      borderRadius: 7,
                      errorIcon: AppIcons.locationPin,
                    )
                  : iconBadge(
                      CupertinoIcons.location_solid,
                      CupertinoColors.activeBlue,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.theme,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitleParts.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                    if (meetingLink != null) ...[
                      const SizedBox(height: 8),
                      _JoinMeetingChip(
                        url: meetingLink,
                        isPassed: booking.isPassed,
                      ),
                    ],
                    if (hasSeparateDescription) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
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
  const _JoinMeetingChip({required this.url, this.isPassed = false});

  final String url;
  final bool isPassed;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final color = isPassed
        ? CupertinoColors.systemGrey
        : CupertinoColors.activeBlue;

    return GestureDetector(
      onTap: isPassed ? null : _open,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.video_camera_solid, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              'Подключиться',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
