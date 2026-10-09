import '../api_config.dart';

class AuthRoutes {
  AuthRoutes._();

  static const String login = '/auth/login';

  static const String logout = '/auth/logout';

  static String get loginUrl => '${ApiConfig.baseUrl}$login';

  static String get logoutUrl => '${ApiConfig.baseUrl}$logout';
}

