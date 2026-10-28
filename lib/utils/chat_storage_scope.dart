import 'package:connect/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ключ SharedPreferences для локальных данных чатов (черновики, mute,
/// избранное) конкретного пользователя: на одном телефоне по очереди могут
/// работать разные сотрудники, и чужие черновики им видеть нельзя.
///
/// Раньше ключи были общими — такие данные один раз переезжают к первому,
/// кто войдёт после обновления (это и есть их владелец).
Future<String> userScopedChatKey(
  SharedPreferences prefs,
  String baseKey,
) async {
  final user = await AuthService.instance.getStoredUser();
  final id = user?['id']?.toString().trim();
  if (id == null || id.isEmpty) return baseKey;

  final key = '${baseKey}_u$id';
  if (!prefs.containsKey(key) && prefs.containsKey(baseKey)) {
    final legacy = prefs.get(baseKey);
    if (legacy is String) {
      await prefs.setString(key, legacy);
    } else if (legacy is bool) {
      await prefs.setBool(key, legacy);
    } else if (legacy is List) {
      await prefs.setStringList(key, legacy.cast<String>());
    }
    await prefs.remove(baseKey);
  }
  return key;
}
