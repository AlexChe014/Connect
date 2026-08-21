import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/bookings/create_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/videoconference_repository.dart';
import '../services/api_client.dart';
import '../utils/booking_time_utils.dart';
import '../widgets/booking_pickers.dart';
import '../widgets/selected_staff_field.dart';

/// Планирование видеовстречи как записи Booking (без физического объекта).
class ScheduleVideoMeetingScreen extends StatefulWidget {
  const ScheduleVideoMeetingScreen({super.key});

  @override
  State<ScheduleVideoMeetingScreen> createState() =>
      _ScheduleVideoMeetingScreenState();
}

class _ScheduleVideoMeetingScreenState
    extends State<ScheduleVideoMeetingScreen> {
  final _themeController = TextEditingController();
  final _descriptionController = TextEditingController();

  late DateTime _bookingDate;
  late int _startSlotIndex;
  late int _endSlotIndex;

  List<StaffUser> _participants = [];
  bool _isSubmitting = false;
  String? _themeError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _bookingDate = BookingTimeUtils.startOfDay(now);
    final slots = BookingTimeUtils.slotsForDate(_bookingDate);
    _startSlotIndex = BookingTimeUtils.nearestSlotIndex(
      slots,
      now.add(const Duration(minutes: BookingTimeUtils.slotMinutes)),
      floorToPrevious: false,
    ).clamp(
      BookingTimeUtils.minStartIndex(slots, _bookingDate),
      slots.length - 2,
    );
    _endSlotIndex = (_startSlotIndex + 2).clamp(0, slots.length - 1);
  }

  @override
  void dispose() {
    _themeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<DateTime> get _slots => BookingTimeUtils.slotsForDate(_bookingDate);

  DateTime get _startDateTime => _slots[_startSlotIndex.clamp(0, _slots.length - 1)];

  DateTime get _endDateTime => _slots[_endSlotIndex.clamp(0, _slots.length - 1)];

  int get _minStartIndex =>
      BookingTimeUtils.minStartIndex(_slots, _bookingDate);

  int get _minEndIndex => (_startSlotIndex + 1).clamp(0, _slots.length - 1);

  void _onBookingDateChanged(DateTime date) {
    setState(() {
      _bookingDate = BookingTimeUtils.startOfDay(date);
      final slots = BookingTimeUtils.slotsForDate(_bookingDate);
      _startSlotIndex = _startSlotIndex.clamp(
        BookingTimeUtils.minStartIndex(slots, _bookingDate),
        slots.length - 2,
      );
      if (_endSlotIndex <= _startSlotIndex) {
        _endSlotIndex = (_startSlotIndex + 1).clamp(0, slots.length - 1);
      }
    });
  }

  Future<void> _submit() async {
    final theme = _themeController.text.trim();
    setState(() {
      _themeError = theme.isEmpty ? 'Укажите название встречи' : null;
    });
    if (_themeError != null) return;
    if (!_endDateTime.isAfter(_startDateTime)) {
      _showMessage('Время окончания должно быть позже начала');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final startSec = _startDateTime.millisecondsSinceEpoch ~/ 1000;
      final endSec = _endDateTime.millisecondsSinceEpoch ~/ 1000;

      String? link;
      try {
        final meeting = await VideoconferenceRepository.instance.create(
          topic: theme,
          startSeconds: startSec,
        );
        link = meeting.url;
      } catch (_) {
        // Если отдельный API недоступен — попросим портал сгенерировать ссылку.
      }

      await BookingsRepository.instance.createBooking(
        CreateBookingRequest(
          theme: theme,
          datetimeStartSeconds: startSec,
          datetimeEndSeconds: endSec,
          description: _descriptionController.text.trim(),
          link: link,
          generateLink: link == null || link.isEmpty,
          userIds: _participants
              .map((u) => u.idAsInt)
              .whereType<int>()
              .toList(),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Видеовстреча запланирована')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось запланировать встречу';
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
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

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final slots = _slots;
    final startIndex = _startSlotIndex.clamp(_minStartIndex, slots.length - 1);
    final endIndex = _endSlotIndex.clamp(_minEndIndex, slots.length - 1);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        middle: const Text('Новая видеовстреча'),
        trailing: _isSubmitting
            ? const Padding(
                padding: EdgeInsets.only(right: 8),
                child: CupertinoActivityIndicator(),
              )
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _submit,
                child: const Text('Создать'),
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
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              CupertinoFormSection.insetGrouped(
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _themeController,
                    prefix: const Text('Название'),
                    placeholder: 'Например, Планёрка',
                    textCapitalization: TextCapitalization.sentences,
                    textAlign: TextAlign.end,
                    onChanged: (_) {
                      if (_themeError != null) {
                        setState(() => _themeError = null);
                      }
                    },
                  ),
                  CupertinoTextFormFieldRow(
                    controller: _descriptionController,
                    prefix: const Text('Описание'),
                    placeholder: 'Необязательно',
                    textCapitalization: TextCapitalization.sentences,
                    textAlign: TextAlign.end,
                    maxLines: 3,
                  ),
                ],
              ),
              if (_themeError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    _themeError!,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectedStaffField(
                  participants: _participants,
                  onUserAdded: (user) =>
                      setState(() => _participants = [..._participants, user]),
                  onUserRemoved: (user) => setState(
                    () => _participants =
                        _participants.where((p) => p.id != user.id).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CupertinoFormSection.insetGrouped(
                header: const Text('ВРЕМЯ'),
                children: [
                  CupertinoListTile(
                    leading: _iconBadge(
                      CupertinoIcons.calendar,
                      CupertinoColors.systemOrange,
                    ),
                    title: const Text('День'),
                    additionalInfo: Text(
                      BookingTimeUtils.formatDateShort(_bookingDate),
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      final picked = await showBookingDateSheet(
                        context: context,
                        initial: _bookingDate,
                        firstDate: BookingTimeUtils.startOfDay(now),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (picked != null) _onBookingDateChanged(picked);
                    },
                  ),
                  CupertinoListTile(
                    leading: _iconBadge(
                      CupertinoIcons.clock_fill,
                      CupertinoColors.systemOrange,
                    ),
                    title: const Text('Начало'),
                    additionalInfo: Text(
                      BookingTimeUtils.formatHm(slots[startIndex]),
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      final picked = await showBookingTimeSheet(
                        context: context,
                        title: 'Начало',
                        slots: slots,
                        minIndex: _minStartIndex,
                        currentIndex: startIndex,
                      );
                      if (picked == null) return;
                      setState(() {
                        _startSlotIndex = picked;
                        if (_endSlotIndex <= _startSlotIndex) {
                          _endSlotIndex = (picked + 1).clamp(
                            0,
                            slots.length - 1,
                          );
                        }
                      });
                    },
                  ),
                  CupertinoListTile(
                    leading: _iconBadge(
                      CupertinoIcons.clock_fill,
                      CupertinoColors.systemOrange,
                    ),
                    title: const Text('Окончание'),
                    additionalInfo: Text(
                      BookingTimeUtils.formatHm(slots[endIndex]),
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      final picked = await showBookingTimeSheet(
                        context: context,
                        title: 'Окончание',
                        slots: slots,
                        minIndex: _minEndIndex,
                        currentIndex: endIndex,
                      );
                      if (picked == null) return;
                      setState(() => _endSlotIndex = picked);
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'Встреча появится в календаре. Ссылка на ConnectHub '
                  'будет создана автоматически.',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
