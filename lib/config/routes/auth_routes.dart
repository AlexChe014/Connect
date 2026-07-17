import '../api_config.dart';

class AuthRoutes {
  AuthRoutes._();

  static const String login = '/auth/login';

  static String get loginUrl => '${ApiConfig.baseUrl}$login';
}

