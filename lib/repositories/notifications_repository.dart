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
    final page = ApiPaginatedEnvelope.unwrapPaginated<NotificationItem>(
      decoded,
      defaultErrorMessage: 'Не удалось загрузить уведомления',
      mapItem: NotificationItem.fromJson,
    );
    return Paginated<NotificationItem>(
      data: page.data,
      currentPage: page.currentPage,
      lastPage: page.lastPage,
      nextPageUrl: _keepPerPage(page.nextPageUrl),
      prevPageUrl: page.prevPageUrl,
      path: page.path,
      perPage: page.perPage,
      to: page.to,
      total: page.total,
    );
  }

  /// Laravel строит `next_page_url` без `per_page`, и следующая страница
  /// пришла бы с размером по умолчанию — со сдвигом и дублями.
  static String? _keepPerPage(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.queryParameters.containsKey('per_page')) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'per_page': '${NotificationRoutes.perPage}',
          },
        )
        .toString();
  }

  /// Число непрочитанных: `count` из `/unread`, иначе длина списка.
  Future<int> getUnreadCount() async {
    final decoded = await ApiClient.instance.get(NotificationRoutes.unreadUrl);
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage:
          'Не удалось получить число непрочитанных уведомлений',
    );
    final count = data['count'];
    if (count is num) return count.toInt();
    final parsed = int.tryParse(count?.toString() ?? '');
    if (parsed != null) return parsed;
    final list = data['notifications'];
    return list is List ? list.length : 0;
  }

  Future<void> markAsRead(int id) async {
    await ApiClient.instance.post(NotificationRoutes.markReadUrl(id));
  }

  Future<void> markAllAsRead() async {
    await ApiClient.instance.post(NotificationRoutes.markAllReadUrl);
  }
}
