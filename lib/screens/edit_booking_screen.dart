import 'package:flutter/cupertino.dart';

import '../models/bookings/booking_detail.dart';
import '../models/bookings/update_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../utils/app_feedback.dart';
import '../utils/booking_time_utils.dart';
import '../widgets/app_glass.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/booking_pickers.dart';
import '../widgets/selected_staff_field.dart';

/// Редактирование брони (`POST /booking/update/{id}`).
///
/// Тема, описание, ссылка и участники меняются всегда. Дату и время можно
/// перенести только у встречи без объекта ([BookingDetail.canReschedule]):
/// бэкенд при обновлении не проверяет занятость переговорной. Дни повтора
/// не редактируются; у всей серии меняется только время — дату каждой
/// встречи серии бэкенд сохраняет.
class EditBookingScreen extends StatefulWidget {
  const EditBookingScreen({
    super.key,
    required this.detail,
    this.updateAll = false,
  });

  final BookingDetail detail;

  /// Область правки для повторяющейся брони: обновить всю серию
  /// (`update_all=1`) — выбирается пользователем до открытия этого экрана,
  /// см. `booking_detail_sheet.dart`.
  final bool updateAll;

  @override
  State<EditBookingScreen> createState() => _EditBookingScreenState();
}

class _EditBookingScreenState extends State<EditBookingScreen> {
  late final TextEditingController _themeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _linkController;
  late List<StaffUser> _participants;
  bool _isSubmitting = false;
  String? _themeError;

  /// День и получасовые слоты нового времени. Пока пользователь не трогал
  /// время, оно не отправляется — исходное может быть не кратно 30 минутам.
  late DateTime _date;
  late int _startSlotIndex;
  late int _endSlotIndex;
  bool _timeChanged = false;

  @override
  void initState() {
    super.initState();
    final d = widget.detail;
    _themeController = TextEditingController(text: d.theme);
    _descriptionController = TextEditingController(text: d.description ?? '');
    _linkController = TextEditingController(text: d.link ?? '');
    _participants = List<StaffUser>.from(d.participants);
    _date = BookingTimeUtils.startOfDay(d.datetimeStart);
    final slots = _slots;
    _startSlotIndex = BookingTimeUtils.nearestSlotIndex(
      slots,
      d.datetimeStart,
      floorToPrevious: true,
    ).clamp(0, slots.length - 2);
    _endSlotIndex = BookingTimeUtils.nearestSlotIndex(
      slots,
      d.datetimeEnd,
      floorToPrevious: false,
    ).clamp(_startSlotIndex + 1, slots.length - 1);
  }

  List<DateTime> get _slots => BookingTimeUtils.slotsForDate(_date);

  bool get _canChangeDate => !(widget.detail.isRecurring && widget.updateAll);

