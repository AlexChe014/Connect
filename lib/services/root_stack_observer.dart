import 'package:flutter/widgets.dart';

/// Считает глубину page-route стека корневого [Navigator], чтобы показать
/// быструю кнопку возврата в [MainNavigationScreen] из любого раздела,
/// открытого через `Navigator.push` поверх него (Почта, Диск, Бонусы,
/// Сотрудники и т.д.) — без неё приходится жать «назад» по разу на каждый
/// вложенный экран. Модальные шторки и диалоги (`PopupRoute`) не считаются,
/// т.к. их не нужно перекрывать этой кнопкой.
class RootStackObserver extends NavigatorObserver {
  RootStackObserver._();

  static final RootStackObserver instance = RootStackObserver._();

  final ValueNotifier<int> depth = ValueNotifier<int>(0);
  final List<Route<dynamic>> _stack = [];

  void _sync() => depth.value = _stack.length;

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
