import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Центрированный спиннер для мелких мест (кнопка, инлайн-подгрузка страницы),
/// где полноценный skeleton избыточен.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
}

/// Прямоугольный плейсхолдер с бегущим бликом — замена спиннера для
/// карточек списков (лента, сотрудники, бронирования и т.п.), пока
/// не пришли реальные данные.
class AppSkeletonBox extends StatefulWidget {
  const AppSkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<AppSkeletonBox> createState() => _AppSkeletonBoxState();
}

class _AppSkeletonBoxState extends State<AppSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.outline;
    final highlight = AppColors.surfaceElevated;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + _controller.value * 4, 0),
                  end: Alignment(1 + _controller.value * 4, 0),
                  colors: [base, highlight, base],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Заготовка карточки списка (аватар/картинка слева + 2 строки текста) —
/// используется вместо спиннера на месте будущих карточек.
class AppSkeletonListTile extends StatelessWidget {
  const AppSkeletonListTile({super.key, this.hasLeading = true});

  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (hasLeading) ...[
            const AppSkeletonBox(width: 44, height: 44, borderRadius: 22),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(width: MediaQuery.sizeOf(context).width * 0.5),
                const SizedBox(height: AppSpacing.sm),
                const AppSkeletonBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Список из [count] заготовок карточек — подставляется на место
/// `ListView` на время первой загрузки.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({super.key, this.count = 6, this.hasLeading = true});

  final int count;
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: count,
      itemBuilder: (context, index) =>
          AppSkeletonListTile(hasLeading: hasLeading),
    );
  }
}

/// Крупный центрированный индикатор первой загрузки (не список).
class AppPageLoader extends StatelessWidget {
  const AppPageLoader({super.key, this.label = 'Загрузка…'});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CupertinoActivityIndicator(radius: 14),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(
              label!,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Карточка-скелетон в стиле списков (чаты, сотрудники, почта).
class AppSkeletonCardTile extends StatelessWidget {
  const AppSkeletonCardTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: const Row(
        children: [
          AppSkeletonBox(width: 48, height: 48, borderRadius: 24),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(width: 160, height: 14, borderRadius: 6),
                SizedBox(height: 8),
                AppSkeletonBox(height: 10, borderRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
