import 'package:connect/config/routes/device_routes.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/device_identity.dart';

class DeviceTokenRepository {
  DeviceTokenRepository._();
  static final DeviceTokenRepository instance = DeviceTokenRepository._();

  /// `POST /devices/fcm`. Пользователь берётся из Bearer-токена,
  /// клиент передаёт только FCM-токен устройства и платформу.
  Future<void> registerToken({
    required String token,
    required String platform,
  }) async {
    await ApiClient.instance.post(
      DeviceRoutes.registerUrl,
      body: {
        'token': token,
        'platform': platform,
        'device_id': await DeviceIdentity.instance.id(),
      },
    );
  }

  Future<void> unregisterToken({required String token}) async {
    await ApiClient.instance.post(
      DeviceRoutes.unregisterUrl,
      body: {'token': token},
    );
  }

  /// `POST /devices/voip` — регистрация PushKit VoIP-токена (iOS).
  Future<void> registerVoipToken({required String token}) async {
    await ApiClient.instance.post(
      DeviceRoutes.registerVoipUrl,
      body: {
        'token': token,
        'platform': 'ios',
        'device_id': await DeviceIdentity.instance.id(),
      },
    );
  }

  /// `POST /devices/voip/delete` — отвязать VoIP-токен при выходе.
  Future<void> unregisterVoipToken({required String token}) async {
    await ApiClient.instance.post(
      DeviceRoutes.unregisterVoipUrl,
      body: {'token': token},
    );
  }
}
