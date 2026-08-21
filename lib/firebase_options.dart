import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Сгенерируйте этот файл командой:
/// `dart pub global activate flutterfire_cli && flutterfire configure`
///
/// До настройки Firebase push-уведомления будут отключены.
class DefaultFirebaseOptions {
  static bool get isConfigured =>
      android.apiKey != 'REPLACE_ME' && android.appId != 'REPLACE_ME';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web push is not configured for Connect.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Push notifications are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA4-sOUG_uWV3DzAufuBjsiyww4W5dQYmc',
    appId: '1:826977386147:android:195502a2962d2db70c0916',
    messagingSenderId: '826977386147',
    projectId: 'xonconnect-app',
    storageBucket: 'xonconnect-app.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCcXGOo7FNKkwQp-oQdcZK-iFrVXhr3yg8',
    appId: '1:826977386147:ios:d6eb143d7bd0312e0c0916',
    messagingSenderId: '826977386147',
    projectId: 'xonconnect-app',
    storageBucket: 'xonconnect-app.firebasestorage.app',
    iosBundleId: 'com.example.connect',
  );
}
