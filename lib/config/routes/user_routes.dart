import '../api_config.dart';

class UserRoutes {
  UserRoutes._();

  static const String getProfile = '/user/get';
  static const String getByFilter = '/user/filter';

  static String get getProfileUrl => '${ApiConfig.baseUrl}$getProfile';
  static String get getByFilterUrl => '${ApiConfig.baseUrl}$getByFilter';

  /// `POST /user/request-deletion` — бэкенд пишет запрос в поддержку.
  static String get requestDeletionUrl =>
      '${ApiConfig.baseUrl}/user/request-deletion';

  /// `POST /user/update/{user}` — обновление профиля (multipart).
  static String updateUrl(int userId) =>
      '${ApiConfig.baseUrl}/user/update/$userId';
}
