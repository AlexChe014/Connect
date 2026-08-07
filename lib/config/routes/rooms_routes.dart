import '../api_config.dart';

class RoomsRoutes {
  RoomsRoutes._();

  static const String all = '/rooms';

  static String get allUrl => '${ApiConfig.baseUrl}$all';
}

