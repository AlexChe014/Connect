import '../api_config.dart';

/// Лента уведомлений пользователя — эндпоинты со стороны бэкенда ещё
/// предстоит реализовать (см. контракт в комментариях к каждому методу).
class NotificationRoutes {
  NotificationRoutes._();

  static const String _prefix = '/notifications';

  /// `GET /notifications` — постранично, конверт `{success, data: {data: [...], next_page_url, ...}}`.
  /// Формат элемента — см. `NotificationItem.fromJson`.
  static String get listUrl => '${ApiConfig.baseUrl}$_prefix';

  /// `GET /notifications/unread-count` — конверт `{success, data: <int>}`.
  static String get unreadCountUrl =>
      '${ApiConfig.baseUrl}$_prefix/unread-count';

  /// `POST /notifications/{id}/read` — без тела.
  static String markReadUrl(int id) => '${ApiConfig.baseUrl}$_prefix/$id/read';

  /// `POST /notifications/read-all` — без тела.
  static String get markAllReadUrl => '${ApiConfig.baseUrl}$_prefix/read-all';
}
