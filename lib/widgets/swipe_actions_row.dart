import 'package:flutter/cupertino.dart';

/// Одно действие, раскрывающееся по свайпу (иконка + подпись на цветном
/// фоне), как "Mute"/"Delete" в почте или сообщениях iOS.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// Координирует свайпнутые строки одного списка: когда открывается новая,
/// ранее открытая закрывается сама — как в стандартных списках iOS.
class SwipeGroupController {
  final Map<String, VoidCallback> _closers = {};
  String? _openId;

  void _register(String id, VoidCallback closer) => _closers[id] = closer;

  void _unregister(String id) {
    _closers.remove(id);
    if (_openId == id) _openId = null;
  }

  void _notifyOpened(String id) {
    if (_openId == id) return;
    final previous = _openId;
    _openId = id;
    if (previous != null) _closers[previous]?.call();
  }
}

/// Оборачивает [child] так, что свайп влево раскрывает [actions] справа —
/// аналог `flutter_slidable`, но без внешней зависимости, реализован через
/// [AnimationController] + [Transform.translate].
class SwipeActionsRow extends StatefulWidget {
  const SwipeActionsRow({
    super.key,
    required this.id,
    required this.child,
    required this.actions,
    required this.groupController,
    this.borderRadius = 12,
  });

  final String id;
  final Widget child;
  final List<SwipeAction> actions;
  final SwipeGroupController groupController;
  final double borderRadius;

  @override
  State<SwipeActionsRow> createState() => _SwipeActionsRowState();
}

class _SwipeActionsRowState extends State<SwipeActionsRow>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 76.0;

  late final AnimationController _controller;

  double get _maxOffset => widget.actions.length * _actionWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    widget.groupController._register(widget.id, _close);
  }

  @override
  void didUpdateWidget(covariant SwipeActionsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.groupController != widget.groupController) {
      oldWidget.groupController._unregister(oldWidget.id);
      widget.groupController._register(widget.id, _close);
    }
  }

  @override
  void dispose() {
    widget.groupController._unregister(widget.id);
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (_controller.value == 0) return;
    _controller.animateTo(0, curve: Curves.easeOut);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_controller.value - details.delta.dx / _maxOffset).clamp(
      0.0,
      1.0,
    );
    _controller.value = next;
    if (next > 0) widget.groupController._notifyOpened(widget.id);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -300) {
      _controller.animateTo(1, curve: Curves.easeOut);
    } else if (velocity > 300) {
      _controller.animateTo(0, curve: Curves.easeOut);
    } else {
      _controller.animateTo(
        _controller.value > 0.4 ? 1.0 : 0.0,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: [
                      const Spacer(),
                      for (final action in widget.actions)
                        GestureDetector(
                          onTap: () {
                            _close();
                            action.onTap();
                          },
                          child: Container(
                            width: _actionWidth,
                            color: action.color,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  action.icon,
                                  color: CupertinoColors.white,
                                  size: 20,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  action.label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: Offset(-_controller.value * _maxOffset, 0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _controller.value > 0 ? _close : null,
                    child: AbsorbPointer(
                      absorbing: _controller.value > 0,
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
