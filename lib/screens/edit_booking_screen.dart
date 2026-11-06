import 'package:flutter/cupertino.dart';

import '../models/bookings/bookable_object.dart';
import '../models/bookings/booking_addition.dart';
import '../models/bookings/booking_detail.dart';
import '../models/bookings/create_booking_request.dart';
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
/// Занятость объекта при переносе проверяет бэкенд: если время занято, его
/// сообщение показывается в диалоге. Дни повтора не редактируются; у всей серии
/// меняется только время — дату каждой встречи серии бэкенд сохраняет.
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

  late bool _isPrivate;

  /// Другой объект, выбранный вместо текущего.
  BookableObject? _pickedObject;
  bool _isLoadingObjects = false;

  List<BookingAddition> _additions = const [];
  late Map<int, int> _additionQuantities;

  bool get _supportsAdditions =>
      widget.detail.modelType == CreateBookingRequest.meetingRoomModelType;

  /// Встречу без объекта на другое место не перенести: у неё нет места.
  bool get _canChangeObject {
    final d = widget.detail;
    return d.object != null &&
        d.spaceId != null &&
        d.modelType != null &&
        d.modelType != CreateBookingRequest.meetingModelType;
  }

  @override
  void initState() {
    super.initState();
    final d = widget.detail;
    _isPrivate = d.isPrivate;
    _additionQuantities = Map.of(d.additionQuantities);
    if (_supportsAdditions) _loadAdditions();
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

  Future<void> _loadAdditions() async {
    try {
      final items = await BookingsRepository.instance.getAdditions();
      if (mounted) setState(() => _additions = items);
    } catch (_) {
      // Без справочника блок просто не показывается, заказ останется прежним.
    }
  }

  /// Другие свободные объекты того же типа и этажа на выбранное время.
  Future<void> _pickObject() async {
    final detail = widget.detail;
    final current = _pickedObject ?? detail.object;
    if (current == null || _isLoadingObjects) return;
    final slots = _slots;
    final start = _timeChanged ? slots[_startSlotIndex] : detail.datetimeStart;
    final end = _timeChanged ? slots[_endSlotIndex] : detail.datetimeEnd;

    setState(() => _isLoadingObjects = true);
    final List<BookableObject> free;
    try {
      free = await BookingsRepository.instance.getFreeObjects(
        modelType: detail.modelType!,
        datetimeStartSeconds: start.millisecondsSinceEpoch ~/ 1000,
        datetimeEndSeconds: end.millisecondsSinceEpoch ~/ 1000,
        spaceId: detail.spaceId!,
      );
    } catch (e) {
      if (mounted) _showMessage(AppFeedback.messageOf(e));
      return;
    } finally {
      if (mounted) setState(() => _isLoadingObjects = false);
    }
    if (!mounted) return;

    final options = free.where((o) => o.id != current.id).toList();
    if (options.isEmpty) {
      _showMessage('На это время других свободных мест нет');
      return;
    }
    final picked = await showBookingOptionSheet<BookableObject>(
      context: context,
      title: 'Свободно на это время',
      options: options,
      current: current,
      labelOf: (o) => o.name,
    );
    if (picked != null && mounted) setState(() => _pickedObject = picked);
  }

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

    final detail = widget.detail;
    final picked = _pickedObject;
    final objectChanged = picked != null && picked.id != detail.modelId;

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
          isPrivate: _isPrivate != detail.isPrivate ? _isPrivate : null,
          modelType: objectChanged ? detail.modelType : null,
          modelId: objectChanged ? picked.id : null,
          additions: UpdateBookingRequest.additionsPayload(
            detail.additionQuantities,
            _additionQuantities,
          ),
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
                value: _pickedObject?.name ?? place,
                valueMaxWidth: 200,
                onTap: _canChangeObject && !_isSubmitting ? _pickObject : null,
              ),
            BookingFieldRow(
              icon: CupertinoIcons.link,
              color: CupertinoColors.systemBlue.resolveFrom(context),
              controller: _linkController,
              placeholder: 'Ссылка на встречу',
              keyboardType: TextInputType.url,
            ),
            BookingSwitchRow(
              icon: CupertinoIcons.lock_fill,
              color: CupertinoColors.systemGrey.resolveFrom(context),
              label: 'Приватная встреча',
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
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
            if (!_canChangeDate)
              'У всей серии меняется только время, дни повтора остаются.',
            if (detail.isRecurring)
              widget.updateAll
                  ? 'Изменения применятся ко всей серии.'
                  : 'Изменения применятся только к этой встрече.',
          ].join(' '),
        ),
        if (_additions.isNotEmpty) ...[
          const AppGlassSectionLabel('Дополнения'),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final addition in _additions) _additionRow(addition),
            ],
          ),
        ],
      ],
    );
  }

  Widget _additionRow(BookingAddition addition) {
    final quantity = _additionQuantities[addition.id] ?? 0;
    return CupertinoListTile(
      title: Text(addition.name),
      subtitle: (addition.description ?? '').isNotEmpty
          ? Text(addition.description!)
          : null,
      additionalInfo: BookingAdditionStepper(
        quantity: quantity,
        onDecrement: quantity > 0
            ? () => setState(
                () => _additionQuantities[addition.id] = quantity - 1,
              )
            : null,
        onIncrement: () =>
            setState(() => _additionQuantities[addition.id] = quantity + 1),
      ),
    );
  }
}
