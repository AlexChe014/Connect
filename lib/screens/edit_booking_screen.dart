import 'package:flutter/material.dart';

import '../models/bookings/booking_detail.dart';
import '../models/bookings/update_booking_request.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../widgets/bookable_object_preview.dart';
import '../widgets/selected_staff_field.dart';

/// Редактирование брони (`POST /booking/update/{id}`).
class EditBookingScreen extends StatefulWidget {
  const EditBookingScreen({
    super.key,
    required this.detail,
  });

  final BookingDetail detail;

  @override
  State<EditBookingScreen> createState() => _EditBookingScreenState();
}

class _EditBookingScreenState extends State<EditBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _themeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _linkController;
  late List<StaffUser> _participants;
  bool _updateAll = false;
  bool _isSubmitting = false;

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
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await BookingsRepository.instance.updateBooking(
        bookingId: widget.detail.id,
        request: UpdateBookingRequest(
          theme: _themeController.text.trim(),
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
    final detail = widget.detail;
    final object = detail.object;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Изменить бронь'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (object != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: BookableObjectPreview(object: object),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _themeController,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(context, 'Тема *'),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return 'Укажите тему';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: _decoration(context, 'Описание'),
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
            if (detail.isRecurring) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Изменить всю серию повторений'),
                value: _updateAll,
                onChanged: (v) => setState(() => _updateAll = v),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
