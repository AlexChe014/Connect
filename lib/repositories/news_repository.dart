import 'package:connect/config/routes/news_routes.dart';
import 'package:connect/models/news_item.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/paginated.dart';
import 'package:http/http.dart' as http;

class NewsRepository {
  NewsRepository._();
  static final NewsRepository instance = NewsRepository._();

  Future<Paginated<NewsItem>> getPage({String? url}) async {
    final requestUrl = url ?? NewsRoutes.allUrl;
    final decoded = await ApiClient.instance.get(requestUrl);

    return ApiPaginatedEnvelope.unwrapPaginated<NewsItem>(
      decoded,
      defaultErrorMessage: 'Не удалось получить новости',
      mapItem: (json) => NewsItem.fromJson(json),
    );
  }

  Future<NewsItem> getById(
    String newsId, {
    bool includePeople = false,
  }) async {
    final decoded = await ApiClient.instance.get(
      NewsRoutes.getUrl(newsId),
      queryParameters: includePeople
          ? const {'likes': '1', 'views': '1'}
          : null,
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить новость',
    );
    return _withCurrentUserLike(NewsItem.fromJson(data));
  }

  /// Список лайкнувших / посмотревших: `GET .../likes/{id}` и `.../views/{id}`.
  Future<({List<NewsAuthor> likers, List<NewsAuthor> viewers, NewsItem news})>
      getPeople(String newsId) async {
    List<NewsAuthor> likers = const [];
    List<NewsAuthor> viewers = const [];

    try {
      final results = await Future.wait([
        _getUsers(NewsRoutes.likesUrl(newsId)),
        _getUsers(NewsRoutes.viewsUrl(newsId)),
      ]);
      likers = results[0];
      viewers = results[1];
    } catch (_) {
      // fallback: карточка с likes=1&views=1
    }

    final news = await getById(newsId, includePeople: true);
    if (likers.isEmpty) likers = news.likers;
    if (viewers.isEmpty) viewers = news.viewers;

    final merged = await _withCurrentUserLike(
      news.copyWith(likers: likers, viewers: viewers),
    );
    return (likers: likers, viewers: viewers, news: merged);
  }

  /// `POST /dashboard/news/add-like/{news}` → `data` — новое число лайков.
  Future<int?> addLike(String newsId) async {
    final decoded = await ApiClient.instance.post(
      NewsRoutes.addLikeUrl(newsId),
      body: const {},
    );
    return _parseLikeCount(decoded);
  }

  /// `POST /dashboard/news/remove-like/{news}` → `data` — новое число лайков.
  Future<int?> removeLike(String newsId) async {
    final decoded = await ApiClient.instance.post(
      NewsRoutes.removeLikeUrl(newsId),
      body: const {},
    );
    return _parseLikeCount(decoded);
  }

  Future<void> addView(String newsId) async {
    await ApiClient.instance.post(
      NewsRoutes.addViewUrl(newsId),
      body: const {},
    );
  }

  Future<void> create({
    required String title,
    String? text,
    List<http.MultipartFile> pictures = const [],
    List<http.MultipartFile> documents = const [],
  }) async {
    final fields = <String, String>{
      'title': title.trim(),
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
    };

    await ApiClient.instance.postMultipart(
      NewsRoutes.createUrl,
      fields: fields,
      files: [...pictures, ...documents],
    );
  }

  Future<List<NewsAuthor>> _getUsers(String url) async {
    final decoded = await ApiClient.instance.get(url);
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось получить список',
    );
    final rawList = _asUserList(data);
    return [
      for (final e in rawList)
        if (e is Map<String, dynamic>)
          NewsAuthor.fromJson(e)
        else if (e is Map)
          NewsAuthor.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  static List _asUserList(Object? data) {
    if (data is List) return data;
    if (data is Map) {
      final nested = data['data'] ?? data['users'];
      if (nested is List) return nested;
    }
    return const [];
  }

  static int? _parseLikeCount(Map<String, dynamic> decoded) {
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось обновить лайк',
    );
    if (data is int) return data;
    if (data is num) return data.toInt();
    if (data is String) return int.tryParse(data.trim());
    if (data is Map) {
      return NewsItem.fromJson(Map<String, dynamic>.from(data)).likesCount;
    }
    return null;
  }

  static Future<NewsItem> _withCurrentUserLike(NewsItem news) async {
    if (news.isLiked || news.likers.isEmpty) return news;
    final user = await AuthService.instance.getStoredUser();
    final rawId = user?['id'] ?? user?['user_id'];
    if (rawId == null) return news;
    final id = rawId.toString();
    if (news.likers.any((u) => u.id == id)) {
      return news.copyWith(isLiked: true);
    }
    return news;
  }
}
