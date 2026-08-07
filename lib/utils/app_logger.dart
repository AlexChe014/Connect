import 'dart:convert';
import 'dart:developer' as developer;

/// Минималистичный логгер для приложения.
///
/// В релизе логи можно отключить через `enabled=false` (или оставить включенными,
/// если вы используете сбор и отправку логов).
class AppLogger {
  AppLogger._();

  /// Глобальный флаг. Удобно переключать из одного места.
  static bool enabled = true;

  static void d(
    String message, {
    String name = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;

    // Логируем только в debug/profile через assert (в release assert не выполняется).
    assert(() {
      developer.log(message, name: name, error: error, stackTrace: stackTrace);
      return true;
    }());
  }

  static void e(
    String message, {
    String name = 'app.error',
    Object? error,
    StackTrace? stackTrace,
  }) {
    d(message, name: name, error: error, stackTrace: stackTrace);
  }

  /// Безопасно обрезает длинные строки для логов.
  static String truncate(String s, {int max = 1500}) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…(truncated ${s.length - max} chars)';
  }

  /// Маскирует чувствительные поля (пароль/токены) в JSON-подобных структурах.
  static Object? sanitize(Object? value) {
    if (value is Map) {
      final out = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key?.toString() ?? '';
        final lower = key.toLowerCase();
        final v = entry.value;
        if (lower.contains('password') ||
            lower == 'pass' ||
            lower.contains('token') ||
            lower == 'authorization') {
          out[key] = _mask(v);
        } else {
          out[key] = sanitize(v);
        }
      }
      return out;
    }
    if (value is List) {
      return value.map(sanitize).toList();
    }
    return value;
  }

  static String prettyJson(Object? jsonLike) {
    try {
      return const JsonEncoder.withIndent('  ').convert(sanitize(jsonLike));
    } catch (_) {
      return sanitize(jsonLike)?.toString() ?? 'null';
    }
  }

  static Object? tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static String _mask(Object? v) {
    if (v == null) return '<null>';
    final s = v.toString();
    if (s.isEmpty) return '<empty>';
    if (s.length <= 8) return '***';
    return '${s.substring(0, 4)}…${s.substring(s.length - 3)}';
  }
}
