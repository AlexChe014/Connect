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
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (_hasZone.hasMatch(iso)) return parsed.toLocal();
    // Бэкенд отдаёт `datetime_start/end` строкой из БД без пояса — это время
    // сервера (APP_TIMEZONE=Europe/Moscow, UTC+3 без перехода на летнее).
    // Без пересчёта у сотрудника не в МСК встреча съезжает на разницу поясов.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
    ).subtract(_serverUtcOffset).toLocal();
  }

  static const _serverUtcOffset = Duration(hours: 3);
  static final _hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  static int? parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == '1' || v == 'true';
    }
    return false;
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
