import '../api_config.dart';

/// Настройки компании. Префикс: `/api/settings` (см. api-docs).
class SettingsRoutes {
  SettingsRoutes._();

  static const String _prefix = '/settings';

  /// `GET /settings/get` — настройки модуля.
  ///
  /// Query: `module`, опционально `key`.
  static String get getUrl => '${ApiConfig.baseUrl}$_prefix/get';

  /// Тот же роут для хоста, который ещё не сохранён в [ApiConfig].
  static String getUrlForHost(String host) =>
      '${ApiConfig.apiBaseUrlForHost(host)}$_prefix/get';
}
