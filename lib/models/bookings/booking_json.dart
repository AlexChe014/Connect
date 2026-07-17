/// Общие хелперы парсинга ответов бронирований.
class BookingJson {
  BookingJson._();

  static DateTime parseDateTime(dynamic value) {
    if (value is num) {
      final seconds = value.toInt();
      if (seconds > 0) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    final raw = (value is String ? value : '').trim();
    if (raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);

    final asInt = int.tryParse(raw);
    if (asInt != null && asInt > 0) {
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
    }

    final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(iso) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int? parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static List<int> parseIntList(dynamic value) {
    if (value is! List) return const [];
    return value.map(parseInt).whereType<int>().toList();
  }

  static String? objectNameFromJson(Map<String, dynamic> json) {
    final object = json['object'];
    if (object is Map) return (object['name'] as String?)?.trim();
    return null;
  }
}
