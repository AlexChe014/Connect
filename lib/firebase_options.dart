import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Конфигурация Firebase проекта `xonconnect-2a433`.
/// Перегенерация: `flutterfire configure --project=xonconnect-2a433`
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
    apiKey: 'AIzaSyBuVX7zdtSHBuWpfgTc0sBCATUa0G7nmts',
    appId: '1:303524150014:android:48bfed566129d021c783af',
    messagingSenderId: '303524150014',
    projectId: 'xonconnect-2a433',
    storageBucket: 'xonconnect-2a433.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB36fqozU1czYkU5AZEPD8TMnrJOsMoNHs',
    appId: '1:303524150014:ios:3f8465275f5b05c5c783af',
    messagingSenderId: '303524150014',
    projectId: 'xonconnect-2a433',
    storageBucket: 'xonconnect-2a433.firebasestorage.app',
    iosBundleId: 'com.example.connect',
  );
}
