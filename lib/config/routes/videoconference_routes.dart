import '../api_config.dart';

class VideoconferenceRoutes {
  VideoconferenceRoutes._();

  static const String create = '/videoconference/create';
  static const String get = '/videoconference/get';

  static String get createUrl => '${ApiConfig.baseUrl}$create';
  static String get getUrl => '${ApiConfig.baseUrl}$get';
}
