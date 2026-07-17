import '../api_config.dart';

class ObjectsRoutes {
  ObjectsRoutes._();

  static const String getAdditions = '/objects/addition/get';

  static String get additionsUrl => '${ApiConfig.baseUrl}$getAdditions';
}
