class DocumentService {
  final int id;
  final String name;
  final String title;
  final String? url;
  final bool isActive;
  final String? type;

  const DocumentService({
    required this.id,
    required this.name,
    required this.title,
    this.url,
    this.isActive = true,
    this.type,
  });

  bool get isSigningService {
    final t = type?.trim().toLowerCase();
    return t == 'sign' || t == 'signing' || t == 'подпись' || t == 'подписание';
  }

  bool get isApprovalService {
    final t = type?.trim().toLowerCase();
    return t == 'agreement' ||
        t == 'agree' ||
        t == 'approval' ||
        t == 'accept' ||
        t == 'согласование';
  }

  /// Имя сервиса для UI: человекочитаемый `title`, иначе `name`.
  String get displayName {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    return name.trim();
  }

  String get displayTitle => displayName;

  factory DocumentService.fromJson(Map<String, dynamic> json) {
    return DocumentService(
      id: _parseInt(json['id']) ?? 0,
      name: _optionalString(json, ['name']) ?? '',
      title: _optionalString(json, ['title', 'name']) ?? '',
      url: _optionalString(json, ['url']),
      isActive: _parseBool(json['is_active'], defaultValue: true),
      type: _optionalString(json, ['type']),
    );
  }

  static bool _parseBool(Object? value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  static String? _optionalString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final v = json[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }
}
