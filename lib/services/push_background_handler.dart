import 'package:connect/firebase_options.dart';
import 'package:connect/models/incoming_call_payload.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/incoming_call_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!DefaultFirebaseOptions.isConfigured) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Этот колбэк выполняется в отдельном фоновом изоляте (когда приложение
  // убито) — AuthService.instance там всегда "пустой", пока не прочитать
  // токен из SharedPreferences заново. Без этого handlePushData ниже тихо
  // выходит по `!isAuthenticated`, и входящий звонок никогда не показывается.
  await AuthService.instance.init();

  if (IncomingCallPayload.isChatCall(message.data)) {
    await IncomingCallService.instance.handlePushData(message.data);
  }
}
