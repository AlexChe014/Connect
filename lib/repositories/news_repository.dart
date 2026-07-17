import 'package:connect/config/routes/news_routes.dart';
import 'package:connect/models/news_item.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
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
    return NewsItem.fromJson(data);
  }

  /// Список лайкнувших / посмотревших из детальной новости.
  ///
  /// Запрашиваем `likes=1&views=1` (как в Dashboard Postman / Update)
  /// и парсим пользователей из ответа.
  Future<({List<NewsAuthor> likers, List<NewsAuthor> viewers, NewsItem news})>
      getPeople(String newsId) async {
    final news = await getById(newsId, includePeople: true);
    return (likers: news.likers, viewers: news.viewers, news: news);
  }

  Future<void> addLike(String newsId) async {
    await ApiClient.instance.post(NewsRoutes.addLikeUrl(newsId));
  }

  Future<void> removeLike(String newsId) async {
    await ApiClient.instance.post(NewsRoutes.removeLikeUrl(newsId));
  }

  Future<void> addView(String newsId) async {
    await ApiClient.instance.post(NewsRoutes.addViewUrl(newsId));
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
}
