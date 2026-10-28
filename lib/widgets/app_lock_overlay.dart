import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../config/branding.dart';
import '../services/app_lock_service.dart';
import '../services/sign_out.dart';

/// Экран блокировки и заставка переключателя приложений поверх всего
/// приложения (кроме звонка — он остаётся доступен, как в системе).
class AppLockOverlay extends StatelessWidget {
  const AppLockOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final lock = AppLockService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: lock.locked,
      builder: (context, locked, _) {
        if (locked) return const _LockScreen();
        return ValueListenableBuilder<bool>(
          valueListenable: lock.obscured,
          builder: (context, obscured, _) =>
              obscured ? const _Cover() : const SizedBox.shrink(),
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // Перекрывает и касания, и VoiceOver для экранов под ним.
      child: BlockSemantics(
        child: ColoredBox(
          color: AppColors.groupedBackground.resolveFrom(context),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      BrandingAssets.appIconPng,
                      width: 76,
                      height: 76,
                    ),
                  ),
                  const Spacer(flex: 3),
                  ?child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> with WidgetsBindingObserver {
  /// Запрос показываем сам только после настоящего ухода в фон: отмена
  /// Face ID тоже возвращает приложение в resumed (из inactive), и без
  /// этой проверки запрос всплывал бы снова бесконечно.
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptIfForeground());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      _promptIfForeground();
    }
  }

  void _promptIfForeground() {
    if (!mounted) return;
    // Старт из пуша или CallKit в фоне: запрос появится при открытии.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _wasInBackground = true;
      return;
    }
    AppLockService.instance.unlock();
  }

  /// Подтверждение выхода — прямо на экране: он лежит над Navigator,
  /// диалог отсюда открылся бы под ним.
  bool _confirmSignOut = false;
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await signOut();
  }

  @override
  Widget build(BuildContext context) {
    final method = AppLockService.instance.methodName;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return _Cover(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
        child: Column(
          children: [
            const Text(
              'Connect заблокирован',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Разблокируйте, чтобы продолжить',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: secondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: AppLockService.instance.unlock,
                child: Text(
                  method == 'Face ID' || method == 'Touch ID'
                      ? 'Войти с $method'
                      : 'Разблокировать',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_signingOut)
              const Padding(
                padding: EdgeInsets.all(14),
                child: CupertinoActivityIndicator(),
              )
            else if (_confirmSignOut)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CupertinoButton(
                    onPressed: () => setState(() => _confirmSignOut = false),
                    child: const Text('Отмена', style: TextStyle(fontSize: 15)),
                  ),
                  CupertinoButton(
                    onPressed: _signOut,
                    child: Text(
                      'Выйти',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.destructiveRed.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              CupertinoButton(
                onPressed: () => setState(() => _confirmSignOut = true),
                child: Text(
                  'Выйти из аккаунта',
                  style: TextStyle(fontSize: 15, color: secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
