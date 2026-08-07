import '../api_config.dart';

class DeviceRoutes {
  DeviceRoutes._();

  static const String _prefix = '/devices/fcm';

  static String get registerUrl => '${ApiConfig.baseUrl}$_prefix';

  static String get unregisterUrl => '${ApiConfig.baseUrl}$_prefix/delete';
}
