import 'package:flutter/cupertino.dart';

/// Белая иконка на цветном скруглённом квадрате — как в «Настройках» iOS.
/// Используется в строках профиля и бокового меню.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }
}
