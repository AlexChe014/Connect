import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import 'app_glass.dart';
import 'app_title_bar.dart';
import 'confetti_overlay.dart';
import '../services/haptics_service.dart';

/// Общие детали раздела «Бонусная программа» в стиле Liquid Glass:
/// прозрачная шапка над цветным пятном, содержимое на стеклянных карточках.

/// «1 балл», «3 балла», «1 600 баллов».
String formatPoints(int points) =>
    '${NumberFormat.decimalPattern('ru_RU').format(points)} '
    '${pointsWord(points)}';

/// Слово «балл» в форме для числа [points].
String pointsWord(int points) {
  final n = points.abs() % 100;
  final last = n % 10;
  if (n >= 11 && n <= 14) return 'баллов';
  if (last == 1) return 'балл';
  if (last >= 2 && last <= 4) return 'балла';
  return 'баллов';
}

/// Экран раздела: прозрачная шапка с кнопкой «назад», под ней
/// `CustomScrollView` из [slivers]. С [largeTitle] — заголовок в строке
/// с кнопками ([AppSliverTitleBar]), как у корневых экранов «Ещё».
class BonusGlassScaffold extends StatelessWidget {
  const BonusGlassScaffold({
    super.key,
    required this.title,
    this.slivers = const [],
    this.body,
    this.glow = const AppGlassGlow(),
    this.trailing,
    this.onRefresh,
    this.controller,
    this.largeTitle = false,
    this.canPop = true,
  });

  final String title;
  final List<Widget> slivers;

  /// Непрокручиваемое содержимое вместо [slivers] — под шапкой, на всю
  /// оставшуюся высоту (колесо фортуны).
  final Widget? body;

  /// Цветное пятно за шапкой — первый ребёнок `Stack` (обычно `Positioned`).
  final Widget glow;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final bool largeTitle;

  /// `false` — пока идёт отправка, «назад» неактивна.
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final groupedBg = AppColors.groupedBackground.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    // Прозрачная: заливка дала бы на цветном пятне видимую границу.
    final barBg = groupedBg.withValues(alpha: 0);
    final back = CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: canPop ? () => Navigator.maybePop(context) : null,
      child: Icon(
        CupertinoIcons.back,
        size: AppSliverTitleBar.iconSize,
        color: label,
      ),
    );

    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: groupedBg,
        navigationBar: largeTitle
            ? null
            : AppTitleBar(
                title: Text(title),
                leading: back,
                trailing: trailing,
                backgroundColor: barBg,
                blur: blur,
              ),
        // Без Material-предка любой Text, не переопределивший все поля стиля
        // явно, откатывается на debug-заглушку MaterialApp.
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: label,
            fontSize: 16,
          ),
          child: Stack(
            children: [
              glow,
              Builder(
                // Свой context — под скаффолдом, где в MediaQuery уже учтена
                // высота полупрозрачной шапки.
                builder: (context) {
                  if (body != null) {
                    return Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top,
                      ),
                      child: body,
                    );
                  }
                  final view = CustomScrollView(
                    controller: controller,
                    // Иначе на коротком экране не тянется pull-to-refresh.
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      if (largeTitle)
                        AppSliverTitleBar(
                          title: Text(title),
                          leading: back,
                          trailing: trailing,
                          blur: blur,
                        )
                      else
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaQuery.paddingOf(context).top + 12,
                          ),
                        ),
                      ...slivers,
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.paddingOf(context).bottom + 32,
                        ),
                      ),
                    ],
                  );
                  final refresh = onRefresh;
                  if (refresh == null) return view;
                  return RefreshIndicator.adaptive(
                    onRefresh: AppHaptics.onRefresh(refresh),
                    child: view,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Индикатор первой загрузки на месте всего содержимого.
class BonusSliverLoader extends StatelessWidget {
  const BonusSliverLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: CupertinoActivityIndicator(radius: 14)),
    );
  }
}

/// Праздничная карточка поверх экрана — выигрыш в колесе, покупка в
/// магазине: конфетти, фото приза в медальоне и статус заявки.
Future<void> showBonusCelebration(
  BuildContext context, {
  required String title,
  required String message,
  String? status,
  Color? statusColor,
  String? photoUrl,
  IconData icon = CupertinoIcons.gift_fill,
  bool celebrate = true,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'bonus-celebration',
    barrierColor: AppColors.scrim,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (context, anim, secondaryAnim, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Opacity(
        opacity: anim.value.clamp(0, 1),
        child: Transform.scale(
          scale: 0.7 + 0.3 * curved.value.clamp(0, 1.2),
          child: Center(
            child: _BonusCelebrationCard(
              title: title,
              message: message,
              status: status,
              statusColor: statusColor,
              photoUrl: photoUrl,
              icon: icon,
              celebrate: celebrate,
            ),
          ),
        ),
      );
    },
  );
}

class _BonusCelebrationCard extends StatelessWidget {
  const _BonusCelebrationCard({
    required this.title,
    required this.message,
    required this.status,
    required this.statusColor,
    required this.photoUrl,
    required this.icon,
    required this.celebrate,
  });

  final String title;
  final String message;
  final String? status;
  final Color? statusColor;
  final String? photoUrl;
  final IconData icon;
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final fallbackIcon = Icon(icon, color: CupertinoColors.white, size: 32);
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.SF Pro Text',
        color: CupertinoColors.label.resolveFrom(context),
        decoration: TextDecoration.none,
      ),
      child: SizedBox(
        width: 300,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            if (celebrate)
              const Positioned(
                top: -60,
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: ConfettiOverlay(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 38),
              child: AppGlass(
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 50, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          status!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CupertinoDynamicColor.resolve(
                              statusColor ??
                                  CupertinoColors.secondaryLabel.resolveFrom(
                                    context,
                                  ),
                              context,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      AppPrimaryButton(
                        label: 'Отлично!',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: celebrate
                      ? AppFestiveColors.medalGradient
                      : [
                          CupertinoColors.systemGrey3.resolveFrom(context),
                          CupertinoColors.systemGrey.resolveFrom(context),
                        ],
                ),
                border: Border.all(
                  color: CupertinoColors.white.withValues(alpha: 0.9),
                  width: 4,
                ),
                boxShadow: AppGlass.controlShadow,
              ),
              child: photoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: photoUrl!,
                      fit: BoxFit.cover,
                      width: 72,
                      height: 72,
                      errorWidget: (context, url, error) => fallbackIcon,
                    )
                  : fallbackIcon,
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка товара или приза в сетке: фото на светлой подложке сверху,
/// подпись и [footer] снизу. Без размытия — карточек в сетке много.
class BonusPhotoCard extends StatelessWidget {
  const BonusPhotoCard({
    super.key,
    required this.photoUrl,
    required this.title,
    this.footer,
    this.badge,
    this.onTap,
    this.dimmed = false,
  });

  final String? photoUrl;
  final String title;
  final Widget? footer;

  /// Плашка поверх фото слева сверху (например, «Нет в наличии»).
  final Widget? badge;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Icon(
        CupertinoIcons.gift_fill,
        size: 40,
        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: AppFlatGlassCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: CupertinoColors.tertiarySystemFill.resolveFrom(
                          context,
                        ),
                        child: photoUrl != null
                            ? CachedNetworkImage(
                                imageUrl: photoUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) =>
                                    placeholder,
                              )
                            : placeholder,
                      ),
                      if (badge != null)
                        Positioned(top: 6, left: 6, child: badge!),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 0, 0),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
