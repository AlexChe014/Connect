import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Отправка необработанных ошибок в Firebase Crashlytics.
///
/// Должен вызываться после [PushNotificationService.init] (тот вызывает
/// `Firebase.initializeApp`) — если Firebase не инициализирован (веб,
/// dev-сборка без `flutterfire configure`), тихо ничего не делает: репортинг
/// не критичен для работы приложения.
class CrashReportingService {
  CrashReportingService._();

  static bool get _isAvailable => !kIsWeb && Firebase.apps.isNotEmpty;

  /// Включает сбор крашей и подписывается на необработанные ошибки Flutter
  /// (`FlutterError.onError`) и платформы (`PlatformDispatcher.onError`).
  ///
  /// Сбор включён только в релизной сборке — в debug ошибки и так видны в
  /// консоли, незачем засорять ими Crashlytics при разработке.
  static Future<void> init() async {
    if (!_isAvailable) return;

    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      kReleaseMode,
    );

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Для ошибок вне зоны Flutter — из `runZonedGuarded` в `main()`.
  static void recordError(Object error, StackTrace stack) {
    if (!_isAvailable) return;
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  }
}
