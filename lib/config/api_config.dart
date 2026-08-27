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

  /// Временно: файлы/картинки всё ещё раздаёт старый хост
  /// (`https://data.xondev.ru`), пока storage не настроен на новом сервере.
  static const String _filesHost = 'https://data.xondev.ru';

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
  static String get publicHost => _filesHost;

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
  /// Временно все «локальные» и API-хосты приводим к [_filesHost]:
  /// - `localhost` / `127.0.0.1`
  /// - текущий [backendHost] (файлы на новом сервере ещё не настроены)
  /// - относительные пути (`/storage/...`)
  ///
  /// Важно: `Uri.replace(port: null)` в Dart **не сбрасывает** порт.
  static String? normalizeFileUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    final publicUri = Uri.parse(publicHost);

    // Относительный путь без хоста.
    if (!uri.hasScheme || uri.host.isEmpty) {
      final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
      return publicUri.replace(path: path).toString();
    }

    final host = uri.host.toLowerCase();
    final backendUri = Uri.tryParse(backendHost);
    final backendHostName = backendUri?.host.toLowerCase();
    final filesHostName = publicUri.host.toLowerCase();

    final shouldRewrite = host == 'localhost' ||
        host == '127.0.0.1' ||
        (backendHostName != null &&
            host == backendHostName &&
            host != filesHostName);

    if (!shouldRewrite) return trimmed;

    return publicUri
        .replace(
          path: uri.path.isEmpty ? '/' : uri.path,
          query: uri.hasQuery ? uri.query : null,
          fragment: uri.hasFragment ? uri.fragment : null,
        )
        .toString();
  }

  /// Приводит Laravel `next_page_url` к текущему [baseUrl].
  ///
  /// `Uri.replace(port: null)` в Dart **не сбрасывает** порт исходного URL —
  /// из‑за этого пагинация ломалась, если бэкенд отдавал `localhost:8000`.
  static String? normalizeNextPageUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final nextUri = Uri.tryParse(trimmed);
    if (nextUri == null) return null;

    final baseUri = Uri.parse(baseUrl);
    var path = nextUri.path;
    if (path.isEmpty || path == '/') {
      path = baseUri.path;
    } else {
      final basePath = baseUri.path;
      if (basePath.isNotEmpty &&
          basePath != '/' &&
          !path.startsWith(basePath)) {
        final suffix = path.startsWith('/') ? path : '/$path';
        path = '$basePath$suffix';
      }
    }

    return Uri(
      scheme: baseUri.scheme,
      userInfo: baseUri.userInfo,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: path,
      query: nextUri.hasQuery ? nextUri.query : null,
    ).toString();
  }
}
