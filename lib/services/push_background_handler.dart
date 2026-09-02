import 'package:connect/firebase_options.dart';
import 'package:connect/models/incoming_call_payload.dart';
import 'package:connect/services/incoming_call_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!DefaultFirebaseOptions.isConfigured) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (IncomingCallPayload.isChatCall(message.data)) {
    await IncomingCallService.instance.handlePushData(message.data);
  }
}
