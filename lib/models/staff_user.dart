import 'package:connect/config/api_config.dart';
import 'package:connect/utils/media_url_utils.dart';
import 'package:connect/utils/user_display_name.dart';

/// Пользователь из `/user/filter` (список сотрудников).
class StaffUser {
  final String id;
  final String surname;
  final String name;
  final String patronymic;
  final String? email;
  final String? phone;
  final DateTime? birthday;
  final String? department;
  final String? workStatus;
  final List<String> roles;
  final String? avatarUrl;
  final bool isOnline;

  const StaffUser({
    required this.id,
    required this.surname,
    required this.name,
    this.patronymic = '',
    this.email,
    this.phone,
    this.birthday,
    this.department,
    this.workStatus,
    this.roles = const [],
    this.avatarUrl,
    this.isOnline = false,
  });

  String get fullName {
    final parts = <String>[
      if (surname.trim().isNotEmpty) surname.trim(),
      if (name.trim().isNotEmpty) name.trim(),
      if (patronymic.trim().isNotEmpty) patronymic.trim(),
    ];
    if (parts.isEmpty) {
      final e = email?.trim();
      if (e != null && e.isNotEmpty) return e;
      return 'Пользователь';
    }
    return parts.join(' ');
  }

  /// Имя и фамилия для чатов.
  String get chatDisplayName =>
      userDisplayName(surname: surname, name: name, email: email);

  /// Числовой id для API (`users[]`).
  int? get idAsInt => int.tryParse(id.trim());

  String get initials {
    final parts = <String>[];
    for (final t in [surname, name]) {
      final s = t.trim();
      if (s.isNotEmpty) parts.add(s.substring(0, 1));
    }
    if (parts.isEmpty) {
      final e = email?.trim();
      if (e != null && e.isNotEmpty) return e[0].toUpperCase();
      return '?';
    }
    return parts.take(2).join().toUpperCase();
  }

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId == null ? '' : rawId.toString();

    String s(Object? key, {String fallback = ''}) {
      final v = json[key];
      if (v == null) return fallback;
      return v.toString().trim();
    }

    final surname = s('surname');
    final name = s('name');
    final patronymic = s('patronymic', fallback: s('father_name', fallback: s('middlename')));

    final email = _optionalString(json, ['email', 'mail']);
    final phone = _optionalString(json, ['phone', 'mobile', 'tel', 'telephone']);

    final birthday = _parseDate(
      json['birthday'] ?? json['birth_date'] ?? json['date_of_birth'],
    );

    final department = _departmentLabel(json);
    final workStatus = _namedEntityLabel(json, [
      'work_status',
      'employment_status',
      'status_label',
      'status',
    ]);

    final roles = _parseRoles(json['roles'] ?? json['role_names'] ?? json['user_roles']);

    final avatarUrl = ApiConfig.normalizeFileUrl(_avatarFromJson(json));

    final isOnline = _parseOnline(json);

    return StaffUser(
      id: id,
      surname: surname,
      name: name,
      patronymic: patronymic,
      email: email,
      phone: phone,
      birthday: birthday,
      department: department,
      workStatus: workStatus,
      roles: roles,
      avatarUrl: avatarUrl,
      isOnline: isOnline,
    );
  }

  static String? _optionalString(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      final t = v.toString().trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  static String? _namedEntityLabel(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final raw = json[k];
      if (raw == null) continue;
      if (raw is Map) {
        for (final nameKey in ['name', 'title', 'label']) {
          final v = raw[nameKey];
          if (v != null) {
            final t = v.toString().trim();
            if (t.isNotEmpty) return t;
          }
        }
        continue;
      }
      final t = raw.toString().trim();
      if (t.isNotEmpty && !t.startsWith('{')) return t;
    }
    return null;
  }

  static String? _departmentLabel(Map<String, dynamic> json) {
    final dep = json['department'];
    if (dep is Map<String, dynamic>) {
      final title = dep['title'] ?? dep['name'] ?? dep['label'];
      if (title != null) {
        final t = title.toString().trim();
        if (t.isNotEmpty) return t;
      }
    }
    return _optionalString(json, ['department_name', 'dep_name', 'department', 'dep']);
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final parts = s.split(RegExp(r'[.\-/]'));
    if (parts.length == 3) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      final c = int.tryParse(parts[2]);
      if (a != null && b != null && c != null) {
        if (a > 31) return DateTime(a, b, c);
        if (c > 31) return DateTime(c, b, a);
        return DateTime(c, b, a);
      }
    }
    return null;
  }

  static List<String> _parseRoles(Object? raw) {
    if (raw == null) return const [];
    if (raw is String) {
      final t = raw.trim();
      return t.isEmpty ? const [] : [t];
    }
    if (raw is List) {
      final out = <String>[];
      for (final e in raw) {
        if (e is String) {
          final t = e.trim();
          if (t.isNotEmpty) out.add(t);
        } else if (e is Map) {
          final name = e['name'] ?? e['title'] ?? e['slug'] ?? e['role'];
          if (name != null) {
            final t = name.toString().trim();
            if (t.isNotEmpty) out.add(t);
          }
        }
      }
      return out;
    }
    return const [];
  }

  static bool _parseOnline(Map<String, dynamic> json) {
    for (final key in ['is_online', 'online', 'isOnline', 'in_network']) {
      final v = json[key];
      if (v == null) continue;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase();
      if (s == 'true' || s == '1' || s == 'online' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'offline' || s == 'no') return false;
    }
    return false;
  }

  static String? _avatarFromJson(Map<String, dynamic> json) {
    final direct = _optionalString(json, ['avatar_url', 'avatar', 'photo', 'photo_url', 'image']);
    if (direct != null) return direct;

    return MediaUrlUtils.firstUrl(json['media'] ?? json['avatar_media']);
  }
}
