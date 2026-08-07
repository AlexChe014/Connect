/// Конфигурация подключения к REST API.
///
class ApiConfig {
  ApiConfig._();

  /// Базовый URL API (без завершающего слеша)
  static const String baseUrl = 'https://data.xondev.ru/api';

  /// Публичный хост для файлов/картинок (без завершающего слеша).
  /// Бэкенд иногда отдаёт ссылки вида `http://localhost/...` — приводим к этому домену.
  static const String publicHost = 'https://data.xondev.ru';

  /// Таймаут запросов в секундах
  static const int timeoutSeconds = 30;

  /// Нормализация URL файлов от бэкенда.
  ///
  /// Требование: `http://localhost` заменяем на `https://data.xondev.ru`.
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
