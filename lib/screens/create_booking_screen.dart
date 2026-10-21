import 'package:flutter/cupertino.dart';

import '../config/connector_config.dart';
import '../models/bookings/bookable_object.dart';
import '../models/bookings/booking_addition.dart';
import '../models/bookings/create_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/connector_repository.dart';
import '../utils/booking_time_utils.dart';
import '../widgets/app_glass.dart';
import '../widgets/bookable_object_preview.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/booking_pickers.dart';
import '../widgets/selected_staff_field.dart';

/// Форма создания брони: по выбранному объекту, либо, если [object] не
/// задан, встречи без объекта (`model_type`/`model_id` — см.
/// [CreateBookingRequest.meetingModelType]).
class CreateBookingScreen extends StatefulWidget {
  const CreateBookingScreen({
    super.key,
    this.object,
    required this.modelType,
    required this.modelId,
    required this.initialStart,
    required this.initialEnd,
  });

  final BookableObject? object;
  final int modelType;
  final int modelId;
  final DateTime initialStart;
  final DateTime initialEnd;

  bool get isMeeting => object == null;

  /// Доп. услуги (чай, кофе и т.п.) заказываются только к переговорной —
  /// для рабочих мест, локеров, парковок и встреч без объекта их нет.
  bool get supportsAdditions =>
      !isMeeting && modelType == CreateBookingRequest.meetingRoomModelType;

  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  final _themeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();

  late DateTime _bookingDate;
  late int _startSlotIndex;
  late int _endSlotIndex;

  List<BookingAddition> _additions = const [];
  bool _additionsLoading = true;
  String? _additionsError;
  final Map<int, int> _additionQuantities = {};

  List<StaffUser> _participants = [];

  bool _isPrivate = false;
  bool _isOnlineConference = false;

  bool _isSubmitting = false;
  String? _themeError;

  @override
  void initState() {
    super.initState();
    _initDateTimeFromInitial();
    if (widget.supportsAdditions) {
      _loadAdditions();
    } else {
      _additionsLoading = false;
    }
  }

  void _initDateTimeFromInitial() {
    final start = widget.initialStart;
    final end = widget.initialEnd.isAfter(start)
        ? widget.initialEnd
        : start.add(const Duration(minutes: BookingTimeUtils.slotMinutes));

    _bookingDate = BookingTimeUtils.startOfDay(start);
    final slots = BookingTimeUtils.slotsForDate(_bookingDate);

    _startSlotIndex = BookingTimeUtils.nearestSlotIndex(
      slots,
      start,
      floorToPrevious: true,
    );
    _startSlotIndex = _startSlotIndex.clamp(
      BookingTimeUtils.minStartIndex(slots, _bookingDate),
      slots.length - 1,
    );

    _endSlotIndex = BookingTimeUtils.nearestSlotIndex(
      slots,
      end,
      floorToPrevious: true,
    );
    _clampEndIndex(slots);
  }

