import 'dart:convert';

/// Одно уведомление в ленте (`GET /notifications`). `type` и `data`
/// повторяют формат push-payload (см. `NotificationTopics`), поэтому тап
/// по элементу ленты и тап по push ведут по одной и той же логике
/// (`AppNavigationService.openFromData`).
class NotificationItem {
  final int id;
  final String type;
  final String? module;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;

  /// Вложенный объект `data` с бэкенда как есть (включая `booking_id`,
  /// `creator`, `link`). Не приводим значения к строке: иначе вложенные
  /// карты теряются, а `id` брони нельзя отличить от id уведомления.
  final Map<String, dynamic> data;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    this.module,
    this.createdAt,
    this.data = const {},
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: _parseInt(json['id']) ?? 0,
      type: (json['type'] ?? '').toString(),
      module: json['module']?.toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? json['message'] ?? json['text'] ?? '').toString(),
      isRead: _parseBool(json['is_read'], defaultValue: false),
      createdAt: _parseDate(json['created_at']),
      data: _parseData(json['data']),
    );
  }

  Map<String, dynamic> toNavigationData() => {
        'type': type,
        if (module != null && module!.isNotEmpty) 'module': module,
        ...data,
        'data': data,
      };

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      type: type,
      module: module,
      title: title,
      body: body,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      data: data,
    );
  }

  static Map<String, dynamic> _parseData(Object? rawData) {
    if (rawData is Map) {
      return rawData.map((key, value) => MapEntry(key.toString(), value));
    }
    if (rawData is String && rawData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map) {
          return decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } catch (_) {}
    }
    return {};
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

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.contains('T') ? s : s.replaceFirst(' ', 'T'));
  }
}
