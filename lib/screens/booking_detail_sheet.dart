import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/bookings/booking_detail.dart';
import '../models/staff_user.dart';
import '../repositories/bookings_repository.dart';
import '../utils/booking_time_utils.dart';
import '../utils/connector_link_join.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/booking_pickers.dart';
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
      useSafeArea: true,
      // Ручка рисуется внутри шторки: системная лежит на отдельной
      // полосе, и цветное пятно под ней обрывалось ровной границей.
      showDragHandle: false,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
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

    var updateAll = false;
    if (detail.isRecurring) {
      final choice = await showRecurringScopeSheet(
        context: context,
        title: 'Изменить бронь?',
        message: 'Выберите, что изменить из серии повторений.',
      );
      if (choice == null) return;
      if (!mounted) return;
      updateAll = choice;
    }

    final updated = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (context) =>
            EditBookingScreen(detail: detail, updateAll: updateAll),
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
      final choice = await showRecurringScopeSheet(
        context: context,
        title: 'Удалить бронь?',
        message: 'Выберите, что удалить из серии повторений.',
        isDestructive: true,
      );
      if (choice == null) return;
      if (!mounted) return;
      deleteAll = choice;
    } else {
      final ok =
          await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Удалить бронь?'),
              content: const Text('Это действие нельзя отменить.'),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
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

  String _formatWhen(BookingDetail d) {
    final day = DateFormat('EEEE, d MMMM', 'ru_RU').format(d.datetimeStart);
    final capitalized = day.isEmpty
        ? day
        : day[0].toUpperCase() + day.substring(1);
    return '$capitalized · '
        '${BookingTimeUtils.formatHm(d.datetimeStart)}–'
        '${BookingTimeUtils.formatHm(d.datetimeEnd)}';
  }

  /// Возвращает описание, если это ссылка на встречу (http/https), иначе null.
  String? _meetingLinkOrNull(String description) {
    if (!description.startsWith('http://') &&
        !description.startsWith('https://')) {
      return null;
    }
    return Uri.tryParse(description) != null ? description : null;
  }

  Future<void> _openLink(String url) => joinMeetingLink(context, url);

  /// Строка деталей: мельче строк форм (15 вместо 17) — это справка
  /// под заголовком, она не должна спорить с темой встречи.
  Widget _detailTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return CupertinoListTile(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 14, 8),
      leading: AppIconBadge(icon: icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
      additionalInfo: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
      trailing: onTap == null ? null : const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }

  Widget _valueRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return _detailTile(icon: icon, color: color, label: label, value: value);
  }

  Widget _linkRow(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return _detailTile(
      icon: CupertinoIcons.link,
      color: CupertinoColors.systemBlue,
      label: 'Ссылка',
      value: host.isEmpty ? 'Открыть' : host,
      onTap: () => _openLink(url),
    );
  }

  List<Widget> _participantsSection(List<StaffUser> users) {
    if (users.isEmpty) return const [];

    return [
      AppGlassSectionLabel('Участники (${users.length})'),
      AppGlassSection(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: users.map((user) {
          return CupertinoListTile(
            leading: MemberAvatar(
              displayName: user.fullName,
              avatarUrl: user.avatarUrl,
              radius: 16,
            ),
            title: Text(
              user.fullName,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            subtitle: (user.email ?? '').isNotEmpty
                ? Text(user.email!, style: const TextStyle(fontSize: 12))
                : null,
          );
        }).toList(),
      ),
    ];
  }

  /// Ссылка на встречу: отдельное поле или описание, целиком состоящее
  /// из URL (так её сохраняют старые брони).
  String? _meetingLink(BookingDetail detail) {
    final link = (detail.link ?? '').trim();
    if (link.isNotEmpty) return link;
    return _meetingLinkOrNull((detail.description ?? '').trim());
  }

  Widget _buildHeader(BookingDetail detail) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    // «Повторяется» не дублируем — повторение есть строкой в деталях.
    final chips = <Widget>[
      if (detail.isPassed)
        const _HeaderChip(icon: CupertinoIcons.checkmark_alt, text: 'Прошла'),
      if (detail.isPrivate)
        const _HeaderChip(icon: CupertinoIcons.lock_fill, text: 'Приватная'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.theme,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: label,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatWhen(detail),
                  style: TextStyle(fontSize: 15, color: secondary),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: chips),
                ],
              ],
            ),
          ),
          // Прошедшую бронь менять нельзя — кнопку не показываем вовсе,
          // а не выводим серой.
          if (!detail.isPassed) ...[
            const SizedBox(width: 12),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              minimumSize: Size.zero,
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius: BorderRadius.circular(18),
              onPressed: _openEdit,
              child: Text(
                'Изменить',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: label,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Подключение — единственное действие, ради которого карточку
  /// открывают перед встречей, поэтому крупная синяя кнопка.
  List<Widget> _buildJoinButton(BookingDetail detail, String? meetingLink) {
    // Опоздавшим нужно подключаться до окончания встречи, а сервер
    // помечает is_passed уже после её начала.
    if (meetingLink == null || !DateTime.now().isBefore(detail.datetimeEnd)) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: CupertinoButton(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
          onPressed: () => _openLink(meetingLink),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.video_camera_solid,
                size: 20,
                color: CupertinoColors.white,
              ),
              SizedBox(width: 8),
              Text(
                'Подключиться',
                style: TextStyle(
                  color: CupertinoColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDetails(BookingDetail detail) {
    final description = (detail.description ?? '').trim();
    final link = (detail.link ?? '').trim();
    final descriptionIsLink =
        description.isNotEmpty && _meetingLinkOrNull(description) != null;

    final rows = <Widget>[
      if (detail.displayObjectName.trim().isNotEmpty)
        _valueRow(
          icon: CupertinoIcons.location_solid,
          color: CupertinoColors.systemRed,
          label: 'Место',
          value: detail.displayObjectName,
        ),
      if (detail.isRecurring) ...[
        _valueRow(
          icon: CupertinoIcons.repeat,
          color: CupertinoColors.systemPurple,
          label: 'Повтор',
          value: detail.recurring?.label(detail.datetimeStart) ?? 'Да',
        ),
        if (detail.recurring?.endDateLabel case final endDate?)
          _valueRow(
            icon: CupertinoIcons.calendar,
            color: CupertinoColors.systemPurple,
            label: 'До',
            value: endDate,
          ),
      ],
      if (link.isNotEmpty)
        _linkRow(link)
      else if (descriptionIsLink)
        _linkRow(description),
    ];

    return [
      if (rows.isNotEmpty) AppGlassSection(children: rows),
      if (description.isNotEmpty && !descriptionIsLink) ...[
        const AppGlassSectionLabel('Описание'),
        BookingGlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Text(
            description,
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.SF Pro Text',
        decoration: TextDecoration.none,
        color: CupertinoColors.label.resolveFrom(context),
        fontSize: 16,
      ),
      child: Stack(
        children: [
          const AppGlassGlow(height: 300),
          // Positioned, а не Align: Align растягивается на всю высоту,
          // и шторка вместе с ним уезжала под статус-бар.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 30, bottom: 24),
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
                          icon: CupertinoIcons.exclamationmark_circle,
                          message: _error!,
                          onRetry: _load,
                        ),
                      )
                    else if (detail != null) ...[
                      _buildHeader(detail),
                      ..._buildJoinButton(detail, _meetingLink(detail)),
                      ..._buildDetails(detail),
                      ..._participantsSection(detail.participants),
                      if (!detail.isPassed)
                        AppGlassSection(
                          margin: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                          children: [
                            CupertinoListTile(
                              title: Center(
                                child: _isDeleting
                                    ? const CupertinoActivityIndicator()
                                    : Text(
                                        'Удалить бронь',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: CupertinoColors.systemRed
                                              .resolveFrom(context),
                                        ),
                                      ),
                              ),
                              onTap: _isDeleting ? null : _delete,
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Метка состояния под заголовком: прошла, приватная, повторяется.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: secondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}
