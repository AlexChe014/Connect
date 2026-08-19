import 'package:shared_preferences/shared_preferences.dart';

/// Конфигурация подключения к REST API.
///
class ApiConfig {
  ApiConfig._();

  static const String _backendHostKey = 'backend_host';
  static const String _defaultBackendHost = 'https://connect.xondev.ru';
  static const String _mobileSegment = '/mobile';
  static const String _apiSegment = '/api';
  static String? _customBackendHost;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _customBackendHost = _sanitizeBackendHost(prefs.getString(_backendHostKey));
  }

  /// Текущий хост бэкенда без пути `/mobile`.
  static String get backendHost => _customBackendHost ?? _defaultBackendHost;

  /// Пользовательский хост (без дефолта), если задан локально.
  static String? get customBackendHost => _customBackendHost;

  /// Базовый URL API (без завершающего слеша)
  static String get baseUrl => '${_normalizeHost(backendHost)}$_mobileSegment$_apiSegment';

  /// Публичный хост для файлов/картинок (без завершающего слеша).
  /// Бэкенд иногда отдаёт ссылки вида `http://localhost/...` — приводим к этому домену.
  static String get publicHost => _normalizeHost(backendHost);

  /// Таймаут запросов в секундах
  static const int timeoutSeconds = 30;

  /// Устанавливает локальный хост бэкенда.
  ///
  /// Пользователь вводит хост без `/mobile`, например `https://connect.xondev.ru`.
  /// Пустое значение сбрасывает настройку к дефолтному адресу.
  static Future<void> setBackendHost(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = _sanitizeBackendHost(value);
    _customBackendHost = sanitized;
    if (sanitized == null) {
      await prefs.remove(_backendHostKey);
    } else {
      await prefs.setString(_backendHostKey, sanitized);
    }
  }

  static bool isBackendHostValid(String? value) => _sanitizeBackendHost(value) != null;

  static String _normalizeHost(String host) => host.replaceAll(RegExp(r'/+$'), '');

  static String? _sanitizeBackendHost(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    var normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
    if (normalized.toLowerCase().endsWith('/mobile')) {
      normalized = normalized.substring(0, normalized.length - '/mobile'.length);
    }
    if (normalized.isEmpty) return null;

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  /// Нормализация URL файлов от бэкенда.
  ///
  /// Требование: `http://localhost` заменяем на текущий `publicHost`.
  static String? normalizeFileUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host == 'localhost') {
      final publicUri = Uri.parse(publicHost);
      return uri
          .replace(
            scheme: publicUri.scheme,
            host: publicUri.host,
            port: null,
          )
          .toString();
    }

    // Фоллбэк для “кривых” строк, которые `Uri` не парсит.
    const localhostPrefix = 'http://localhost';
    if (trimmed.startsWith(localhostPrefix)) {
      final rest = trimmed.substring(localhostPrefix.length);
      final restWithoutPort = rest.replaceFirst(RegExp(r'^:\d+'), '');
      return '$publicHost$restWithoutPort';
    }

    return trimmed;
  }
}
