import 'package:flutter/material.dart';

import '../models/bookings/booking_detail.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../widgets/bookable_object_preview.dart';
import 'edit_booking_screen.dart';

/// Нижняя панель с деталями брони (`GET /booking/get/{id}`).
class BookingDetailSheet extends StatefulWidget {
  const BookingDetailSheet({
    super.key,
    required this.bookingId,
  });

  final int bookingId;

  /// `true` — бронь изменена или удалена.
  static Future<bool?> show(
    BuildContext context, {
    required int bookingId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: BookingDetailSheet(bookingId: bookingId),
      ),
    );
  }

  @override
  State<BookingDetailSheet> createState() => _BookingDetailSheetState();
}

class _BookingDetailSheetState extends State<BookingDetailSheet> {
  BookingDetail? _detail;
  bool _isLoading = true;
  String? _error;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final detail = await BookingsRepository.instance.getBookingById(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openEdit() async {
    final detail = _detail;
    if (detail == null) return;

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => EditBookingScreen(detail: detail),
      ),
    );

    if (updated == true) {
      await _load();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    final detail = _detail;
    if (detail == null || _isDeleting) return;

    bool deleteAll = false;
    if (detail.isRecurring) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Удалить бронь?'),
          content: const Text('Выберите, что удалить из серии повторений.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'one'),
              child: const Text('Только эту'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('Всю серию'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      deleteAll = choice == 'all';
    } else {
      final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Удалить бронь?'),
              content: const Text('Это действие нельзя отменить.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Удалить'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }

    setState(() => _isDeleting = true);
    try {
      await BookingsRepository.instance.deleteBooking(
        bookingId: detail.id,
        deleteAll: deleteAll,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  String _formatHm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  Widget _infoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _participantsSection(List<StaffUser> users) {
    if (users.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Участники',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(height: 8),
        ...users.map((user) {
          final hasAvatar = (user.avatarUrl ?? '').trim().isNotEmpty;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: hasAvatar
                      ? ClipOval(
                          child: Image.network(
                            user.avatarUrl!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Text(
                              user.initials,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                      : Text(user.initials, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      if ((user.email ?? '').isNotEmpty)
                        Text(
                          user.email!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Column(
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Повторить')),
                  ],
                )
              else if (detail != null) ...[
                Text(
                  detail.displayObjectName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                if (detail.object != null)
                  BookableObjectPreview(object: detail.object!, compact: true),
                const SizedBox(height: 16),
                _infoRow('Тема', detail.theme),
                _infoRow(
                  'Дата и время',
                  '${_formatDate(detail.datetimeStart)}, '
                  '${_formatHm(detail.datetimeStart)}—${_formatHm(detail.datetimeEnd)}',
                ),
                if (detail.isPrivate) _infoRow('Доступ', 'Приватное'),
                if ((detail.description ?? '').trim().isNotEmpty)
                  _infoRow('Описание', detail.description!.trim()),
                if ((detail.link ?? '').trim().isNotEmpty)
                  _infoRow('Ссылка', detail.link!.trim()),
                if (detail.isRecurring) ...[
                  _infoRow('Повторение', detail.recurring?.type ?? 'да'),
                  if ((detail.recurring?.endDate ?? '').isNotEmpty)
                    _infoRow('Повторять до', detail.recurring!.endDate!),
                ],
                _participantsSection(detail.participants),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: detail.isPassed ? null : _openEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Изменить'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: detail.isPassed || _isDeleting ? null : _delete,
                        icon: _isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_outline),
                        label: const Text('Удалить'),
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
