/// Разбор «как пришло» значений из JSON модуля опросов.
abstract final class SurveyJson {
  static int? parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static bool parseBool(Object? v, {bool defaultValue = false}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  static DateTime? parseDate(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(
      s.contains('T') ? s : s.replaceFirst(' ', 'T'),
    )?.toLocal();
  }

  static Map<String, dynamic>? map(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, value) => MapEntry(k.toString(), value));
    return null;
  }

  static String? nonEmpty(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }
}
