import 'package:flutter/cupertino.dart';

import '../models/bookings/bookable_object.dart';
import '../models/bookings/booking_addition.dart';
import '../models/bookings/create_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../utils/booking_time_utils.dart';
import '../widgets/bookable_object_preview.dart';
import '../widgets/booking_pickers.dart';
import '../widgets/selected_staff_field.dart';

/// Форма создания брони по выбранному объекту.
class CreateBookingScreen extends StatefulWidget {
  const CreateBookingScreen({
    super.key,
    required this.object,
    required this.modelType,
    required this.initialStart,
    required this.initialEnd,
  });

  final BookableObject object;
  final int modelType;
  final DateTime initialStart;
  final DateTime initialEnd;

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
    _loadAdditions();
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
      await BookingsRepository.instance.createBooking(
        CreateBookingRequest(
          theme: theme,
          modelType: widget.modelType,
          modelId: widget.object.id,
          datetimeStartSeconds: _startDateTime.millisecondsSinceEpoch ~/ 1000,
          datetimeEndSeconds: _endDateTime.millisecondsSinceEpoch ~/ 1000,
          description: _descriptionController.text.trim(),
          link: _isOnlineConference && _linkController.text.trim().isNotEmpty
              ? _linkController.text.trim()
              : null,
          generateLink:
              _isOnlineConference && _linkController.text.trim().isEmpty,
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
    final slots = _slots;
    final startIndex = _startSlotIndex.clamp(_minStartIndex, slots.length - 1);
    final endIndex = _endSlotIndex.clamp(_minEndIndex, slots.length - 1);
    final rangeError = _validateDateTimeRange();
    final now = DateTime.now();

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Новая бронь'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 26),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: (_isSubmitting || rangeError != null) ? null : _submit,
          child: _isSubmitting
              ? const CupertinoActivityIndicator()
              : const Text(
                  'Забронировать',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ),
      // Без Material-предка любой Text, не переопределивший все поля стиля
      // явно, откатывается на debug-заглушку MaterialApp — этот
      // DefaultTextStyle подстраховывает весь экран разом (см. тот же
      // приём в news_create_screen.dart).
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemGroupedBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: BookableObjectPreview(object: widget.object),
                ),
              ),
              const SizedBox(height: 20),
              CupertinoFormSection.insetGrouped(
                header: const Text('О БРОНИ'),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _themeController,
                    prefix: const Text('Тема'),
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
              CupertinoFormSection.insetGrouped(
                children: [
                  CupertinoListTile(
                    title: const Text('Приватная встреча'),
                    trailing: CupertinoSwitch(
                      value: _isPrivate,
                      onChanged: (v) => setState(() => _isPrivate = v),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text(
                  'Приватные встречи будут отображаться в общем календаре '
                  'без наименования и описания, чтобы сохранить '
                  'конфиденциальность.',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CupertinoFormSection.insetGrouped(
                children: [
                  CupertinoListTile(
                    title: const Text('Онлайн-конференция'),
                    trailing: CupertinoSwitch(
                      value: _isOnlineConference,
                      onChanged: (v) => setState(() => _isOnlineConference = v),
                    ),
                  ),
                  if (_isOnlineConference)
                    CupertinoTextFormFieldRow(
                      controller: _linkController,
                      prefix: const Text('Ссылка'),
                      placeholder: 'https://…',
                      keyboardType: TextInputType.url,
                      textAlign: TextAlign.end,
                    ),
                ],
              ),
              if (_isOnlineConference)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(
                    'Укажите ссылку, если встреча планируется во внешнем '
                    'сервисе. При отсутствии ссылки ВКС будет создана в '
                    'портале, ссылка автоматически отобразится в календаре.',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
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
                    () => _participants = _participants
                        .where((p) => p.id != user.id)
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CupertinoFormSection.insetGrouped(
                header: const Text('ДАТА И ВРЕМЯ'),
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
                        _clampEndIndex(slots);
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
                      if (picked != null) {
                        setState(() => _endSlotIndex = picked);
                      }
                    },
                  ),
                ],
              ),
              if (rangeError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(
                    rangeError,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              if (_additionsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (_additionsError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _additionsError!,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 13,
                    ),
                  ),
                )
              else if (_additions.isNotEmpty)
                CupertinoFormSection.insetGrouped(
                  header: const Text('ДОПОЛНЕНИЯ'),
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
            ],
          ),
        ),
      ),
    );
  }
}

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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onDecrement,
          child: Icon(
            CupertinoIcons.minus_circle_fill,
            size: 24,
            color: onDecrement == null
                ? CupertinoColors.systemGrey4.resolveFrom(context)
                : CupertinoColors.systemRed,
          ),
        ),
        SizedBox(
          width: 26,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        GestureDetector(
          onTap: onIncrement,
          child: const Icon(
            CupertinoIcons.plus_circle_fill,
            size: 24,
            color: CupertinoColors.systemGreen,
          ),
        ),
      ],
    );
  }
}
