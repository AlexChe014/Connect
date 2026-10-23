import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Шапка экрана одной строкой: «назад», заголовок слева и кнопки справа.
///
/// Одна и та же на корневых и вложенных экранах: разная высота шапок
/// заставляла кнопки и контент прыгать при переходе. Между экранами шапка
/// не уезжает вместе со страницей, а стоит на месте и плавно перетекает
/// в новую (общий [Hero]).
///
/// Прозрачная, размытие — только при прокрутке ([blur] из `AppGlassBarBlur`).
/// В `CupertinoPageScaffold.navigationBar` — [AppTitleBar], первым сливером
/// `CustomScrollView` — [AppSliverTitleBar].
class AppTitleBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  const AppTitleBar({
    super.key,
    this.title,
    this.leading,
    this.trailing,
    this.blur = false,
    this.backgroundColor,
  });

  /// Высота строки без статус-бара.
  static const height = 52.0;

  /// Единый размер иконок в шапках.
  static const iconSize = 24.0;

  static const titleStyle = TextStyle(
    inherit: false,
    fontFamily: 'CupertinoSystemDisplay',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    decoration: TextDecoration.none,
  );

  final Widget? title;

  /// Без него на вложенном экране — стрелка «назад».
  final Widget? leading;
  final Widget? trailing;
  final bool blur;

  /// По умолчанию прозрачная: заливка дала бы на цветном пятне границу.
  final Color? backgroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  bool shouldFullyObstruct(BuildContext context) {
    final bg = backgroundColor;
    return bg != null && CupertinoDynamicColor.resolve(bg, context).a == 1;
  }

  @override
  Widget build(BuildContext context) {
    return _TitleBar(bar: this, topPadding: MediaQuery.paddingOf(context).top);
  }
}

/// [AppTitleBar] закреплённым сливером — для экранов с `CustomScrollView`.
class AppSliverTitleBar extends StatelessWidget {
  const AppSliverTitleBar({
    super.key,
    this.title,
    this.leading,
    this.trailing,
    this.blur = false,
    this.backgroundColor,
  });

  static const iconSize = AppTitleBar.iconSize;

  final Widget? title;
  final Widget? leading;
  final Widget? trailing;
  final bool blur;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TitleBarDelegate(
        topPadding: MediaQuery.paddingOf(context).top,
        bar: AppTitleBar(
          title: title,
          leading: leading,
          trailing: trailing,
          blur: blur,
          backgroundColor: backgroundColor,
        ),
      ),
    );
  }
}

class _TitleBarDelegate extends SliverPersistentHeaderDelegate {
  _TitleBarDelegate({required this.topPadding, required this.bar});

  final double topPadding;
  final AppTitleBar bar;

  @override
  double get minExtent => topPadding + AppTitleBar.height;

  @override
  double get maxExtent => minExtent;

  @override
  bool shouldRebuild(_TitleBarDelegate oldDelegate) => true;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => _TitleBar(bar: bar, topPadding: topPadding);
}

/// Общий тег: шапка исходного и нового экрана — одна пара героев.
const _heroTag = _TitleBarHeroTag();

class _TitleBarHeroTag {
  const _TitleBarHeroTag();
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.bar, required this.topPadding});

  final AppTitleBar bar;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final iconTheme = IconThemeData(size: AppTitleBar.iconSize, color: label);

    var leading = bar.leading;
    if (leading == null && (ModalRoute.of(context)?.canPop ?? false)) {
      leading = CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => Navigator.maybePop(context),
        child: const Icon(CupertinoIcons.back),
      );
    }

    Widget content = Padding(
      padding: EdgeInsets.only(top: topPadding, left: 16, right: 16),
      child: SizedBox(
        height: AppTitleBar.height,
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme.merge(data: iconTheme, child: leading),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: DefaultTextStyle(
                style: AppTitleBar.titleStyle.copyWith(color: label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: bar.title ?? const SizedBox.shrink(),
              ),
            ),
            if (bar.trailing != null) ...[
              const SizedBox(width: 12),
              IconTheme.merge(data: iconTheme, child: bar.trailing!),
            ],
          ],
        ),
      ),
    );

    final bg = bar.backgroundColor;
    if (bg != null) {
      content = ColoredBox(
        color: CupertinoDynamicColor.resolve(bg, context),
        child: content,
      );
    }
    if (bar.blur) {
      content = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: content,
        ),
      );
    }

    // Скрытые вкладки IndexedStack (тикеры выключены) в перелёте не
    // участвуют — иначе у маршрута оказалось бы несколько героев с одним
    // тегом.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: HeroMode(
        enabled: TickerMode.valuesOf(context).enabled,
        child: Hero(
          tag: _heroTag,
          transitionOnUserGestures: true,
          flightShuttleBuilder: _crossFade,
          child: content,
        ),
      ),
    );
  }

  /// Старая шапка гаснет, новая проявляется на том же месте.
  static Widget _crossFade(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final from = (fromHeroContext.widget as Hero).child;
    final to = (toHeroContext.widget as Hero).child;
    // На pop анимация идёт от 1 к 0, и «верхний» экран — исходный.
    final top = direction == HeroFlightDirection.push ? to : from;
    final bottom = direction == HeroFlightDirection.push ? from : to;
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(opacity: ReverseAnimation(curved), child: bottom),
        FadeTransition(opacity: curved, child: top),
      ],
    );
  }
}
