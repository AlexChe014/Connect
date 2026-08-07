import '../api_config.dart';

class CommentsRoutes {
  CommentsRoutes._();

  static const String _prefix = '/dashboard/comments';

  static String byNewsUrl(String newsId) =>
      '${ApiConfig.baseUrl}$_prefix/get/$newsId/news';

  static String byUserUrl(String userId) =>
      '${ApiConfig.baseUrl}$_prefix/get/$userId/user';

  static String createUrl(String newsId) =>
      '${ApiConfig.baseUrl}$_prefix/create/$newsId';

  static String updateUrl(String commentId) =>
      '${ApiConfig.baseUrl}$_prefix/update/$commentId';

  static String deleteUrl(String commentId) =>
      '${ApiConfig.baseUrl}$_prefix/delete/$commentId';
}
