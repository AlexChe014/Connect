import 'package:connect/config/routes/user_routes.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';

class ProfileRepository {
  ProfileRepository._();
  static final ProfileRepository instance = ProfileRepository._();

  Future<Map<String, dynamic>> getProfile() async {
    final decoded = await ApiClient.instance.get(UserRoutes.getProfileUrl);
    return ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить профиль',
    );
  }
}

