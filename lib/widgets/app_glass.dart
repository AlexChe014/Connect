import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';

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
    // Тень рисуется поверх и только снаружи формы: под полупрозрачным
    // стеклом обычная тень просвечивает и размывается внутрь панели —
    // у нижнего края появляется вторая, «грязная» тень.
    return CustomPaint(
      foregroundPainter: shadows == null || shadows!.isEmpty
          ? null
          : _OuterShadowPainter(borderRadius: borderRadius, shadows: shadows!),
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

/// Тени [AppGlass] только за пределами скруглённой формы.
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter({required this.borderRadius, required this.shadows});

  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = borderRadius.toRRect(Offset.zero & size);
    var reach = 0.0;
    for (final s in shadows) {
      final r = s.blurRadius * 2 + s.spreadRadius.abs() + s.offset.distance;
      if (r > reach) reach = r;
    }
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect((Offset.zero & size).inflate(reach)),
        Path()..addRRect(rrect),
      ),
    );
    for (final s in shadows) {
      canvas.drawRRect(
        rrect.shift(s.offset).inflate(s.spreadRadius),
        s.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.borderRadius != borderRadius || old.shadows != shadows;
}

/// Мягкое цветное пятно за шапкой экрана: стеклу есть что размывать,
/// иначе на ровном сером оно выглядит как обычная карточка.
/// Кладётся первым ребёнком `Stack` под прокручиваемым содержимым.
class AppGlassGlow extends StatelessWidget {
  const AppGlassGlow({super.key, this.height = 420});

  final double height;

  @override
  Widget build(BuildContext context) {
    final groupedBg = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withValues(alpha: 0.22),
                AppColors.primary.withValues(alpha: 0.08),
                groupedBg.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Длинный ленивый список на «стекле» без размытия: BackdropFilter под
/// сотнями строк дорог, а ниже шапки размывать всё равно нечего —
/// та же заливка, кромка и тень, что у [AppGlass].
class AppGlassSliverList extends StatelessWidget {
  const AppGlassSliverList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorIndent = 72,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final double separatorIndent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return SliverPadding(
      padding: padding,
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: isDark ? const Color(0x80303032) : const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0x26FFFFFF) : const Color(0xB3FFFFFF),
          ),
          boxShadow: AppGlass.controlShadow,
        ),
        sliver: SliverList.separated(
          itemCount: itemCount,
          separatorBuilder: (context, index) => Container(
            height: 0.5,
            margin: EdgeInsets.only(left: separatorIndent),
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

/// Секция списка на стекле вместо сплошной подложки insetGrouped.
class AppGlassSection extends StatelessWidget {
  const AppGlassSection({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(16, 20, 16, 0),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          backgroundColor: const Color(0x00000000),
          decoration: const BoxDecoration(),
          children: children,
        ),
      ),
    );
  }
}

/// Подпись над стеклянной секцией — капсом, как у системных списков.
class AppGlassSectionLabel extends StatelessWidget {
  const AppGlassSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 6),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Кнопка быстрого действия — стеклянная плитка с иконкой и подписью,
/// как в карточке контакта iOS 26.
class AppGlassActionButton extends StatelessWidget {
  const AppGlassActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.label.resolveFrom(context);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: AppGlass(
        borderRadius: BorderRadius.circular(18),
        shadows: AppGlass.controlShadow,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          minimumSize: Size.zero,
          onPressed: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка на «стекле» без размытия: заливка, кромка и тень как у
/// [AppGlass]. Для длинного содержимого (лента, письмо): BackdropFilter
/// под ним дорог, а платформенное представление (WebView письма) под ним
/// на iOS рендерится с артефактами.
class AppFlatGlassCard extends StatelessWidget {
  const AppFlatGlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0x80303032) : const Color(0xCCFFFFFF),
        borderRadius: radius,
        border: Border.all(
          color: isDark ? const Color(0x26FFFFFF) : const Color(0xB3FFFFFF),
        ),
        boxShadow: AppGlass.controlShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
