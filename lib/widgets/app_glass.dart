import 'dart:ui';

import 'package:flutter/cupertino.dart';

/// Поверхность в стиле Liquid Glass: размытый и чуть насыщенный фон
/// под полупрозрачной заливкой, светлая кромка и мягкая тень.
/// Боковое меню, поле ввода чата и другие плавающие панели.
class AppGlass extends StatelessWidget {
  const AppGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.shadows = panelShadow,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final List<BoxShadow>? shadows;

  /// Тень крупной плавающей панели (боковое меню).
  static const panelShadow = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  /// Тень мелкого элемента (кнопка, поле ввода) — тише, чтобы соседние
  /// капсулы не сливались в одно пятно.
  static const controlShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 3)),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: const ColorFilter.matrix(_saturate),
            inner: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0x803A3A3C), Color(0x661C1C1E)]
                    : const [Color(0xCCFFFFFF), Color(0x99FFFFFF)],
              ),
              border: Border.all(
                color: isDark
                    ? const Color(0x26FFFFFF)
                    : const Color(0xB3FFFFFF),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Насыщенность фона ×1.6 — как у системного стекла, цвета под панелью
  /// не выцветают от размытия.
  static const List<double> _saturate = [
    1.4808, -0.4576, -0.0232, 0, 0, //
    -0.1272, 1.1424, -0.0152, 0, 0, //
    -0.1272, -0.4576, 1.5848, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}
