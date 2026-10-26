import 'api_response_cache.dart';
import 'app_lock_service.dart';
import 'app_navigation_service.dart';
import 'auth_service.dart';
import 'chat_realtime_service.dart';
import 'chat_service.dart';
import 'mail_contacts_service.dart';
import 'push_notification_service.dart';
import 'user_presence_service.dart';

/// Выход из аккаунта по просьбе пользователя (профиль, экран блокировки).
Future<void> signOut() async {
  await UserPresenceService.instance.setOnline(false);
  UserPresenceService.instance.reset();
  await ChatRealtimeService.instance.stop();
  // Пока известен пользователь — подсказки адресатов лежат под его id.
  await MailContactsService.instance.clear();
  // Порядок важен: токены отвязываем, пока Bearer ещё валиден, а
  // локально гасим уже после очистки сессии.
  await PushNotificationService.instance.unregisterOnBackend();
  await AuthService.instance.revokeServerSession();
  await AuthService.instance.logout();
  ChatService.instance.reset();
  await ApiResponseCache.clearAll();
  await PushNotificationService.instance.disableLocally();
  await AppLockService.instance.reset();
  AppNavigationService.goToLogin();
}
