import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';

/// Единый пустой/ошибочный стейт для списков — заменяет копипасту
/// `Center(child: Text('Пока нет...'))` по экранам.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.icon = CupertinoIcons.tray,
    this.onRetry,
    this.retryLabel = 'Повторить',
    this.scrollable = true,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Когда `false`, возвращает только контент без [LayoutBuilder].
  /// Нужно для [SliverFillRemaining], который запрашивает intrinsic-размеры.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = _AppEmptyStateContent(
      message: message,
      icon: icon,
      onRetry: onRetry,
      retryLabel: retryLabel,
    );

    if (!scrollable) return content;

    // Скроллящийся контейнер, а не просто Center — иначе жест
    // pull-to-refresh не работает, когда этот виджет — единственный
    // потомок RefreshIndicator (нет Scrollable-предка). Но когда высота
    // не ограничена (виджет — просто один из children обычного
    // ListView), центрировать через minHeight нельзя — упадёт с
    // "infinite height", поэтому в этом случае отдаём контент как есть.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return content;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

/// Пустой стейт для [CustomScrollView] — без [LayoutBuilder], совместим
/// с pull-to-refresh через [AlwaysScrollableScrollPhysics].
class SliverAppEmptyState extends StatelessWidget {
  const SliverAppEmptyState({
    super.key,
    required this.message,
    this.icon = CupertinoIcons.tray,
    this.onRetry,
    this.retryLabel = 'Повторить',
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final minHeight = MediaQuery.sizeOf(context).height * 0.55;

    return SliverToBoxAdapter(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Center(
            child: _AppEmptyStateContent(
              message: message,
              icon: icon,
              onRetry: onRetry,
              retryLabel: retryLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppEmptyStateContent extends StatelessWidget {
  const _AppEmptyStateContent({
    required this.message,
    required this.icon,
    this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            CupertinoButton(
              onPressed: onRetry,
              child: Text(
                retryLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
