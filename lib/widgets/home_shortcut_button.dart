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

  /// Сколько активных причин скрыть кнопку сейчас есть (экран звонка, сама
  /// видеоконференция, список/экран чата и т.п.). Счётчик, а не простой
  /// bool: несколько источников могут просить скрыть кнопку одновременно
  /// (например, звонок, начатый из чата, — суппрессит и сам чат, и звонок),
  /// и снятие запроса одним из них не должно преждевременно показать
  /// кнопку, пока другой ещё активен.
  static final ValueNotifier<int> _suppressCount = ValueNotifier<int>(0);

  /// Скрывает кнопку, пока не будет вызван возвращённый колбэк (обычно из
  /// `dispose`/`finally`). Экраны, где переход на главный экран молча
  /// отменил бы текущее действие без возможности вернуться (например,
  /// «Звоним…» — `popUntil` до корня сбросил бы звонок), а также разделы,
  /// где этой кнопке вообще не место (чаты — см. ChatsListScreen,
  /// ChatConversationScreen), держат её скрытой всё время, пока они
  /// смонтированы. Безопасно вызывать вложенно и звать колбэк повторно.
  static VoidCallback suppress() {
    _suppressCount.value++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _suppressCount.value--;
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        RootStackObserver.instance.depth,
        _suppressCount,
      ]),
      builder: (context, child) {
        final depth = RootStackObserver.instance.depth.value;
        if (depth < _visibleFromDepth || _suppressCount.value > 0) {
          return const SizedBox.shrink();
        }
        return child!;
      },
      child: SafeArea(
        // bottomLeft — намеренно не bottomRight: экран почты держит там
        // свою кнопку «написать письмо», и обе кнопки в одном углу
        // накладывались друг на друга.
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 16),
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
