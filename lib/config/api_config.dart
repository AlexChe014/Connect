import 'package:shared_preferences/shared_preferences.dart';

/// Конфигурация подключения к REST API.
///
class ApiConfig {
  ApiConfig._();

  static const String _backendHostKey = 'backend_host';
  static const String _defaultBackendHost = 'https://connect.xondev.ru';
  static const String _mobileSegment = '/mobile';
  static const String _apiSegment = '/api';

  /// Публичный префикс файлового storage (реверс-прокси к MinIO/S3).
  /// Не путать с [_mobileSegment] (`/mobile/api` — REST).
  static const String _mobiApiSegment = '/mobi-api';

  static String? _customBackendHost;

  /// Временно: относительные пути `/storage/...` всё ещё раздаёт старый хост.
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
  static String get baseUrl =>
      '${_normalizeHost(backendHost)}$_mobileSegment$_apiSegment';

  /// Базовый URL API для произвольного хоста (ещё не сохранённого в настройках).
  static String apiBaseUrlForHost(String host) {
    final sanitized = _sanitizeBackendHost(host) ?? _normalizeHost(host.trim());
    return '${_normalizeHost(sanitized)}$_mobileSegment$_apiSegment';
  }

  /// Публичный хост для файлов/картинок (без завершающего слеша).
  static String get publicHost => _filesHost;

  /// Таймаут запросов в секундах
  static const int timeoutSeconds = 30;

  /// Устанавливает локальный хост бэкенда.
  ///
  /// Если схема не указана, автоматически добавляется `https://`.
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

  static bool isBackendHostValid(String? value) =>
      _sanitizeBackendHost(value) != null;

  /// Нормализованный хост для отображения в поле ввода (с `https://`).
  static String? normalizeBackendHost(String? value) =>
      _sanitizeBackendHost(value);

  static String _normalizeHost(String host) =>
      host.replaceAll(RegExp(r'/+$'), '');

  static String? _sanitizeBackendHost(String? raw) {
    if (raw == null) return null;
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    trimmed = trimmed.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.toLowerCase().endsWith('/mobile')) {
      trimmed = trimmed.substring(0, trimmed.length - '/mobile'.length);
      trimmed = trimmed.replaceAll(RegExp(r'/+$'), '');
    }
    if (trimmed.isEmpty) return null;

    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('https://')) {
      if (lower.startsWith('http://')) {
        trimmed = 'https://${trimmed.substring(7)}';
      } else {
        final withoutSlashes = trimmed.replaceFirst(RegExp(r'^/+'), '');
        trimmed = 'https://$withoutSlashes';
      }
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return null;
    }

    return _normalizeHost(
      uri.replace(path: '', query: null, fragment: null).toString(),
    );
  }

  /// Нормализация URL файлов от бэкенда.
  ///
  /// S3/MinIO отдаёт внутренние адреса `http://10.5.10.63:9000/...` —
  /// с устройства они недоступны. Приводим к публичному
  /// `{backendHost}/mobi-api/...` (не `/mobile`).
  ///
  /// Временно остальные «локальные» пути приводим к [_filesHost]:
  /// - `localhost` / `127.0.0.1`
  /// - текущий [backendHost] без префикса `/mobi-api`
  /// - относительные пути (`/storage/...`)
  ///
  /// Важно: `Uri.replace(port: null)` в Dart **не сбрасывает** порт.
  static String? normalizeFileUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final fromInternal = _rewriteInternalFilesOrigin(trimmed);
    if (fromInternal != null) return fromInternal;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    if (_pathStartsWithMobiApi(uri.path)) {
      return _rebaseOntoMobiApi(uri);
    }

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

    final shouldRewrite =
        host == 'localhost' ||
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

  /// `http://10.5.10.63:9000/test/x.jpeg` → `{backendHost}/mobi-api/test/x.jpeg`
  static String? _rewriteInternalFilesOrigin(String url) {
    final origin = RegExp(
      r'^https?://10\.5\.10\.63(?::9000)?',
      caseSensitive: false,
    );
    final match = origin.firstMatch(url);
    if (match == null) return null;

    final rest = url.substring(match.end);
    final path = rest.isEmpty
        ? '/'
        : (rest.startsWith('/') ? rest : '/$rest');
    if (_pathStartsWithMobiApi(path.split('?').first.split('#').first)) {
      return '${_normalizeHost(backendHost)}$path';
    }
    return '$_mobiApiBase$path';
  }

  static String get _mobiApiBase =>
      '${_normalizeHost(backendHost)}$_mobiApiSegment';

  static bool _pathStartsWithMobiApi(String path) {
    return path == _mobiApiSegment || path.startsWith('$_mobiApiSegment/');
  }

  /// `{backendHost}/mobi-api` + исходный путь (без дублирования префикса).
  static String _rebaseOntoMobiApi(Uri uri) {
    final origin = Uri.parse(_normalizeHost(backendHost));
    final sourcePath = uri.path.isEmpty ? '/' : uri.path;
    final path = _pathStartsWithMobiApi(sourcePath)
        ? sourcePath
        : '$_mobiApiSegment${sourcePath.startsWith('/') ? sourcePath : '/$sourcePath'}';
    return Uri(
      scheme: origin.scheme,
      userInfo: origin.userInfo,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
      path: path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
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
        // Бэкенд иногда строит `next_page_url` от своего внутреннего пути
        // (например `/api/user/filter`), не зная о префиксе реверс-прокси
        // (у нас `baseUrl` — `/mobile/api`). Наивное «просто приклеить
        // basePath спереди» в этом случае даёт `/mobile/api/api/user/filter`
        // (404). Ищем максимальное перекрытие конца basePath с началом
        // next-пути и добавляем только недостающий префикс.
        final baseSegments = basePath
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();
        final nextSegments = path
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();
        var overlap = 0;
        for (var k = baseSegments.length; k > 0; k--) {
          if (k > nextSegments.length) continue;
          final baseTail = baseSegments.sublist(baseSegments.length - k);
          final nextHead = nextSegments.sublist(0, k);
          var matches = true;
          for (var i = 0; i < k; i++) {
            if (baseTail[i] != nextHead[i]) {
              matches = false;
              break;
            }
          }
          if (matches) {
            overlap = k;
            break;
          }
        }
        final missingPrefix = baseSegments
            .sublist(0, baseSegments.length - overlap)
            .join('/');
        final suffix = path.startsWith('/') ? path : '/$path';
        path = missingPrefix.isEmpty ? suffix : '/$missingPrefix$suffix';
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
