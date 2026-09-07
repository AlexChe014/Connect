import 'package:connect/repositories/users_repository.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/utils/app_logger.dart';

/// Онлайн-статус текущего пользователя через `POST /user/update/{id}`.
class UserPresenceService {
  UserPresenceService._();
  static final UserPresenceService instance = UserPresenceService._();

  bool? _lastSent;

  Future<void> setOnline(bool isOnline) async {
    if (!AuthService.instance.isAuthenticated) {
      _lastSent = null;
      return;
    }
    if (_lastSent == isOnline) return;

    final stored = await AuthService.instance.getStoredUser();
    final userId = _parseInt(stored?['id']);
    if (userId == null) return;

    try {
      await UsersRepository.instance.updateOnlineStatus(
        userId: userId,
        isOnline: isOnline,
      );
      _lastSent = isOnline;
    } catch (e, st) {
      AppLogger.d(
        'Failed to update online status',
        name: 'presence',
        error: e,
        stackTrace: st,
      );
    }
  }

  void reset() {
    _lastSent = null;
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}
