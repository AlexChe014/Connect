import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/bookings/user_booking.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../services/haptics_service.dart';
import '../services/notification_unread_service.dart';
import '../services/sign_out.dart';
import '../utils/media_url_utils.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_network_image.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/chat_avatar.dart';
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
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    NotificationUnreadService.instance.refresh();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {
      // Без версии профиль работает — строку просто не показываем.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const NotificationsScreen(),
      ),
    );
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
    await launchUrl(_privacyPolicyUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _requestAccountDeletion() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Аккаунт создаётся и управляется корпоративной IT-службой. '
          'Мы отправим ей запрос на удаление аккаунта и связанных с ним '
          'данных — обработка занимает до 30 дней.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отправить запрос'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ProfileRepository.instance.requestAccountDeletion();
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Запрос отправлен'),
          content: const Text(
            'IT-служба свяжется с вами по корпоративной почте.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ОК'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Эндпоинт мог ещё не доехать до прода — запасной путь письмом.
      if (mounted) await _requestAccountDeletionByMail();
    }
  }

  Future<void> _requestAccountDeletionByMail() async {
    final email = _optionalField('email', altKeys: ['mail']) ?? '';
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@xondev.ru',
      query:
          'subject=${Uri.encodeComponent('Запрос на удаление аккаунта Connect')}'
          '&body=${Uri.encodeComponent('Прошу удалить мой аккаунт и связанные с ним данные в приложении Connect.\n\n'
          'Учётная запись: $email')}',
    );
    if (!await launchUrl(uri) && mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Не удалось отправить запрос'),
          content: const Text(
            'Отправьте запрос на удаление аккаунта на support@xondev.ru вручную.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ОК'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Выйти'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) await signOut();
  }

  String _formatHm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _iconBadge(IconData icon, Color color) =>
      AppIconBadge(icon: icon, color: color);

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
      if ((phone ?? '').isNotEmpty)
        _infoRow(
          icon: CupertinoIcons.phone_fill,
          color: CupertinoColors.systemGreen.resolveFrom(context),
          label: 'Телефон',
          value: phone!,
        ),
      if ((email ?? '').isNotEmpty)
        _infoRow(
          icon: CupertinoIcons.mail_solid,
          color: CupertinoColors.systemBlue.resolveFrom(context),
          label: 'Email',
          value: email!,
        ),
      if (birthday != null)
        _infoRow(
          icon: CupertinoIcons.gift_fill,
          color: CupertinoColors.systemPink.resolveFrom(context),
          label: 'Дата рождения',
          value: DateFormat('d MMMM yyyy', 'ru_RU').format(birthday),
        ),
    ];

    return SliverPadding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 32,
      ),
      sliver: SliverList.list(
        children: [
          _ProfileHeaderCard(
            avatarUrl: _avatarUrl,
            displayName: _displayName,
            position: position,
            department: department,
            status: status,
            isBirthdayToday:
                birthday != null && _isSameMonthDay(birthday, DateTime.now()),
          ),
          if (contactTiles.isNotEmpty) ...[
            const AppGlassSectionLabel('Контакты'),
            AppGlassSection(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: contactTiles,
            ),
          ],
          const AppGlassSectionLabel('Ближайшие брони'),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
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
                          fontSize: 15,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                  ]
                : _upcomingBookings.map(_bookingTile).toList(),
          ),
          AppGlassSection(
            margin: const EdgeInsets.fromLTRB(16, 28, 16, 8),
            children: [
              CupertinoListTile(
                title: Center(
                  child: Text(
                    'Выйти из аккаунта',
                    style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: _logout,
              ),
            ],
          ),
          _footerLink(
            'Запросить удаление аккаунта',
            onPressed: _requestAccountDeletion,
          ),
          _footerLink(
            'Политика конфиденциальности',
            onPressed: _openPrivacyPolicy,
          ),
          if (_appVersion != null) _versionLabel(_appVersion!),
        ],
      ),
    );
  }

  Widget _bookingTile(UserBooking b) {
    final timeLabel =
        '${DateFormat('dd.MM').format(b.datetimeStart)} • '
        '${_formatHm(b.datetimeStart)}—${_formatHm(b.datetimeEnd)}';
    final subtitleParts = <String>[
      timeLabel,
      if ((b.objectName ?? '').trim().isNotEmpty) b.objectName!.trim(),
    ];
    return CupertinoListTile(
      leading: b.objectImageUrl != null
          ? AppNetworkImage(
              url: b.objectImageUrl,
              width: 29,
              height: 29,
              borderRadius: 7,
              errorIcon: CupertinoIcons.location_solid,
            )
          : _iconBadge(
              CupertinoIcons.location_solid,
              CupertinoColors.systemRed.resolveFrom(context),
            ),
      title: Text(
        b.theme,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitleParts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: () async {
        final changed = await BookingDetailSheet.show(context, bookingId: b.id);
        if (changed == true && mounted) await _loadUpcomingBookings();
      },
    );
  }

  /// Строка «Контактов» как в карточке сотрудника: подпись мелко сверху,
  /// значение под ней — длинный email или номер с добавочным не обрезаются.
  /// Долгое нажатие копирует значение.
  Widget _infoRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: value));
        AppHaptics.selection();
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Скопировано')));
      },
      child: CupertinoListTile(
        leading: _iconBadge(icon, color),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            value,
            // CupertinoListTile форсирует subtitle в 1 строку с "…", если
            // не переопределить maxLines явно.
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }

  /// Неброская ссылка внизу профиля (удаление аккаунта, политика).
  Widget _footerLink(String label, {required VoidCallback onPressed}) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 4),
      minimumSize: const Size(0, 32),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  /// Версия сборки в самом низу профиля: по ней поддержка понимает, какой
  /// билд у пользователя. Долгое нажатие копирует строку.
  Widget _versionLabel(String version) {
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: version));
        AppHaptics.selection();
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Версия скопирована')));
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Версия $version',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }

  /// Колокольчик в шапке с красным счётчиком непрочитанных уведомлений.
  Widget _buildNotificationsButton(BuildContext context) {
    final count = NotificationUnreadService.instance.unreadCount;
    return Semantics(
      button: true,
      label: count > 0 ? 'Уведомления, непрочитанных: $count' : 'Уведомления',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: _openNotifications,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              CupertinoIcons.bell,
              size: AppSliverTitleBar.iconSize,
              color: CupertinoColors.label.resolveFrom(context),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                right: -8,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground.resolveFrom(context),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(height: 360),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: AppHaptics.onRefresh(_loadProfile),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      AppSliverTitleBar(
                        title: const Text('Профиль'),
                        blur: blur,
                        trailing: ListenableBuilder(
                          listenable: NotificationUnreadService.instance,
                          builder: (context, _) =>
                              _buildNotificationsButton(context),
                        ),
                      ),
                      _buildSliverBody(context),
                    ],
                  ),
                ),
              ),
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
    this.department,
    this.status,
    this.isBirthdayToday = false,
  });

  final String? avatarUrl;
  final String displayName;
  final String? position;
  final String? department;
  final String? status;
  final bool isBirthdayToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(24),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  MemberAvatar(
                    displayName: displayName,
                    avatarUrl: avatarUrl,
                    radius: 34,
                  ),
                  if (isBirthdayToday) const BirthdayBadge(radius: 34),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if ((position ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        position!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                    if ((department ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        department!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.tertiaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                    if ((status ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.tertiarySystemFill.resolveFrom(
                            context,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
