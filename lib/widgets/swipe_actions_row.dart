import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../services/haptics_service.dart';

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
/// Пока какая-то строка открыта, тап по любой строке списка только закрывает
/// её, не открывая саму строку.
class SwipeGroupController extends ChangeNotifier {
  final Map<String, VoidCallback> _closers = {};
  String? _openId;

  bool get hasOpen => _openId != null;

  void _register(String id, VoidCallback closer) => _closers[id] = closer;

  void _unregister(String id) {
    _closers.remove(id);
    if (_openId == id) _setOpenId(null);
  }

  void _setOpenId(String? id) {
    if (_openId == id) return;
    _openId = id;
    notifyListeners();
  }

  void _notifyClosed(String id) {
    if (_openId == id) _setOpenId(null);
  }

  /// Закрывает открытую строку — например, перед переходом на другой экран.
  void closeAll() {
    final open = _openId;
    if (open != null) _closers[open]?.call();
  }

  void _notifyOpened(String id) {
    if (_openId == id) return;
    final previous = _openId;
    _setOpenId(id);
    if (previous != null) _closers[previous]?.call();
  }
}

/// Оборачивает [child] так, что свайп влево раскрывает [actions] справа —
/// аналог `flutter_slidable`, но без внешней зависимости, реализован через
/// [AnimationController] + [Transform.translate]. Кнопки — скруглённые
/// «таблетки», как выбранная вкладка в нижнем таббаре; открытая строка
/// закрывается, как только список начинают прокручивать.
class SwipeActionsRow extends StatefulWidget {
  const SwipeActionsRow({
    super.key,
    required this.id,
    required this.child,
    required this.actions,
    required this.groupController,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final String id;
  final Widget child;
  final List<SwipeAction> actions;
  final SwipeGroupController groupController;
  final BorderRadius borderRadius;

  @override
  State<SwipeActionsRow> createState() => _SwipeActionsRowState();
}

class _SwipeActionsRowState extends State<SwipeActionsRow>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 76.0;

  late final AnimationController _controller;
  ValueListenable<bool>? _scrollingNotifier;

  double get _maxOffset => widget.actions.length * _actionWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onValueChanged);
    widget.groupController._register(widget.id, _close);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = Scrollable.maybeOf(context)?.position.isScrollingNotifier;
    if (notifier == _scrollingNotifier) return;
    _scrollingNotifier?.removeListener(_onScrollingChanged);
    _scrollingNotifier = notifier?..addListener(_onScrollingChanged);
  }

  void _onScrollingChanged() {
    if (_scrollingNotifier?.value ?? false) _close();
  }

  // Слушаем значение, а не статус: animateTo(0) завершается со статусом
  // completed, а не dismissed, и закрытие строки иначе не замечалось бы —
  // группа навсегда считала бы её открытой и глушила тапы по всем строкам.
  void _onValueChanged() {
    if (_controller.value == 0) {
      widget.groupController._notifyClosed(widget.id);
    }
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
    _scrollingNotifier?.removeListener(_onScrollingChanged);
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
    final double target;
    if (velocity < -300) {
      target = 1;
    } else if (velocity > 300) {
      target = 0;
    } else {
      target = _controller.value > 0.4 ? 1.0 : 0.0;
    }
    if (target == 1 && _controller.value < 1) AppHaptics.selection();
    _controller.animateTo(target, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              children: [
                // Кнопки рисуются только в открывшейся полосе справа, а не
                // под всей строкой: строке не нужен непрозрачный фон, и под
                // ней может просвечивать фон экрана.
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: _controller.value * _maxOffset,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerRight,
                      minWidth: _maxOffset,
                      maxWidth: _maxOffset,
                      child: Row(
                        children: [
                          for (final action in widget.actions)
                            GestureDetector(
                              onTap: () {
                                AppHaptics.light();
                                _close();
                                action.onTap();
                              },
                              child: SizedBox(
                                width: _actionWidth,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 6,
                                  ),
                                  child: DecoratedBox(
                                    decoration: ShapeDecoration(
                                      color: action.color,
                                      shape: RoundedSuperellipseBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              action.icon,
                                              color: CupertinoColors.white,
                                              size: 20,
                                            ),
                                            const SizedBox(height: 4),
                                            // Одна строка: длинная подпись
                                            // («Избранное») ужимается, а не
                                            // переносится по слогам.
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                action.label,
                                                maxLines: 1,
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: CupertinoColors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(-_controller.value * _maxOffset, 0),
                  child: ListenableBuilder(
                    listenable: widget.groupController,
                    builder: (context, child) {
                      // Тап по любой строке, пока какая-то открыта, только
                      // закрывает её — как в «Почте» и «Сообщениях».
                      final blocked =
                          _controller.value > 0 ||
                          widget.groupController.hasOpen;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: blocked ? widget.groupController.closeAll : null,
                        child: AbsorbPointer(absorbing: blocked, child: child),
                      );
                    },
                    child: widget.child,
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
