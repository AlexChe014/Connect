import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Стабильный идентификатор установки приложения.
///
/// Нужен бэкенду, чтобы при ответе/отклонении звонка на одном устройстве
/// погасить звонок на остальных устройствах того же пользователя (и в вебе),
/// не трогая само устройство-инициатор. Передаётся в `device_id` при
/// регистрации FCM/VoIP-токенов и в действиях со звонками.
class DeviceIdentity {
  DeviceIdentity._();
  static final DeviceIdentity instance = DeviceIdentity._();

  static const _prefsKey = 'device_install_id';

  String? _cached;

  Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_prefsKey);
    if (value == null || value.isEmpty) {
      value = _generate();
      await prefs.setString(_prefsKey, value);
    }
    _cached = value;
    return value;
  }

  String get platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  static String _generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
