import 'dart:io';

import 'package:connect/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const _batteryExemptionAskedKey = 'battery_optimization_exemption_asked';

  /// Разово (после первого логина) предлагает исключить приложение из
  /// оптимизации батареи Android. Без этого на части прошивок (MIUI, EMUI
  /// и т.п.) система может не поднять headless-движок для входящего звонка
  /// вовсе, если приложение полностью выгружено из памяти — экран Accept
  /// тогда просто не появится. Спрашивает не чаще одного раза за установку,
  /// независимо от ответа пользователя.
  static Future<void> ensureBatteryOptimizationExemptionOnce() async {
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_batteryExemptionAskedKey) ?? false) return;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e, st) {
      AppLogger.d(
        'Battery optimization exemption request failed',
        name: 'call.permissions',
        error: e,
        stackTrace: st,
      );
    } finally {
      await prefs.setBool(_batteryExemptionAskedKey, true);
    }
  }

  /// Перед входом в Jitsi после Accept (камера + микрофон).
  static Future<bool> ensureMediaOnly() async {
    if (kIsWeb) return true;
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    return (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);
  }
}
