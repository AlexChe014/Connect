import '../api_config.dart';

/// REST-маршруты раздела «Коннектор» (видеовстречи ConnectHub).
///
/// Базовый префикс: `{backendHost}/mobile/api` ([ApiConfig.baseUrl]).
///
/// Контракт для бэкенда описан в промпте для реализации API.
class ConnectorRoutes {
  ConnectorRoutes._();

  static const String _prefix = '/connector';

  /// `POST /connector/instant` — мгновенная видеовстреча.
  static const String instant = '$_prefix/instant';

  /// `POST /connector/schedule` — запланированная встреча (Booking + ссылка).
  static const String schedule = '$_prefix/schedule';

  /// `GET /connector/join/{room}` — JWT и параметры для входа в комнату.
  static const String _joinPrefix = '$_prefix/join/';

  /// `GET /connector/{room}` — метаданные встречи по id комнаты.
  static const String _roomPrefix = '$_prefix/';

  static String get instantUrl => '${ApiConfig.baseUrl}$instant';
  static String get scheduleUrl => '${ApiConfig.baseUrl}$schedule';

  static String joinUrl(String room) =>
      '${ApiConfig.baseUrl}$_joinPrefix${Uri.encodeComponent(room)}';

  static String roomUrl(String room) =>
      '${ApiConfig.baseUrl}$_roomPrefix${Uri.encodeComponent(room)}';
}
