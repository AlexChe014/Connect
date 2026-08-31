import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bookings/user_booking.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/notifications_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../utils/media_url_utils.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_network_image.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/menu_button.dart';
import '../widgets/status_bubble.dart';
import 'booking_detail_sheet.dart';
import 'notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  List<UserBooking> _upcomingBookings = const [];
  bool _bookingsLoading = false;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadUnreadNotifications();
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final count = await NotificationsRepository.instance.getUnreadCount();
      if (!mounted) return;
      setState(() => _unreadNotifications = count);
    } catch (_) {
      // Эндпоинт может быть ещё не готов на бэкенде — просто не показываем бейдж.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const NotificationsScreen(),
      ),
    );
    _loadUnreadNotifications();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final stored = await AuthService.instance.getStoredUser();
      final api = await ProfileRepository.instance.getProfile();

      if (mounted) {
        setState(() {
          _profile = api.isNotEmpty ? api : (stored ?? {});
          _isLoading = false;
        });
      }
      await _loadUpcomingBookings();
    } catch (_) {
      final stored = await AuthService.instance.getStoredUser();

      if (mounted) {
        setState(() {
          _profile = stored ?? {};
          _isLoading = false;
        });
      }
      await _loadUpcomingBookings();
    }
  }

  int? get _userId {
    final p = _profile;
    if (p == null) return null;
    final raw = p['id'] ?? p['user_id'];
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  Future<void> _loadUpcomingBookings() async {
    final userId = _userId;
    if (userId == null) return;

    setState(() => _bookingsLoading = true);
    try {
      final now = DateTime.now();
      final weekEnd = now.add(const Duration(days: 7));
      final items = await BookingsRepository.instance.getBookingsByUserForRange(
        userId: userId,
        datetimeStartSeconds: now.millisecondsSinceEpoch ~/ 1000,
        datetimeEndSeconds: weekEnd.millisecondsSinceEpoch ~/ 1000,
      );

      final upcoming = items.where((b) => !b.datetimeEnd.isBefore(now)).toList()
        ..sort((a, b) => a.datetimeStart.compareTo(b.datetimeStart));

      if (!mounted) return;
      setState(() {
        _upcomingBookings = upcoming;
        _bookingsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _upcomingBookings = const [];
        _bookingsLoading = false;
      });
    }
  }

  String? get _avatarUrl => MediaUrlUtils.normalizeFirstUrl(_profile?['media']);

  String get _displayName {
    final p = _profile;
    if (p == null) return 'Пользователь';
    final s = (p['surname'] ?? '').toString().trim();
    final n = (p['name'] ?? '').toString().trim();
    final patronymic =
        (p['patronymic'] ?? p['father_name'] ?? p['middlename'] ?? '')
            .toString()
            .trim();
    final parts = [
      if (s.isNotEmpty) s,
      if (n.isNotEmpty) n,
      if (patronymic.isNotEmpty) patronymic,
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    final e = (p['email'] ?? '').toString().trim();
    if (e.isNotEmpty) return e;
    return 'Пользователь';
  }

  String? _labelFromValue(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      for (final key in ['name', 'title', 'label']) {
        final v = raw[key];
        if (v != null) {
          final t = v.toString().trim();
          if (t.isNotEmpty) return t;
        }
      }
      return null;
    }
    final t = raw.toString().trim();
    if (t.isEmpty || t.startsWith('{')) return null;
    return t;
  }

  String? _fieldLabel(String key, {List<String> altKeys = const []}) {
    final p = _profile;
    if (p == null) return null;
    for (final k in [key, ...altKeys]) {
      final label = _labelFromValue(p[k]);
      if (label != null) return label;
    }
    return null;
  }

  String? get _statusLabel {
    return _fieldLabel(
      'work_status',
      altKeys: ['employment_status', 'status_label', 'status'],
    );
  }

  String? get _departmentLabel {
    return _fieldLabel(
      'department',
      altKeys: ['department_name', 'dep_name', 'dep'],
    );
  }

  String? _optionalField(String key, {List<String> altKeys = const []}) {
    return _fieldLabel(key, altKeys: altKeys);
  }

  DateTime? _parseBirthday() {
    final p = _profile;
    if (p == null) return null;
    final raw = p['birthday'] ?? p['birth_date'] ?? p['date_of_birth'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final formats = ['dd.MM.yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy'];
    for (final f in formats) {
      try {
        return DateFormat(f).parseStrict(s);
      } catch (_) {}
    }
    return DateTime.tryParse(s.contains('T') ? s : s.replaceFirst(' ', 'T'));
  }

  bool _isSameMonthDay(DateTime a, DateTime b) =>
      a.month == b.month && a.day == b.day;

  static final Uri _privacyPolicyUri = Uri.parse(
    'https://xon-connect.ru/include/licenses_detail.php',
  );

  Future<void> _openPrivacyPolicy() async {
    await launchUrl(
      _privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _requestAccountDeletion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление аккаунта'),
        content: const Text(
          'Аккаунт создаётся и управляется корпоративной IT-службой. '
          'Мы откроем письмо с запросом на удаление — его нужно отправить '
          'в поддержку, обработка занимает до 30 дней.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final email = _optionalField('email', altKeys: ['mail']) ?? '';
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@xondev.ru',
      query:
          'subject=${Uri.encodeComponent('Запрос на удаление аккаунта Connect')}'
          '&body=${Uri.encodeComponent(
            'Прошу удалить мой аккаунт и связанные с ним данные в приложении Connect.\n\n'
            'Учётная запись: $email',
          )}',
    );
    if (!await launchUrl(uri) && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Не удалось открыть почту'),
          content: const Text(
            'Отправьте запрос на удаление аккаунта на support@xondev.ru вручную.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ОК'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await PushNotificationService.instance.unregisterCurrentDevice();
      await AuthService.instance.logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      }
    }
  }

  String _formatHm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
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

  Widget _buildSliverBody(BuildContext context) {
    if (_isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: AppPageLoader(),
      );
    }

    final birthday = _parseBirthday();
    final email = _optionalField('email', altKeys: ['mail']);
    final phone = _optionalField(
      'phone',
      altKeys: ['mobile', 'tel', 'telephone'],
    );
    final position = _optionalField(
      'position',
      altKeys: ['job_title', 'post', 'appointment'],
    );
    final department = _departmentLabel;
    final status = _statusLabel;
    final contactTiles = <Widget>[
      if (birthday != null)
        CupertinoListTile(
          leading: _iconBadge(
            CupertinoIcons.gift_fill,
            CupertinoColors.systemPink,
          ),
          title: const Text('Дата рождения'),
          additionalInfo: Text(DateFormat('dd.MM.yyyy').format(birthday)),
        ),
      if ((email ?? '').isNotEmpty)
        CupertinoListTile(
          leading: _iconBadge(
            CupertinoIcons.mail_solid,
            CupertinoColors.systemBlue,
          ),
          title: const Text('Email'),
          additionalInfo: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              email!,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      if ((phone ?? '').isNotEmpty)
        CupertinoListTile(
          leading: _iconBadge(
            CupertinoIcons.phone_fill,
            CupertinoColors.systemGreen,
          ),
          title: const Text('Телефон'),
          additionalInfo: Text(phone!),
        ),
      if ((department ?? '').isNotEmpty)
        CupertinoListTile(
          leading: _iconBadge(
            CupertinoIcons.building_2_fill,
            CupertinoColors.systemIndigo,
          ),
          title: const Text('Отдел'),
          additionalInfo: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              department!,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
    ];

    return SliverPadding(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      sliver: SliverList.list(
        children: [
          _ProfileHeaderCard(
            avatarUrl: _avatarUrl,
            displayName: _displayName,
            position: position,
            status: status,
            isBirthdayToday: birthday != null && _isSameMonthDay(
              birthday,
              DateTime.now(),
            ),
          ),
          if (contactTiles.isNotEmpty) ...[
            const SizedBox(height: 20),
            CupertinoListSection.insetGrouped(
              header: const Text('Контакты'),
              children: contactTiles,
            ),
          ],
          const SizedBox(height: 20),
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                leading: _iconBadge(
                  CupertinoIcons.bell_fill,
                  CupertinoColors.systemRed,
                ),
                title: const Text('Уведомления'),
                additionalInfo: _unreadNotifications > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemRed,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _unreadNotifications > 99
                              ? '99+'
                              : '$_unreadNotifications',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white,
                          ),
                        ),
                      )
                    : null,
                trailing: const CupertinoListTileChevron(),
                onTap: _openNotifications,
              ),
            ],
          ),
          const SizedBox(height: 20),
          CupertinoListSection.insetGrouped(
            header: const Text('Ближайшие брони'),
            children: _bookingsLoading
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                  ]
                : _upcomingBookings.isEmpty
                ? [
                    CupertinoListTile(
                      title: Text(
                        'На ближайшие 7 дней бронирований нет',
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                  ]
                : _upcomingBookings.map((b) {
                    final timeLabel =
                        '${DateFormat('dd.MM').format(b.datetimeStart)} • '
                        '${_formatHm(b.datetimeStart)}—${_formatHm(b.datetimeEnd)}';
                    final subtitleParts = <String>[
                      timeLabel,
                      if ((b.objectName ?? '').trim().isNotEmpty)
                        b.objectName!.trim(),
                    ];

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        final changed = await BookingDetailSheet.show(
                          context,
                          bookingId: b.id,
                        );
                        if (changed == true && mounted) {
                          await _loadUpcomingBookings();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: DefaultTextStyle(
                          style: TextStyle(
                            fontFamily: '.SF Pro Text',
                            decoration: TextDecoration.none,
                            color: CupertinoColors.label.resolveFrom(context),
                            fontSize: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              b.objectImageUrl != null
                                  ? AppNetworkImage(
                                      url: b.objectImageUrl,
                                      width: 29,
                                      height: 29,
                                      borderRadius: 7,
                                      errorIcon: CupertinoIcons.location_solid,
                                    )
                                  : _iconBadge(
                                      CupertinoIcons.location_solid,
                                      CupertinoColors.systemRed,
                                    ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b.theme,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        subtitleParts.join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: CupertinoColors.secondaryLabel
                                              .resolveFrom(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Icon(
                                  CupertinoIcons.chevron_forward,
                                  size: 16,
                                  color: CupertinoColors.tertiaryLabel
                                      .resolveFrom(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
          ),
          const SizedBox(height: 20),
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                leading: _iconBadge(
                  CupertinoIcons.doc_text_fill,
                  CupertinoColors.systemGrey,
                ),
                title: const Text('Политика конфиденциальности'),
                trailing: const CupertinoListTileChevron(),
                onTap: _openPrivacyPolicy,
              ),
            ],
          ),
          const SizedBox(height: 20),
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                title: const Center(
                  child: Text(
                    'Выйти из аккаунта',
                    style: TextStyle(
                      color: CupertinoColors.systemRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: _logout,
              ),
              CupertinoListTile(
                title: const Center(
                  child: Text(
                    'Запросить удаление аккаунта',
                    style: TextStyle(
                      color: CupertinoColors.systemRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: _requestAccountDeletion,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Профиль'),
                leading: const MenuButton(),
                backgroundColor: CupertinoColors.systemGroupedBackground,
                border: null,
              ),
              _buildSliverBody(context),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.avatarUrl,
    required this.displayName,
    this.position,
    this.status,
    this.isBirthdayToday = false,
  });

  final String? avatarUrl;
  final String displayName;
  final String? position;
  final String? status;
  final bool isBirthdayToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(
                  displayName: displayName,
                  avatarUrl: avatarUrl,
                  radius: 44,
                ),
                if (isBirthdayToday) const BirthdayBadge(radius: 44),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            if ((position ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                position!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
            if ((status ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              StatusBubble(text: status!),
            ],
          ],
        ),
      ),
    );
  }
}
