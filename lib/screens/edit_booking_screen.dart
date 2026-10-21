import 'package:flutter/cupertino.dart';

import '../models/bookings/booking_detail.dart';
import '../models/bookings/update_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../utils/booking_time_utils.dart';
import '../widgets/app_glass.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/selected_staff_field.dart';

/// Редактирование брони (`POST /booking/update/{id}`).
///
/// Бэкенд на данный момент принимает изменение только темы, описания,
/// ссылки и участников — дата, время и дни повторения не редактируются,
/// поэтому здесь они только показаны для контекста, недоступны для правки.
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

  @override
  void initState() {
    super.initState();
    final d = widget.detail;
    _themeController = TextEditingController(text: d.theme);
    _descriptionController = TextEditingController(text: d.description ?? '');
    _linkController = TextEditingController(text: d.link ?? '');
    _participants = List<StaffUser>.from(d.participants);
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

    setState(() => _isSubmitting = true);
    try {
      await BookingsRepository.instance.updateBooking(
        bookingId: widget.detail.id,
        request: UpdateBookingRequest(
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

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
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
                color: CupertinoColors.systemRed,
                label: 'Место',
                value: place,
                valueMaxWidth: 200,
              ),
            BookingFieldRow(
              icon: CupertinoIcons.link,
              color: CupertinoColors.systemBlue,
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
            BookingPickerRow(
              icon: CupertinoIcons.calendar,
              color: CupertinoColors.systemOrange,
              label: 'Дата',
              value: BookingTimeUtils.formatDateShort(detail.datetimeStart),
            ),
            BookingPickerRow(
              icon: CupertinoIcons.clock_fill,
              color: CupertinoColors.systemOrange,
              label: 'Время',
              value:
                  '${BookingTimeUtils.formatHm(detail.datetimeStart)}–'
                  '${BookingTimeUtils.formatHm(detail.datetimeEnd)}',
            ),
            if (days != null)
              BookingPickerRow(
                icon: CupertinoIcons.repeat,
                color: CupertinoColors.systemPurple,
                label: 'Повтор',
                value: days,
                valueMaxWidth: 200,
              ),
          ],
        ),
        BookingFootnote(
          [
            'Дату, время и повтор пока нельзя изменить.',
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
