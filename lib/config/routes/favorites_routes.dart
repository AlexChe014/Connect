import '../api_config.dart';

class FavoritesRoutes {
  FavoritesRoutes._();

  static const String toggle = '/user/favorites/toggle';
  static const String users = '/user/favorites/users';
  static const String objects = '/user/favorites/objects';

  static String get toggleUrl => '${ApiConfig.baseUrl}$toggle';
  static String get usersUrl => '${ApiConfig.baseUrl}$users';
  static String get objectsUrl => '${ApiConfig.baseUrl}$objects';
}
