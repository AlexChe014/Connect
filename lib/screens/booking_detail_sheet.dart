import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bookings/booking_detail.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/bookable_object_preview.dart';
import '../widgets/chat_avatar.dart';
import 'edit_booking_screen.dart';

/// Нижняя панель с деталями брони (`GET /booking/get/{id}`).
class BookingDetailSheet extends StatefulWidget {
  const BookingDetailSheet({super.key, required this.bookingId});

  final int bookingId;

  /// `true` — бронь изменена или удалена.
  static Future<bool?> show(BuildContext context, {required int bookingId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
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
      final detail = await BookingsRepository.instance.getBookingById(
        widget.bookingId,
      );
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
      final ok =
          await showDialog<bool>(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
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

  /// Возвращает описание, если это ссылка на встречу (http/https), иначе null.
  String? _meetingLinkOrNull(String description) {
    if (!description.startsWith('http://') &&
        !description.startsWith('https://')) {
      return null;
    }
    return Uri.tryParse(description) != null ? description : null;
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  Widget _valueRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return CupertinoListTile(
      leading: _iconBadge(icon, color),
      title: Text(label),
      additionalInfo: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _textRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return CupertinoListTile(
      leading: _iconBadge(icon, color),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          value,
          style: const TextStyle(color: CupertinoColors.label),
        ),
      ),
    );
  }

  Widget _linkRow(String url) {
    return CupertinoListTile(
      leading: _iconBadge(
        CupertinoIcons.video_camera_solid,
        CupertinoColors.systemBlue,
      ),
      title: const Text('Ссылка на встречу'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: CupertinoColors.systemBlue),
        ),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: () => _openLink(url),
    );
  }

  Widget _participantsSection(List<StaffUser> users) {
    if (users.isEmpty) return const SizedBox.shrink();

    return CupertinoListSection.insetGrouped(
      header: const Text('Участники'),
      children: users.map((user) {
        return CupertinoListTile(
          leading: MemberAvatar(
            displayName: user.fullName,
            avatarUrl: user.avatarUrl,
            radius: 16,
          ),
          title: Text(user.fullName),
          subtitle: (user.email ?? '').isNotEmpty ? Text(user.email!) : null,
        );
      }).toList(),
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
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: AppLoadingIndicator(size: 32),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AppEmptyState(
                    icon: Icons.error_outline,
                    message: _error!,
                    onRetry: _load,
                  ),
                )
              else if (detail != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                    detail.theme,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.label,
                    ),
                  ),
                ),
                if (detail.object != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: BookableObjectPreview(
                      object: detail.object!,
                      compact: true,
                    ),
                  ),
                CupertinoListSection.insetGrouped(
                  children: [
                    _valueRow(
                      icon: CupertinoIcons.clock_fill,
                      color: CupertinoColors.systemOrange,
                      label: 'Дата и время',
                      value:
                          '${_formatDate(detail.datetimeStart)}, '
                          '${_formatHm(detail.datetimeStart)}—${_formatHm(detail.datetimeEnd)}',
                    ),
                    _valueRow(
                      icon: CupertinoIcons.location_solid,
                      color: CupertinoColors.systemRed,
                      label: 'Объект',
                      value: detail.displayObjectName,
                    ),
                    if (detail.isPrivate)
                      _valueRow(
                        icon: CupertinoIcons.lock_fill,
                        color: CupertinoColors.systemGrey,
                        label: 'Доступ',
                        value: 'Приватное',
                      ),
                    if (detail.isRecurring) ...[
                      _valueRow(
                        icon: CupertinoIcons.repeat,
                        color: CupertinoColors.systemPurple,
                        label: 'Повторение',
                        value: detail.recurring?.type ?? 'да',
                      ),
                      if ((detail.recurring?.endDate ?? '').isNotEmpty)
                        _valueRow(
                          icon: CupertinoIcons.calendar,
                          color: CupertinoColors.systemPurple,
                          label: 'Повторять до',
                          value: detail.recurring!.endDate!,
                        ),
                    ],
                  ],
                ),
                if ((detail.description ?? '').trim().isNotEmpty ||
                    (detail.link ?? '').trim().isNotEmpty)
                  CupertinoListSection.insetGrouped(
                    children: [
                      if ((detail.description ?? '').trim().isNotEmpty)
                        if (_meetingLinkOrNull(detail.description!.trim())
                            case final link?)
                          _linkRow(link)
                        else
                          _textRow(
                            icon: CupertinoIcons.doc_text_fill,
                            color: CupertinoColors.systemGrey,
                            label: 'Описание',
                            value: detail.description!.trim(),
                          ),
                      if ((detail.link ?? '').trim().isNotEmpty)
                        _linkRow(detail.link!.trim()),
                    ],
                  ),
                _participantsSection(detail.participants),
                CupertinoListSection.insetGrouped(
                  children: [
                    CupertinoListTile(
                      leading: _iconBadge(
                        CupertinoIcons.pencil,
                        CupertinoColors.systemBlue,
                      ),
                      title: Text(
                        'Изменить',
                        style: TextStyle(
                          color: detail.isPassed
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.systemBlue,
                        ),
                      ),
                      trailing: detail.isPassed
                          ? null
                          : const CupertinoListTileChevron(),
                      onTap: detail.isPassed ? null : _openEdit,
                    ),
                    CupertinoListTile(
                      leading: _iconBadge(
                        CupertinoIcons.delete_solid,
                        CupertinoColors.systemRed,
                      ),
                      title: Text(
                        'Удалить',
                        style: TextStyle(
                          color: detail.isPassed
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.systemRed,
                        ),
                      ),
                      trailing: _isDeleting
                          ? const CupertinoActivityIndicator()
                          : null,
                      onTap: detail.isPassed || _isDeleting ? null : _delete,
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
