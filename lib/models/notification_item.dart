/// Одно уведомление в ленте (`GET /notifications`). `type` и `data`
/// повторяют формат push-payload (см. `NotificationTopics`), поэтому тап
/// по элементу ленты и тап по push ведут по одной и той же логике
/// (`AppNavigationService.openFromData`).
class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;
  final Map<String, String> data;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    this.createdAt,
    this.data = const {},
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final data = <String, String>{};
    if (rawData is Map) {
      for (final entry in rawData.entries) {
        final value = entry.value;
        if (value == null) continue;
        data[entry.key.toString()] = value.toString();
      }
    }

    return NotificationItem(
      id: _parseInt(json['id']) ?? 0,
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? json['message'] ?? '').toString(),
      isRead: _parseBool(json['is_read'], defaultValue: false),
      createdAt: _parseDate(json['created_at']),
      data: data,
    );
  }

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      type: type,
      title: title,
      body: body,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      data: data,
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
