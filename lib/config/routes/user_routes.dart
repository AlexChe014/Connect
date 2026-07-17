import '../api_config.dart';

class UserRoutes {
  UserRoutes._();

  static const String getProfile = '/user/get';
  static const String getByFilter = '/user/filter';

  static String get getProfileUrl => '${ApiConfig.baseUrl}$getProfile';
  static String get getByFilterUrl => '${ApiConfig.baseUrl}$getByFilter';
}

