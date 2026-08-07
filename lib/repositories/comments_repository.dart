import 'package:connect/config/routes/comments_routes.dart';
import 'package:connect/models/news_comment.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/services/paginated.dart';

class CommentsRepository {
  CommentsRepository._();
  static final CommentsRepository instance = CommentsRepository._();

  Future<Paginated<NewsComment>> getByNewsPage({
    required String newsId,
    String? url,
  }) async {
    final requestUrl = url ?? CommentsRoutes.byNewsUrl(newsId);
    final decoded = await ApiClient.instance.get(requestUrl);
    return _unwrapCommentsPage(
      decoded,
      defaultErrorMessage: 'Не удалось получить комментарии',
    );
  }

  Future<void> create({
    required String newsId,
    required String text,
  }) async {
    await ApiClient.instance.postMultipart(
      CommentsRoutes.createUrl(newsId),
      fields: {'text': text.trim()},
    );
  }

  Paginated<NewsComment> _unwrapCommentsPage(
    Map<String, dynamic> decoded, {
    required String defaultErrorMessage,
  }) {
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: defaultErrorMessage,
    );

    if (data is List) {
      final items = data
          .whereType<Map>()
          .map((e) => NewsComment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      return Paginated<NewsComment>(
        data: items,
        currentPage: 1,
        nextPageUrl: null,
        prevPageUrl: null,
        path: null,
        perPage: items.length,
        to: items.length,
        total: items.length,
      );
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final rawList = map['data'];
      if (rawList is List && map.containsKey('current_page')) {
        return ApiPaginatedEnvelope.unwrapPaginated<NewsComment>(
          decoded,
          defaultErrorMessage: defaultErrorMessage,
          mapItem: (json) => NewsComment.fromJson(json),
        );
      }
      if (rawList is List) {
        final items = rawList
            .whereType<Map>()
            .map((e) => NewsComment.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
        return Paginated<NewsComment>(
          data: items,
          currentPage: 1,
          nextPageUrl: map['next_page_url'] as String?,
          prevPageUrl: map['prev_page_url'] as String?,
          path: map['path'] as String?,
          perPage: (map['per_page'] as num?)?.toInt() ?? items.length,
          to: (map['to'] as num?)?.toInt() ?? items.length,
          total: (map['total'] as num?)?.toInt() ?? items.length,
        );
      }
    }

    throw ApiException(200, 'Некорректный формат комментариев');
  }
}
