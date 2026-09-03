import 'package:connect/config/routes/device_routes.dart';
import 'package:connect/services/api_client.dart';

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
      },
    );
  }

  /// `POST /chat/call/{callId}/decline` — собеседник отклонил звонок.
  Future<void> declineCall({required String callId}) async {
    await ApiClient.instance.post(DeviceRoutes.declineCallUrl(callId));
  }
}
