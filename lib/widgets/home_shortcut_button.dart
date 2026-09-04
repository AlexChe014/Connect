import 'package:flutter/cupertino.dart';

import '../services/app_navigation_service.dart';
import '../services/root_stack_observer.dart';

/// Плавающая кнопка «на главный экран» поверх всего приложения. Появляется,
/// когда пользователь зашёл на 2+ уровня вглубь раздела, открытого поверх
/// `MainNavigationScreen` (Почта, Диск, Бонусы, Сотрудники и т.д.), и одним
/// тапом возвращает к таб-бару/боковому меню вместо серии нажатий «назад».
class HomeShortcutButton extends StatelessWidget {
  const HomeShortcutButton({super.key});

  /// На первом уровне ("назад" и так один тап до дома) кнопка не нужна.
  static const int _visibleFromDepth = 3;

  /// Принудительно скрывает кнопку поверх экранов, где переход на главный
  /// экран молча отменил бы текущее действие без возможности вернуться
  /// (например, экран «Звоним…» — `popUntil` до корня сбрасывает звонок).
  static final ValueNotifier<bool> suppressed = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        RootStackObserver.instance.depth,
        suppressed,
      ]),
      builder: (context, child) {
        final depth = RootStackObserver.instance.depth.value;
        if (depth < _visibleFromDepth || suppressed.value) {
          return const SizedBox.shrink();
        }
        return child!;
      },
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 16),
            child: _HomeButton(),
          ),
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton();

  void _goHome() {
    AppNavigationService.navigatorKey.currentState?.popUntil(
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _goHome,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CupertinoColors.systemBackground.resolveFrom(context),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.house_fill,
          color: CupertinoColors.activeBlue.resolveFrom(context),
          size: 22,
        ),
      ),
    );
  }
}
