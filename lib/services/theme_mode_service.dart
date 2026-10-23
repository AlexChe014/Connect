import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Выбранное оформление: светлое, тёмное или как в системе.
///
/// Живёт только на устройстве. По умолчанию — как в системе; вручную
/// меняется в «Ещё → Оформление».
class ThemeModeService {
  ThemeModeService._();
  static final ThemeModeService instance = ThemeModeService._();

  static const _key = 'app_theme_mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value = switch (prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }
}
