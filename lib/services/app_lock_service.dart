import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Через сколько после ухода в фон приложение снова попросит Face ID.
enum AppLockDelay {
  immediately(Duration(seconds: 10), 'Сразу'),
  oneMinute(Duration(minutes: 1), 'Через 1 минуту'),
  fiveMinutes(Duration(minutes: 5), 'Через 5 минут'),
  fifteenMinutes(Duration(minutes: 15), 'Через 15 минут');

  const AppLockDelay(this.duration, this.label);

  /// «Сразу» — с запасом в 10 секунд: на Android камера, выбор файла и
  /// системный диалог разрешений уводят приложение в фон, и без запаса
  /// после каждой фотографии пришлось бы снова смотреть в камеру.
  final Duration duration;
  final String label;
}

/// Замок приложения по Face ID / Touch ID / отпечатку (с запасным
/// код-паролем устройства). Только на устройстве, бэкенд не участвует.
///
/// Включается в «Ещё». Запирает при холодном старте и при возврате из фона
/// дольше [AppLockDelay]; пока приложение неактивно (переключатель
/// приложений), содержимое закрыто [obscured], чтобы не попасть в снимок.
class AppLockService with WidgetsBindingObserver {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _enabledKey = 'app_lock_enabled';
  static const _delayKey = 'app_lock_delay';
  static const _channel = MethodChannel('connect/app_lock');

  final LocalAuthentication _auth = LocalAuthentication();

  final ValueNotifier<bool> enabled = ValueNotifier(false);
  final ValueNotifier<AppLockDelay> delay = ValueNotifier(
    AppLockDelay.immediately,
  );

  /// Показан экран блокировки.
  final ValueNotifier<bool> locked = ValueNotifier(false);

  /// Приложение неактивно — поверх всего заставка без содержимого.
  final ValueNotifier<bool> obscured = ValueNotifier(false);

  /// Устройство умеет локальную аутентификацию (биометрия или код-пароль).
  bool supported = false;

  /// Название способа для подписей: «Face ID», «Touch ID», «отпечаток».
  String methodName = 'код-пароль';

  DateTime? _backgroundedAt;
  bool _authenticating = false;

  bool get _active => enabled.value && AuthService.instance.isAuthenticated;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? false;
    delay.value = AppLockDelay.values.firstWhere(
      (d) => d.name == prefs.getString(_delayKey),
      orElse: () => AppLockDelay.immediately,
    );
    try {
      supported = await _auth.isDeviceSupported();
      if (supported) {
        methodName = _methodName(await _auth.getAvailableBiometrics());
      }
    } catch (_) {
      supported = false;
    }
    // Биометрию или код на устройстве сняли — замок не открыть, выключаем.
    if (!supported && enabled.value) await _setEnabled(false);
    locked.value = _active;
    _syncRecentsHidden();
    WidgetsBinding.instance.addObserver(this);
  }

  static String _methodName(List<BiometricType> types) {
    if (Platform.isIOS) {
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint)) return 'Touch ID';
      return 'код-пароль';
    }
    if (types.contains(BiometricType.face)) return 'распознавание лица';
    if (types.isNotEmpty) return 'отпечаток';
    return 'блокировку экрана';
  }

  /// Включение — только после успешной проверки, чтобы не запереться
  /// способом, который на этом устройстве не срабатывает.
  Future<bool> enable() async {
    if (!await _authenticate('Включить вход в Connect по $methodName')) {
      return false;
    }
    await _setEnabled(true);
    return true;
  }

  Future<void> disable() => _setEnabled(false);

  Future<void> setDelay(AppLockDelay value) async {
    delay.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_delayKey, value.name);
  }

  /// При выходе из аккаунта: следующий пользователь включит замок сам.
  Future<void> reset() async {
    dismiss();
    await _setEnabled(false);
  }

  /// Сессия истекла — замок снимаем, настройку оставляем тому же человеку.
  void dismiss() {
    locked.value = false;
    obscured.value = false;
    _backgroundedAt = null;
  }

  Future<void> _setEnabled(bool value) async {
    enabled.value = value;
    _syncRecentsHidden();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// На Android заставка не успевает попасть в превью «Недавних» —
  /// превью при включённом замке прячет сама система (MainActivity).
  void _syncRecentsHidden() {
    if (!Platform.isAndroid) return;
    _channel
        .invokeMethod<void>('setRecentsHidden', enabled.value)
        .catchError((Object e) => debugPrint('AppLock: $e'));
  }

  /// Показать системный запрос и снять замок при успехе.
  Future<void> unlock() async {
    if (!locked.value) return;
    if (await _authenticate('Разблокировать Connect')) {
      locked.value = false;
    }
  }

  Future<bool> _authenticate(String reason) async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        authMessages: const [
          IOSAuthMessages(
            cancelButton: 'Отмена',
            localizedFallbackTitle: 'Ввести код-пароль',
          ),
          AndroidAuthMessages(
            signInTitle: 'Connect',
            signInHint: 'Подтвердите, что это вы',
            cancelButton: 'Отмена',
          ),
        ],
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      debugPrint('AppLock: ${e.code} ${e.description}');
      return false;
    } catch (e) {
      debugPrint('AppLock: $e');
      return false;
    } finally {
      _authenticating = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) {
      obscured.value = false;
      return;
    }
    switch (state) {
      case AppLifecycleState.inactive:
        // Системный запрос Face ID тоже делает приложение неактивным —
        // под ним и так экран блокировки, заставка не нужна.
        if (!_authenticating) obscured.value = true;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        obscured.value = true;
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            DateTime.now().difference(since) >= delay.value.duration) {
          locked.value = true;
        }
        obscured.value = false;
      case AppLifecycleState.detached:
        break;
    }
  }
}
