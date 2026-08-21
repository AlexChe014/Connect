import 'package:connect/config/routes/notification_routes.dart';
import 'package:connect/models/notification_item.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/services/paginated.dart';

class NotificationsRepository {
  NotificationsRepository._();
  static final NotificationsRepository instance = NotificationsRepository._();

  /// Первая страница — либо конкретная страница по `url` (пагинация).
  Future<Paginated<NotificationItem>> getPage({String? url}) async {
    final decoded = await ApiClient.instance.get(
      url ?? NotificationRoutes.listUrl,
    );
    return ApiPaginatedEnvelope.unwrapPaginated<NotificationItem>(
      decoded,
      defaultErrorMessage: 'Не удалось загрузить уведомления',
      mapItem: NotificationItem.fromJson,
    );
  }

  Future<int> getUnreadCount() async {
    final decoded = await ApiClient.instance.get(
      NotificationRoutes.unreadCountUrl,
    );
    return ApiEnvelope.unwrapDataInt(
      decoded,
      defaultErrorMessage:
          'Не удалось получить число непрочитанных уведомлений',
    );
  }

  Future<void> markAsRead(int id) async {
    await ApiClient.instance.post(NotificationRoutes.markReadUrl(id));
  }

  Future<void> markAllAsRead() async {
    await ApiClient.instance.post(NotificationRoutes.markAllReadUrl);
  }
}
