class MailConnection {
  final int id;
  final String email;
  final String? service;
  final String? username;
  final String? name;
  final String? customImapHost;
  final int? customImapPort;
  final String? customImapEncryption;
  final bool isActive;
  final String? lastError;

  const MailConnection({
    required this.id,
    required this.email,
    this.service,
    this.username,
    this.name,
    this.customImapHost,
    this.customImapPort,
    this.customImapEncryption,
    this.isActive = true,
    this.lastError,
  });

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return email;
  }

  String get serviceLabel {
    final s = service?.trim();
    if (s == null || s.isEmpty) return 'Почта';
    return s;
  }

  bool get isCustom =>
      service?.toLowerCase() == 'other' ||
      service?.toLowerCase() == 'custom';

  factory MailConnection.fromJson(Map<String, dynamic> json) {
    return MailConnection(
      id: _parseInt(json['id']) ?? 0,
      email: _optionalString(json, ['email', 'mail']) ?? '',
      service: _optionalString(json, ['service', 'provider', 'type']),
      username: _optionalString(json, ['username', 'login']),
      name: _optionalString(json, ['from_name', 'name', 'title', 'display_name']),
      customImapHost: _optionalString(json, ['imap_host', 'custom_imap_host']),
      customImapPort: _parseInt(json['imap_port'] ?? json['custom_imap_port']),
      customImapEncryption:
          _optionalString(json, ['imap_encryption', 'custom_imap_encryption']),
      isActive: _parseBool(json['is_active'], defaultValue: true),
      lastError: _optionalString(json, ['last_error', 'error', 'message']),
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
