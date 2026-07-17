import 'package:connect/config/routes/device_routes.dart';
import 'package:connect/services/api_client.dart';

class DeviceTokenRepository {
  DeviceTokenRepository._();
  static final DeviceTokenRepository instance = DeviceTokenRepository._();

  Future<void> registerToken({
    required String token,
    required String platform,
  }) async {
    await ApiClient.instance.post(
      DeviceRoutes.registerUrl,
      body: {
        'token': token,
        'platform': platform,
      },
    );
  }

  Future<void> unregisterToken({required String token}) async {
    await ApiClient.instance.post(
      DeviceRoutes.unregisterUrl,
      body: {'token': token},
    );
  }
}
