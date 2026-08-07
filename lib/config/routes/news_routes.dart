import '../api_config.dart';

class NewsRoutes {
  NewsRoutes._();

  static const String _prefix = '/dashboard/news';

  static const String all = '$_prefix/all';
  static const String create = '$_prefix/create';

  static String get allUrl => '${ApiConfig.baseUrl}$all';
  static String get createUrl => '${ApiConfig.baseUrl}$create';

  static String getUrl(String newsId) => '${ApiConfig.baseUrl}$_prefix/get/$newsId';

  static String updateUrl(String newsId) =>
      '${ApiConfig.baseUrl}$_prefix/update/$newsId';

  static String deleteUrl(String newsId) =>
      '${ApiConfig.baseUrl}$_prefix/delete/$newsId';

  static String addLikeUrl(String newsId) =>
      '${ApiConfig.baseUrl}$_prefix/add-like/$newsId';

  static String addViewUrl(String newsId) =>
      '${ApiConfig.baseUrl}$_prefix/add-view/$newsId';

  static String removeLikeUrl(String newsId) =>
      '${ApiConfig.baseUrl}$_prefix/remove-like/$newsId';
}