  @override
  void dispose() {
    _themeController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadAdditions() async {
    setState(() {
      _additionsLoading = true;
      _additionsError = null;
    });

    try {
      final items = await BookingsRepository.instance.getAdditions();
      if (!mounted) return;
      setState(() {
        _additions = items;
        _additionsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _additionsError = e.toString();
        _additionsLoading = false;
      });
    }
  }

  List<DateTime> get _slots => BookingTimeUtils.slotsForDate(_bookingDate);

  DateTime get _startDateTime =>
      BookingTimeUtils.slotAt(_slots, _startSlotIndex);

  DateTime get _endDateTime => BookingTimeUtils.slotAt(_slots, _endSlotIndex);

  int get _minStartIndex =>
      BookingTimeUtils.minStartIndex(_slots, _bookingDate);

  int get _minEndIndex => (_startSlotIndex + 1).clamp(0, _slots.length - 1);

  void _clampEndIndex(List<DateTime> slots) {
    _endSlotIndex = _endSlotIndex.clamp(_minEndIndex, slots.length - 1);
  }

  void _onBookingDateChanged(DateTime picked) {
    setState(() {
      _bookingDate = BookingTimeUtils.startOfDay(picked);
      final slots = _slots;
      final minStart = BookingTimeUtils.minStartIndex(slots, _bookingDate);
      _startSlotIndex = _startSlotIndex.clamp(minStart, slots.length - 1);
      _clampEndIndex(slots);
    });
  }

  String? _validateDateTimeRange() {
    if (!BookingTimeUtils.isRangeValid(_startDateTime, _endDateTime)) {
      final now = DateTime.now();
      if (_startDateTime.isBefore(now)) {
        return 'Нельзя выбрать прошедшее время';
      }
      return 'Время окончания должно быть позже времени начала';
    }
    return null;
  }

  Map<int, int> get _selectedAdditions {
    return Map.fromEntries(
      _additionQuantities.entries.where((e) => e.value > 0),
    );
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final rangeError = _validateDateTimeRange();
    if (rangeError != null) {
      _showMessage(rangeError);
      return;
    }

    final theme = _themeController.text.trim();
    setState(() {
      _themeError = theme.isEmpty ? 'Укажите тему бронирования' : null;
    });
    if (_themeError != null) return;

    setState(() => _isSubmitting = true);
    try {
      String? link;
      var generateLink = false;
      if (_isOnlineConference) {
        final manualLink = _linkController.text.trim();
        if (manualLink.isNotEmpty) {
          link = manualLink;
        } else {
          link = await _createJitsiConferenceLink(theme);
          generateLink = link == null || link.isEmpty;
        }
      }

      await BookingsRepository.instance.createBooking(
        CreateBookingRequest(
          theme: theme,
          modelType: widget.modelType,
          modelId: widget.modelId,
          datetimeStartSeconds: _startDateTime.millisecondsSinceEpoch ~/ 1000,
          datetimeEndSeconds: _endDateTime.millisecondsSinceEpoch ~/ 1000,
          description: _descriptionController.text.trim(),
          link: link,
          generateLink: generateLink,
          isPrivate: _isPrivate,
          additions: _selectedAdditions,
          userIds: _participants
              .map((u) => u.idAsInt)
              .whereType<int>()
              .toList(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Комната Jitsi через Коннектор. Без ручной ссылки создаём новую встречу
  /// и подставляем публичный URL (`/connector/{room}`).
  Future<String?> _createJitsiConferenceLink(String theme) async {
    try {
      final session = await ConnectorRepository.instance.createInstant(
        topic: theme,
      );
      final publicUrl = session.publicUrl.trim();
      if (publicUrl.isNotEmpty) return publicUrl;
      if (session.room.isNotEmpty) {
        return ConnectorConfig.publicMeetingUrl(session.room);
      }
    } catch (_) {}
    return null;
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showBookingDateSheet(
      context: context,
      initial: _bookingDate,
      firstDate: BookingTimeUtils.startOfDay(now),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) _onBookingDateChanged(picked);
  }

  Future<void> _pickStart(List<DateTime> slots, int startIndex) async {
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
        _endSlotIndex = (picked + 1).clamp(0, slots.length - 1);
      }
      _clampEndIndex(slots);
    });
  }

  Future<void> _pickEnd(List<DateTime> slots, int endIndex) async {
    final picked = await showBookingTimeSheet(
      context: context,
      title: 'Окончание',
      slots: slots,
      minIndex: _minEndIndex,
      currentIndex: endIndex,
    );
    if (picked != null) setState(() => _endSlotIndex = picked);
  }

  List<Widget> _buildAdditions() {
    if (!widget.supportsAdditions) return const [];
    if (_additionsLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }
    if (_additionsError != null) {
      return [
        const SizedBox(height: 12),
        BookingFootnote(_additionsError!, isError: true),
      ];
    }
    if (_additions.isEmpty) return const [];
    return [
      const AppGlassSectionLabel('Дополнения'),
      AppGlassSection(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: _additions.map((a) {
          final qty = _additionQuantities[a.id] ?? 0;
          return CupertinoListTile(
            title: Text(a.name),
            subtitle: (a.description ?? '').isNotEmpty
                ? Text(a.description!)
                : null,
            additionalInfo: _AdditionStepper(
              quantity: qty,
              onDecrement: qty > 0
                  ? () => setState(() {
                      if (qty <= 1) {
                        _additionQuantities.remove(a.id);
                      } else {
                        _additionQuantities[a.id] = qty - 1;
                      }
                    })
                  : null,
              onIncrement: () => setState(() {
                _additionQuantities[a.id] = qty + 1;
              }),
            ),
          );
        }).toList(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    final startIndex = _startSlotIndex.clamp(_minStartIndex, slots.length - 1);
    final endIndex = _endSlotIndex.clamp(_minEndIndex, slots.length - 1);
    final rangeError = _validateDateTimeRange();

    return BookingGlassScaffold(
      title: widget.isMeeting ? 'Новая встреча' : 'Новая бронь',
      canPop: !_isSubmitting,
      trailing: BookingNavAction(
        label: widget.isMeeting ? 'Создать' : 'Забронировать',
        isLoading: _isSubmitting,
        onPressed: rangeError != null ? null : _submit,
      ),
      children: [
        if (widget.object != null) ...[
          BookingGlassCard(
            child: BookableObjectPreview(object: widget.object!),
          ),
          const SizedBox(height: 16),
        ],
        BookingTitleCard(
          themeController: _themeController,
          themePlaceholder: widget.isMeeting ? 'Название встречи' : 'Тема',
          descriptionController: _descriptionController,
          errorText: _themeError,
          onThemeChanged: (_) {
            if (_themeError != null) setState(() => _themeError = null);
          },
        ),
        const AppGlassSectionLabel('Дата и время'),
        AppGlassSection(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            BookingPickerRow(
              icon: CupertinoIcons.calendar,
              color: CupertinoColors.systemOrange,
              label: 'День',
              value: BookingTimeUtils.formatDateShort(_bookingDate),
              onTap: _pickDate,
            ),
            BookingPickerRow(
              icon: CupertinoIcons.clock_fill,
              color: CupertinoColors.systemOrange,
              label: 'Начало',
              value: BookingTimeUtils.formatHm(slots[startIndex]),
              onTap: () => _pickStart(slots, startIndex),
            ),
            BookingPickerRow(
              icon: CupertinoIcons.clock,
              color: CupertinoColors.systemOrange,
              label: 'Окончание',
              value: BookingTimeUtils.formatHm(slots[endIndex]),
              onTap: () => _pickEnd(slots, endIndex),
            ),
          ],
        ),
        if (rangeError != null) BookingFootnote(rangeError, isError: true),
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
        AppGlassSection(
          children: [
            BookingSwitchRow(
              icon: CupertinoIcons.video_camera_solid,
              color: CupertinoColors.systemBlue,
              label: 'Онлайн-конференция',
              value: _isOnlineConference,
              onChanged: (v) => setState(() => _isOnlineConference = v),
            ),
            if (_isOnlineConference)
              BookingFieldRow(
                icon: CupertinoIcons.link,
                color: CupertinoColors.systemGrey,
                controller: _linkController,
                placeholder: 'Ссылка (необязательно)',
                keyboardType: TextInputType.url,
              ),
            BookingSwitchRow(
              icon: CupertinoIcons.lock_fill,
              color: CupertinoColors.systemGrey,
              label: 'Приватная встреча',
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
          ],
        ),
        BookingFootnote(
          [
            if (_isOnlineConference)
              'Без ссылки конференция создастся автоматически.',
            'Приватная встреча видна в общем календаре без темы и описания.',
          ].join(' '),
        ),
        ..._buildAdditions(),
      ],
    );
  }
}

/// Счётчик доп. услуги — капсула «− n +», как системный степпер.
class _AdditionStepper extends StatelessWidget {
  const _AdditionStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    Widget button(IconData icon, VoidCallback? onTap) {
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Icon(
          icon,
          size: 16,
          color: onTap == null
              ? CupertinoColors.tertiaryLabel.resolveFrom(context)
              : label,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(CupertinoIcons.minus, onDecrement),
          SizedBox(
            width: 22,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: quantity > 0
                    ? label
                    : CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          button(CupertinoIcons.plus, onIncrement),
        ],
      ),
    );
  }
}
