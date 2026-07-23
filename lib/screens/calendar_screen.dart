import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/app_icons.dart';
import '../models/bookings/user_booking.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import 'booking_detail_sheet.dart';

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
    final nextMonth = (d.month == 12) ? DateTime(d.year + 1, 1, 1) : DateTime(d.year, d.month + 1, 1);
    return nextMonth.subtract(const Duration(seconds: 1));
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

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

  List<UserBooking> _eventsForDay(DateTime day) => _eventsByDay[_dayKey(day)] ?? const [];

  String _formatHm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildBottom() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _bootstrap,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedDay == null) {
      return const Center(child: Text('Выберите день'));
    }

    final items = _eventsForDay(_selectedDay!);
    if (items.isEmpty) {
      return const Center(child: Text('На этот день событий нет'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final b = items[index];
        final title = b.theme;
        final subtitleParts = <String>[
          '${_formatHm(b.datetimeStart)}—${_formatHm(b.datetimeEnd)}',
          if ((b.objectName ?? '').trim().isNotEmpty) b.objectName!.trim(),
          if (b.isPrivate) 'Приватное',
        ];

        final imageUrl = b.objectImageUrl;
        final cs = Theme.of(context).colorScheme;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              final changed = await BookingDetailSheet.show(
                context,
                bookingId: b.id,
              );
              if (changed == true && mounted) {
                await _loadMonth(_focusedDay);
              }
            },
            child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: cs.primaryContainer,
                              child: AppIcon(
                                AppIcons.locationPin,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          )
                        : ColoredBox(
                            color: cs.primaryContainer,
                            child: AppIcon(
                              AppIcons.locationPin,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitleParts.join(' • '),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      if ((b.description ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          b.description!.trim(),
                          style: Theme.of(context).textTheme.bodyMedium,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Календарь'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          TableCalendar<UserBooking>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            locale: 'ru_RU',
            startingDayOfWeek: StartingDayOfWeek.monday,
            eventLoader: _eventsForDay,
            calendarStyle: CalendarStyle(
              markersMaxCount: 3,
              markerSize: 7,
              markerDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              todayDecoration: const BoxDecoration(),
              todayTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              selectedDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
              selectedTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
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
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildBottom()),
                if (_isLoading)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
