import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_icons.dart';
import '../models/bookings/user_booking.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../utils/media_url_utils.dart';
import 'booking_detail_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

      final upcoming = items
          .where((b) => !b.datetimeEnd.isBefore(now))
          .toList()
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

  String get _initials {
    final p = _profile;
    if (p == null) return '?';
    final parts = <String>[];
    for (final key in ['surname', 'name']) {
      final t = (p[key] ?? '').toString().trim();
      if (t.isNotEmpty) parts.add(t.substring(0, 1));
    }
    if (parts.isEmpty) {
      final e = (p['email'] ?? '').toString().trim();
      if (e.isNotEmpty) return e[0].toUpperCase();
      return '?';
    }
    return parts.take(2).join().toUpperCase();
  }

  String get _displayName {
    final p = _profile;
    if (p == null) return 'Пользователь';
    final s = (p['surname'] ?? '').toString().trim();
    final n = (p['name'] ?? '').toString().trim();
    if (s.isNotEmpty && n.isNotEmpty) return '$s $n';
    if (n.isNotEmpty) return n;
    if (s.isNotEmpty) return s;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ProfileHeader(
                    avatarUrl: _avatarUrl,
                    initials: _initials,
                    displayName: _displayName,
                    position: _optionalField('position'),
                    birthday: _parseBirthday(),
                    email: _optionalField('email', altKeys: ['mail']),
                    phone: _optionalField('phone', altKeys: ['mobile', 'tel', 'telephone']),
                    status: _statusLabel,
                  ),
                  if (_bookingsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_upcomingBookings.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Ближайшие брони',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    ..._upcomingBookings.map(
                      (b) => _UpcomingBookingTile(
                        booking: b,
                        timeLabel:
                            '${DateFormat('dd.MM').format(b.datetimeStart)} • '
                            '${_formatHm(b.datetimeStart)}—${_formatHm(b.datetimeEnd)}',
                        onTap: () async {
                          final changed = await BookingDetailSheet.show(
                            context,
                            bookingId: b.id,
                          );
                          if (changed == true && mounted) {
                            await _loadUpcomingBookings();
                          }
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: AppIcon(
                      AppIcons.logout,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: const Text('Выйти из аккаунта'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final String displayName;
  final String? position;
  final DateTime? birthday;
  final String? email;
  final String? phone;
  final String? status;

  const _ProfileHeader({
    required this.avatarUrl,
    required this.initials,
    required this.displayName,
    this.position,
    this.birthday,
    this.email,
    this.phone,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAvatar = (avatarUrl ?? '').trim().isNotEmpty;
    final initialsStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: CircleAvatar(
                radius: 44,
                backgroundColor: cs.primaryContainer,
                child: hasAvatar
                    ? ClipOval(
                        child: Image.network(
                          avatarUrl!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Text(initials, style: initialsStyle),
                        ),
                      )
                    : Text(initials, style: initialsStyle),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if ((position ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      position!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (birthday != null)
                    _InfoIconRow(
                      icon: const AppIcon(AppIcons.birthdayCake, size: 18),
                      text: DateFormat('dd.MM.yyyy').format(birthday!),
                    ),
                  if ((email ?? '').isNotEmpty)
                    _InfoIconRow(
                      icon: const AppIcon(AppIcons.profileMail, size: 18),
                      text: email!,
                    ),
                  if ((phone ?? '').isNotEmpty)
                    _InfoIconRow(
                      icon: const AppIcon(AppIcons.phone, size: 18),
                      text: phone!,
                    ),
                  if ((status ?? '').isNotEmpty)
                    _InfoIconRow(
                      icon: Icon(Icons.badge_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      text: status!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoIconRow extends StatelessWidget {
  final Widget icon;
  final String text;

  const _InfoIconRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          IconTheme(
            data: IconThemeData(color: cs.onSurfaceVariant, size: 18),
            child: icon,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingBookingTile extends StatelessWidget {
  final UserBooking booking;
  final String timeLabel;
  final VoidCallback onTap;

  const _UpcomingBookingTile({
    required this.booking,
    required this.timeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.theme,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if ((booking.objectName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        booking.objectName!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
