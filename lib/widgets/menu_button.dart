import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Кнопка-бургер для `leading:` навбара корневых экранов нижнего меню —
/// открывает боковой `Drawer`, объявленный в `MainNavigationScreen`.
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => Scaffold.of(context).openDrawer(),
      child: const Icon(CupertinoIcons.line_horizontal_3, size: 26),
    );
  }
}
