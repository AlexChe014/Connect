import 'package:flutter/material.dart';

import '../config/app_icons.dart';
import '../models/bookings/bookable_object.dart';
import '../models/bookings/booking_addition.dart';
import '../models/bookings/create_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../utils/booking_time_utils.dart';
import '../widgets/bookable_object_preview.dart';
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

  final _formKey = GlobalKey<FormState>();

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



  bool _isSubmitting = false;



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

    _startSlotIndex = BookingTimeUtils.nearestSlotIndex(slots, start, floorToPrevious: true);

    _startSlotIndex = _startSlotIndex.clamp(

      BookingTimeUtils.minStartIndex(slots, _bookingDate),

      slots.length - 1,

    );



    _endSlotIndex = BookingTimeUtils.nearestSlotIndex(slots, end, floorToPrevious: true);

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



  DateTime get _startDateTime => BookingTimeUtils.slotAt(_slots, _startSlotIndex);

  DateTime get _endDateTime => BookingTimeUtils.slotAt(_slots, _endSlotIndex);



  int get _minStartIndex => BookingTimeUtils.minStartIndex(_slots, _bookingDate);



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

    final rangeError = _validateDateTimeRange();

    if (rangeError != null) {

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(rangeError)));

      return;

    }

    if (!_formKey.currentState!.validate()) return;



    setState(() => _isSubmitting = true);

    try {

      await BookingsRepository.instance.createBooking(

        CreateBookingRequest(

          theme: _themeController.text.trim(),

          modelType: widget.modelType,

          modelId: widget.object.id,

          datetimeStartSeconds: _startDateTime.millisecondsSinceEpoch ~/ 1000,

          datetimeEndSeconds: _endDateTime.millisecondsSinceEpoch ~/ 1000,

          description: _descriptionController.text.trim(),

          link: _linkController.text.trim(),

          additions: _selectedAdditions,

          userIds: _participants.map((u) => u.idAsInt).whereType<int>().toList(),

        ),

      );

      if (!mounted) return;

      Navigator.pop(context, true);

    } catch (e) {

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text(e.toString())),

      );

    } finally {

      if (mounted) setState(() => _isSubmitting = false);

    }

  }



  InputDecoration _decoration(BuildContext context, String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
    );
  }



  @override

  Widget build(BuildContext context) {

    final slots = _slots;

    final startIndex = _startSlotIndex.clamp(_minStartIndex, slots.length - 1);

    final endIndex = _endSlotIndex.clamp(_minEndIndex, slots.length - 1);

    final rangeError = _validateDateTimeRange();



    return Scaffold(

      appBar: AppBar(

        title: const Text('Новая бронь'),

        centerTitle: true,

      ),

      body: Form(

        key: _formKey,

        child: ListView(

          padding: const EdgeInsets.all(16),

          children: [

            Card(

              child: Padding(

                padding: const EdgeInsets.all(14),

                child: BookableObjectPreview(object: widget.object),

              ),

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _themeController,

              textCapitalization: TextCapitalization.sentences,

              decoration: _decoration(context, 'Тема *'),

              validator: (v) {

                if ((v ?? '').trim().isEmpty) return 'Укажите тему бронирования';

                return null;

              },

            ),

            const SizedBox(height: 12),

            TextFormField(

              controller: _descriptionController,

              maxLines: 3,

              textCapitalization: TextCapitalization.sentences,

              decoration: _decoration(context, 'Описание', hint: 'Необязательно'),

            ),

            const SizedBox(height: 12),

            TextFormField(

              controller: _linkController,

              keyboardType: TextInputType.url,

              decoration: _decoration(context, 'Ссылка', hint: 'https://…'),

            ),

            const SizedBox(height: 16),

            SelectedStaffField(

              participants: _participants,

              onUserAdded: (user) =>

                  setState(() => _participants = [..._participants, user]),

              onUserRemoved: (user) => setState(

                () => _participants = _participants.where((p) => p.id != user.id).toList(),

              ),

            ),

            const SizedBox(height: 16),

            Text(

              'Дата и время',

              style: Theme.of(context).textTheme.titleSmall?.copyWith(

                    fontWeight: FontWeight.w600,

                  ),

            ),

            const SizedBox(height: 8),

            InkWell(

              onTap: () async {

                final now = DateTime.now();

                final picked = await showDatePicker(

                  context: context,

                  initialDate: _bookingDate.isBefore(now) ? now : _bookingDate,

                  firstDate: BookingTimeUtils.startOfDay(now),

                  lastDate: DateTime(now.year + 1),

                );

                if (picked != null) _onBookingDateChanged(picked);

              },

              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'День',
                  suffixIcon: AppIcon(AppIcons.date, size: 20),
                ),
                child: Text(BookingTimeUtils.formatDateShort(_bookingDate)),
              ),

            ),

            const SizedBox(height: 12),

            Row(

              children: [

                Expanded(

                  child: _TimeSlotField(

                    label: 'Начало',

                    slotIndex: startIndex,

                    slots: slots,

                    minSlotIndex: _minStartIndex,

                    onChanged: (i) {

                      setState(() {

                        _startSlotIndex = i;

                        if (_endSlotIndex <= _startSlotIndex) {

                          _endSlotIndex = (i + 1).clamp(0, slots.length - 1);

                        }

                        _clampEndIndex(slots);

                      });

                    },

                  ),

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: _TimeSlotField(

                    label: 'Окончание',

                    slotIndex: endIndex,

                    slots: slots,

                    minSlotIndex: _minEndIndex,

                    onChanged: (i) => setState(() => _endSlotIndex = i),

                  ),

                ),

              ],

            ),

            if (rangeError != null) ...[

              const SizedBox(height: 8),

              Text(

                rangeError,

                style: Theme.of(context).textTheme.bodySmall?.copyWith(

                      color: Theme.of(context).colorScheme.error,

                    ),

              ),

            ],

            const SizedBox(height: 16),

            Text(

              'Дополнения',

              style: Theme.of(context).textTheme.titleSmall?.copyWith(

                    fontWeight: FontWeight.w600,

                  ),

            ),

            const SizedBox(height: 8),

            if (_additionsLoading)

              const Padding(

                padding: EdgeInsets.symmetric(vertical: 12),

                child: Center(child: CircularProgressIndicator()),

              )

            else if (_additionsError != null)

              Text(

                _additionsError!,

                style: Theme.of(context).textTheme.bodySmall?.copyWith(

                      color: Theme.of(context).colorScheme.error,

                    ),

              )

            else if (_additions.isEmpty)

              Text(

                'Нет доступных дополнений',

                style: Theme.of(context).textTheme.bodyMedium?.copyWith(

                      color: Theme.of(context).colorScheme.outline,

                    ),

              )

            else

              ..._additions.map((a) {

                final qty = _additionQuantities[a.id] ?? 0;

                return Card(

                  margin: const EdgeInsets.only(bottom: 8),

                  child: Padding(

                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

                    child: Row(

                      children: [

                        Expanded(

                          child: Column(

                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [

                              Text(a.name),

                              if ((a.description ?? '').isNotEmpty)

                                Text(

                                  a.description!,

                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(

                                        color: Theme.of(context).colorScheme.outline,

                                      ),

                                ),

                            ],

                          ),

                        ),

                        IconButton(

                          onPressed: qty > 0

                              ? () => setState(() {

                                    if (qty <= 1) {

                                      _additionQuantities.remove(a.id);

                                    } else {

                                      _additionQuantities[a.id] = qty - 1;

                                    }

                                  })

                              : null,

                          icon: const Icon(Icons.remove_circle_outline),

                        ),

                        Text('$qty', style: Theme.of(context).textTheme.titleMedium),

                        IconButton(

                          onPressed: () => setState(() {

                            _additionQuantities[a.id] = qty + 1;

                          }),

                          icon: const AppIcon(AppIcons.profileAdd),

                        ),

                      ],

                    ),

                  ),

                );

              }),

            const SizedBox(height: 24),

            FilledButton(

              onPressed: _isSubmitting || rangeError != null ? null : _submit,

              child: _isSubmitting

                  ? const SizedBox(

                      height: 22,

                      width: 22,

                      child: CircularProgressIndicator(strokeWidth: 2),

                    )

                  : const Text('Забронировать'),

            ),

          ],

        ),

      ),

    );

  }

}



class _TimeSlotField extends StatelessWidget {

  final String label;

  final int slotIndex;

  final List<DateTime> slots;

  final int minSlotIndex;

  final ValueChanged<int> onChanged;



  const _TimeSlotField({

    required this.label,

    required this.slotIndex,

    required this.slots,

    required this.minSlotIndex,

    required this.onChanged,

  });



  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final index = slotIndex.clamp(minSlotIndex, slots.length - 1);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showModalBottomSheet<int>(
          context: context,
          showDragHandle: true,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: slots.length,
                      itemBuilder: (context, i) {
                        final enabled = i >= minSlotIndex;
                        return ListTile(
                          dense: true,
                          enabled: enabled,
                          title: Text(
                            BookingTimeUtils.formatHm(slots[i]),
                            style: TextStyle(color: enabled ? null : cs.outline),
                          ),
                          trailing: i == index
                              ? Icon(Icons.check, color: cs.primary)
                              : null,
                          onTap: enabled ? () => Navigator.pop(context, i) : null,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.keyboard_arrow_down),
        ),
        child: Text(BookingTimeUtils.formatHm(slots[index])),
      ),
    );
  }
}

