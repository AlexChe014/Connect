import 'package:flutter/cupertino.dart';

/// Цветная иконка на мягкой подложке того же цвета — как в «Фитнесе» и
/// «Здоровье»: цвет различает строки, но не спорит с контентом, как
/// насыщенные квадраты с белой иконкой.
/// Используется в строках профиля, форм и настроек.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tint = CupertinoDynamicColor.resolve(color, context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // На тёмном фоне те же 15% почти не видны.
        color: tint.withValues(alpha: isDark ? 0.24 : 0.15),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: tint),
    );
  }
}
