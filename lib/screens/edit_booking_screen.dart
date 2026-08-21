import 'package:flutter/cupertino.dart';

import '../models/bookings/booking_detail.dart';
import '../models/bookings/update_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../widgets/bookable_object_preview.dart';
import '../widgets/selected_staff_field.dart';

/// Редактирование брони (`POST /booking/update/{id}`).
class EditBookingScreen extends StatefulWidget {
  const EditBookingScreen({super.key, required this.detail});

  final BookingDetail detail;

  @override
  State<EditBookingScreen> createState() => _EditBookingScreenState();
}

class _EditBookingScreenState extends State<EditBookingScreen> {
  late final TextEditingController _themeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _linkController;
  late List<StaffUser> _participants;
  bool _updateAll = false;
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
    _updateAll = d.isRecurring;
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
          updateAll: widget.detail.isRecurring && _updateAll ? true : null,
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
    final object = detail.object;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Изменить бронь'),
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
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const CupertinoActivityIndicator()
              : const Text(
                  'Сохранить',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
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
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              if (object != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: CupertinoColors.secondarySystemGroupedBackground
                          .resolveFrom(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: BookableObjectPreview(object: object),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              CupertinoFormSection.insetGrouped(
                header: const Text('О БРОНИ'),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _themeController,
                    prefix: const Text('Тема'),
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
                  CupertinoTextFormFieldRow(
                    controller: _linkController,
                    prefix: const Text('Ссылка'),
                    placeholder: 'https://…',
                    keyboardType: TextInputType.url,
                    textAlign: TextAlign.end,
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
                  onUserAdded: (user) => setState(
                    () => _participants = [..._participants, user],
                  ),
                  onUserRemoved: (user) => setState(
                    () => _participants = _participants
                        .where((p) => p.id != user.id)
                        .toList(),
                  ),
                ),
              ),
              if (detail.isRecurring) ...[
                const SizedBox(height: 20),
                CupertinoFormSection.insetGrouped(
                  children: [
                    CupertinoListTile(
                      title: const Text('Изменить всю серию повторений'),
                      trailing: CupertinoSwitch(
                        value: _updateAll,
                        onChanged: (v) => setState(() => _updateAll = v),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
