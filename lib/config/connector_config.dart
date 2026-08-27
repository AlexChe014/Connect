import 'api_config.dart';

/// Публичные URL портала Connect (не mobile API).
class ConnectorConfig {
  ConnectorConfig._();

  /// Хост портала, напр. `https://connect.xondev.ru`.
  /// Не путать с [ApiConfig.publicHost] (файловый storage).
  static String get portalHost => ApiConfig.backendHost;

  /// Self-hosted Jitsi, напр. `https://connecthub.xondev.ru`.
  static const String jitsiServerUrl = 'https://connecthub.xondev.ru';

  /// Шаблон публичной ссылки на встречу: `/connector/{room}`.
  static String publicMeetingUrl(String room) =>
      '${portalHost.replaceAll(RegExp(r'/+$'), '')}/connector/$room';
}
