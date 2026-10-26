import 'package:flutter/widgets.dart';

/// Считает глубину page-route стека корневого [Navigator], чтобы шапка
/// ([AppTitleBar]) показала домик возврата в [MainNavigationScreen] на
/// экранах в 2+ уровнях от него — без него приходится жать «назад» по разу
/// на каждый вложенный экран. Модальные шторки и диалоги (`PopupRoute`) не
/// считаются.
class RootStackObserver extends NavigatorObserver {
  RootStackObserver._();

  static final RootStackObserver instance = RootStackObserver._();

  final ValueNotifier<int> depth = ValueNotifier<int>(0);
  final List<Route<dynamic>> _stack = [];

  void _sync() => depth.value = _stack.length;

  /// Позиция [route] в стеке с 1 (корень); 0 — маршрут не из корневого
  /// Navigator или уже снят.
  int positionOf(Route<dynamic> route) => _stack.indexOf(route) + 1;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _stack.add(route);
      _sync();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _stack.remove(route);
      _sync();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _stack.remove(route);
      _sync();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PageRoute) _stack.remove(oldRoute);
    if (newRoute is PageRoute) _stack.add(newRoute);
    _sync();
  }
}
