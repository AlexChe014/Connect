import 'dart:io';

import 'package:connect/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';

/// Результат проверки разрешений перед звонком.
class CallPermissionsResult {
  const CallPermissionsResult({
    required this.camera,
    required this.microphone,
    required this.notifications,
    this.fullScreenIntent = true,
  });

  final bool camera;
  final bool microphone;
  final bool notifications;
  final bool fullScreenIntent;

  bool get mediaOk => camera && microphone;

  bool get canStartCall => mediaOk;

  String? get denialMessage {
    if (!camera && !microphone) {
      return 'Нужен доступ к камере и микрофону для звонка';
    }
    if (!camera) return 'Нужен доступ к камере для видеозвонка';
    if (!microphone) return 'Нужен доступ к микрофону для звонка';
    if (!notifications) {
      return 'Включите уведомления, иначе входящий звонок может не прийти';
    }
    if (!fullScreenIntent) {
      return 'Разрешите полноэкранные уведомления, '
          'чтобы принимать звонки на заблокированном экране';
    }
    return null;
  }
}

/// Запрос разрешений для 1:1 звонков (CallKit + Jitsi).
class CallPermissions {
  CallPermissions._();

  /// Перед исходящим звонком: камера, микрофон, уведомления, full-screen (Android).
  static Future<CallPermissionsResult> ensureForOutgoingCall() async {
    if (kIsWeb) {
      return const CallPermissionsResult(
        camera: true,
        microphone: true,
        notifications: true,
      );
    }

    final media = await [Permission.camera, Permission.microphone].request();
    final camera = media[Permission.camera]?.isGranted ?? false;
    final microphone = media[Permission.microphone]?.isGranted ?? false;

    var notifications = true;
    if (Platform.isAndroid || Platform.isIOS) {
      final n = await Permission.notification.request();
      notifications = n.isGranted || n.isLimited || n.isProvisional;
    }

    var fullScreenIntent = true;
    if (Platform.isAndroid) {
      try {
        fullScreenIntent =
            await FlutterCallkitIncoming.canUseFullScreenIntent();
        if (!fullScreenIntent) {
          await FlutterCallkitIncoming.requestFullIntentPermission();
          fullScreenIntent =
              await FlutterCallkitIncoming.canUseFullScreenIntent();
        }
      } catch (e, st) {
        AppLogger.d(
          'Full-screen intent check failed',
          name: 'call.permissions',
          error: e,
          stackTrace: st,
        );
      }
    }

    return CallPermissionsResult(
      camera: camera,
      microphone: microphone,
      notifications: notifications,
      fullScreenIntent: fullScreenIntent,
    );
  }

  /// Перед входом в Jitsi после Accept (камера + микрофон).
  static Future<bool> ensureMediaOnly() async {
    if (kIsWeb) return true;
    await _waitForForegroundIfNeeded();
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    return (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);
  }

  /// iOS не показывает системный алерт запроса камеры/микрофона, пока
  /// приложение в фоне — если это первый Accept звонка (разрешение ещё не
  /// выдано) сразу после подъёма CallKit, .request() может тихо не
  /// показать диалог, пока сцена ещё поднимается на передний план.
  /// Пропускаем, если разрешения уже выданы — тогда .request() и так не
  /// показывает UI.
  static Future<void> _waitForForegroundIfNeeded() async {
    if (!Platform.isIOS) return;
    final cameraGranted = await Permission.camera.status.isGranted;
    final microphoneGranted = await Permission.microphone.status.isGranted;
    if (cameraGranted && microphoneGranted) return;

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