  int get _minStartIndex => BookingTimeUtils.minStartIndex(_slots, _date);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showBookingDateSheet(
      context: context,
      initial: _date,
      firstDate: BookingTimeUtils.startOfDay(now),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _timeChanged = true;
      _date = BookingTimeUtils.startOfDay(picked);
      final slots = _slots;
      _startSlotIndex = _startSlotIndex.clamp(_minStartIndex, slots.length - 2);
      if (_endSlotIndex <= _startSlotIndex) {
        _endSlotIndex = (_startSlotIndex + 1).clamp(0, slots.length - 1);
      }
    });
  }

  Future<void> _pickStart() async {
    final slots = _slots;
    final picked = await showBookingTimeSheet(
      context: context,
      title: 'Начало',
      slots: slots,
      minIndex: _minStartIndex,
      currentIndex: _startSlotIndex,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _timeChanged = true;
      // Длительность сохраняем: сдвигаем окончание вместе с началом.
      final length = _endSlotIndex - _startSlotIndex;
      _startSlotIndex = picked.clamp(0, slots.length - 2);
      _endSlotIndex = (_startSlotIndex + length).clamp(
        _startSlotIndex + 1,
        slots.length - 1,
      );
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showBookingTimeSheet(
      context: context,
      title: 'Окончание',
      slots: _slots,
      minIndex: _startSlotIndex + 1,
      currentIndex: _endSlotIndex,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _timeChanged = true;
      _endSlotIndex = picked;
    });
  }

  @override
  void dispose() {
    _themeController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  List<int> get _participantIds {
    return _participants.map((u) => u.idAsInt).whereType<int>().toList();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final theme = _themeController.text.trim();
    setState(() {
      _themeError = theme.isEmpty ? 'Укажите тему' : null;
    });
    if (_themeError != null) return;

    final slots = _slots;
    final start = _timeChanged ? slots[_startSlotIndex] : null;
    final end = _timeChanged ? slots[_endSlotIndex] : null;
    if (start != null && !start.isAfter(DateTime.now())) {
      _showMessage('Нельзя перенести встречу в прошлое');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await BookingsRepository.instance.updateBooking(
        bookingId: widget.detail.id,
        request: UpdateBookingRequest(
          datetimeStart: start,
          datetimeEnd: end,
          theme: theme,
          description: _descriptionController.text.trim(),
          link: _linkController.text.trim(),
          userIds: _participantIds,
          updateAll: widget.detail.isRecurring && widget.updateAll
              ? true
              : null,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(AppFeedback.messageOf(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final canReschedule = detail.canReschedule;
    final slots = _slots;
    final place = detail.displayObjectName.trim();
    final days = detail.recurring?.daysOfWeek.isNotEmpty ?? false
        ? detail.recurring!.daysOfWeekLabel
        : null;

    return BookingGlassScaffold(
      title: 'Изменить бронь',
      canPop: !_isSubmitting,
      trailing: BookingNavAction(
        label: 'Сохранить',
        isLoading: _isSubmitting,
        onPressed: _submit,
      ),
      children: [
        BookingTitleCard(
          themeController: _themeController,
          themePlaceholder: 'Тема',
          descriptionController: _descriptionController,
          errorText: _themeError,
          onThemeChanged: (_) {
            if (_themeError != null) setState(() => _themeError = null);
          },
        ),
        AppGlassSection(
          children: [
            if (place.isNotEmpty)
              BookingPickerRow(
                icon: CupertinoIcons.location_solid,
                color: CupertinoColors.systemRed.resolveFrom(context),
                label: 'Место',
                value: place,
                valueMaxWidth: 200,
              ),
            BookingFieldRow(
              icon: CupertinoIcons.link,
              color: CupertinoColors.systemBlue.resolveFrom(context),
              controller: _linkController,
              placeholder: 'Ссылка на встречу',
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SelectedStaffField(
            participants: _participants,
            onUserAdded: (user) =>
                setState(() => _participants = [..._participants, user]),
            onUserRemoved: (user) => setState(
              () => _participants = _participants
                  .where((p) => p.id != user.id)
                  .toList(),
            ),
          ),
        ),
        const AppGlassSectionLabel('Когда'),
        AppGlassSection(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            if (!canReschedule) ...[
              BookingPickerRow(
                icon: CupertinoIcons.calendar,
                color: CupertinoColors.systemOrange.resolveFrom(context),
                label: 'Дата',
                value: BookingTimeUtils.formatDateShort(detail.datetimeStart),
              ),
              BookingPickerRow(
                icon: CupertinoIcons.clock_fill,
                color: CupertinoColors.systemOrange.resolveFrom(context),
                label: 'Время',
                value:
                    '${BookingTimeUtils.formatHm(detail.datetimeStart)}–'
                    '${BookingTimeUtils.formatHm(detail.datetimeEnd)}',
              ),
            ] else ...[
              BookingPickerRow(
                icon: CupertinoIcons.calendar,
                color: CupertinoColors.systemOrange.resolveFrom(context),
                label: 'Дата',
                value: BookingTimeUtils.formatDateShort(_date),
                onTap: _canChangeDate && !_isSubmitting ? _pickDate : null,
              ),
              BookingPickerRow(
                icon: CupertinoIcons.clock_fill,
                color: CupertinoColors.systemOrange.resolveFrom(context),
                label: 'Начало',
                value: BookingTimeUtils.formatHm(
                  _timeChanged ? slots[_startSlotIndex] : detail.datetimeStart,
                ),
                onTap: _isSubmitting ? null : _pickStart,
              ),
              BookingPickerRow(
                icon: CupertinoIcons.clock,
                color: CupertinoColors.systemOrange.resolveFrom(context),
                label: 'Окончание',
                value: BookingTimeUtils.formatHm(
                  _timeChanged ? slots[_endSlotIndex] : detail.datetimeEnd,
                ),
                onTap: _isSubmitting ? null : _pickEnd,
              ),
            ],
            if (days != null)
              BookingPickerRow(
                icon: CupertinoIcons.repeat,
                color: CupertinoColors.systemPurple.resolveFrom(context),
                label: 'Повтор',
                value: days,
                valueMaxWidth: 200,
              ),
          ],
        ),
        BookingFootnote(
          [
            if (!canReschedule)
              'Бронь объекта нельзя перенести: удалите её и забронируйте '
                  'заново на новое время.'
            else if (!_canChangeDate)
              'У всей серии меняется только время, дни повтора остаются.',
            if (detail.isRecurring)
              widget.updateAll
                  ? 'Изменения применятся ко всей серии.'
                  : 'Изменения применятся только к этой встрече.',
          ].join(' '),
        ),
      ],
    );
  }
}
