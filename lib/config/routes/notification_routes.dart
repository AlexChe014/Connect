import '../api_config.dart';

/// Уведомления пользователя (`user_notifications`), `routes/api/user.php`.
/// Все под `auth:sanctum`, ответ в конверте `{success, data}`.
class NotificationRoutes {
  NotificationRoutes._();

  static const String _prefix = '/user/notifications';

  /// `GET /user/notifications/get?per_page=N` — постранично, сначала новые:
  /// `data: {data: [...], next_page_url, ...}`. Элемент — см.
  /// `NotificationItem.fromJson`.
  static String get listUrl =>
      '${ApiConfig.baseUrl}$_prefix/get?per_page=$perPage';

  static const int perPage = 20;

  /// `GET /user/notifications/unread` — `data: {notifications: [...], count}`.
  static String get unreadUrl => '${ApiConfig.baseUrl}$_prefix/unread';

  /// `POST /user/notifications/read/{id}` — `data: true`, или `false`, если
  /// уже было прочитано.
  static String markReadUrl(int id) => '${ApiConfig.baseUrl}$_prefix/read/$id';

  /// `POST /user/notifications/read-all` — без тела.
  static String get markAllReadUrl => '${ApiConfig.baseUrl}$_prefix/read-all';
}
