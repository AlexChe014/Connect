import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

import 'app_glass.dart';

/// Пункт контекстного меню сообщения.
class MessageMenuItem {
  const MessageMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
}

/// Меню по долгому нажатию на сообщение, как в Telegram: фон размывается,
/// пузырь [preview] остаётся на своём месте (или сдвигается, чтобы всё
/// влезло), над ним — [reactions], под ним — компактный список [items].
///
/// [anchor] — прямоугольник пузыря в глобальных координатах; [alignEnd] —
/// меню прижато к правому краю пузыря (свои сообщения).
Future<void> showMessageContextMenu({
  required BuildContext context,
  required Rect anchor,
  required List<MessageMenuItem> items,
  Widget? preview,
  Widget? reactions,
  bool alignEnd = false,
}) {
  // Пузырь рисуется в другом маршруте — берём стиль текста из чата.
  final textStyle = DefaultTextStyle.of(context).style;
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, _) => _MessageContextMenu(
        animation: animation,
        anchor: anchor,
        items: items,
        preview: preview == null
            ? null
            : DefaultTextStyle(style: textStyle, child: preview),
        reactions: reactions,
        alignEnd: alignEnd,
      ),
    ),
  );
}

class _MessageContextMenu extends StatelessWidget {
  const _MessageContextMenu({
    required this.animation,
    required this.anchor,
    required this.items,
    required this.preview,
    required this.reactions,
    required this.alignEnd,
  });

  static const double _menuWidth = 250;
  static const double _itemHeight = 46;
  static const double _reactionsHeight = 52;
  static const double _gap = 8;
  static const double _edge = 12;

  final Animation<double> animation;
  final Rect anchor;
  final List<MessageMenuItem> items;
  final Widget? preview;
  final Widget? reactions;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final minTop = padding.top + _edge;
    final maxBottom = size.height - padding.bottom - _edge;

    final menuHeight = items.length * _itemHeight;
    final reactionsSpace = reactions == null ? 0.0 : _reactionsHeight + _gap;

    // Длинный пузырь обрезается снизу, чтобы меню и реакции влезли на экран.
    final maxPreview = maxBottom - minTop - menuHeight - _gap - reactionsSpace;
    final previewHeight = math.max(0.0, math.min(anchor.height, maxPreview));

    // Пузырь остаётся на месте, если всё помещается; иначе сдвигается.
    var top = anchor.top;
    final bottomNeeded = top + previewHeight + _gap + menuHeight;
    if (bottomNeeded > maxBottom) top -= bottomNeeded - maxBottom;
    if (top - reactionsSpace < minTop) top = minTop + reactionsSpace;

    final menuLeft = alignEnd
        ? math.max(_edge, anchor.right - _menuWidth)
        : math.min(anchor.left, size.width - _menuWidth - _edge);
    final reactionsLeft = alignEnd
        ? null
        : math.max(_edge, math.min(anchor.left, size.width - _edge));
    final reactionsRight = alignEnd
        ? math.max(_edge, size.width - anchor.right)
        : null;

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    void close() => Navigator.of(context).pop();

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;
        final previewTop = lerpDouble(anchor.top, top, t)!;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                child: _Backdrop(progress: t),
              ),
            ),
            if (preview != null)
              Positioned(
                left: anchor.left,
                top: previewTop,
                width: anchor.width,
                height: previewHeight,
                child: IgnorePointer(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: anchor.height,
                      maxHeight: anchor.height,
                      child: preview,
                    ),
                  ),
                ),
              ),
            if (reactions != null)
              Positioned(
                top: previewTop - _gap - _reactionsHeight,
                left: reactionsLeft,
                right: reactionsRight,
                height: _reactionsHeight,
                child: _popIn(
                  t,
                  alignEnd ? Alignment.bottomRight : Alignment.bottomLeft,
                  Align(
                    alignment: alignEnd
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: reactions!,
                  ),
                ),
              ),
            Positioned(
              top: previewTop + previewHeight + _gap,
              left: menuLeft,
              width: _menuWidth,
              child: _popIn(
                t,
                alignEnd ? Alignment.topRight : Alignment.topLeft,
                _MenuPanel(
                  items: items,
                  itemHeight: _itemHeight,
                  onSelected: (item) {
                    close();
                    item.onTap();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _popIn(double t, Alignment origin, Widget child) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.6 + 0.4 * t,
        alignment: origin,
        child: child,
      ),
    );
  }
}

/// Затемнение (и на iOS — размытие) всего экрана под меню.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final dim = ColoredBox(
      color: CupertinoColors.black.withValues(
        alpha: (AppGlass.blurSupported ? 0.18 : 0.4) * progress,
      ),
    );
    if (!AppGlass.blurSupported) return dim;
    final sigma = 14 * progress;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: dim,
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.items,
    required this.itemHeight,
    required this.onSelected,
  });

  final List<MessageMenuItem> items;
  final double itemHeight;
  final ValueChanged<MessageMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final separator = CupertinoColors.separator.resolveFrom(context);
    return AppGlass(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(height: 0.5, color: separator),
            _MenuRow(
              item: items[i],
              height: itemHeight - (i > 0 ? 0.5 : 0),
              onTap: () => onSelected(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.item,
    required this.height,
    required this.onTap,
  });

  final MessageMenuItem item;
  final double height;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.item.isDestructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        height: widget.height,
        color: _pressed
            ? CupertinoColors.systemFill.resolveFrom(context)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: color),
              ),
            ),
            const SizedBox(width: 12),
            Icon(widget.item.icon, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}
