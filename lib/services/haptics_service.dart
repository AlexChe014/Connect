import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

/// Тактильный отклик приложения — единая точка для всех «щелчков».
///
/// Системная настройка телефона учитывается самой ОС; поверх неё —
/// свой переключатель в «Ещё → Тактильный отклик». По умолчанию включён.
class AppHaptics {
  AppHaptics._();

  static const _key = 'app_haptics_enabled';

  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    if (value) selection();
  }

  /// Переключение вкладок, сегментов, пикеров.
  static void selection() {
    if (enabled.value) HapticFeedback.selectionClick();
  }

  /// Отправка сообщения, реакция, нажатие на мелкое действие.
  static void light() {
    if (enabled.value) HapticFeedback.lightImpact();
  }

  /// Долгое нажатие, срабатывание свайпа, pull-to-refresh.
  static void medium() {
    if (enabled.value) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled.value) HapticFeedback.heavyImpact();
  }

  /// Обёртка для pull-to-refresh: щелчок в момент срабатывания.
  static Future<void> Function() onRefresh(Future<void> Function() load) {
    return () {
      medium();
      return load();
    };
  }

  /// Операция завершилась успешно (подписание, отправка письма).
  static Future<void> success() async {
    if (!enabled.value) return;
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }

  /// Ошибка: резкий отклик, отличимый от успеха.
  static Future<void> error() async {
    if (!enabled.value) return;
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.heavyImpact();
  }
}
