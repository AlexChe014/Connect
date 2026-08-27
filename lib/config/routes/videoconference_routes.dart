import '../api_config.dart';

/// Устаревшие маршруты видеоконференций.
///
/// Новый контракт — [ConnectorRoutes]. Эти URL сохранены для обратной
/// совместимости, пока бэкенд не мигрирует клиентов на `/connector/*`.
class VideoconferenceRoutes {
  VideoconferenceRoutes._();

  static const String create = '/videoconference/create';
  static const String get = '/videoconference/get';

  static String get createUrl => '${ApiConfig.baseUrl}$create';
  static String get getUrl => '${ApiConfig.baseUrl}$get';
}
