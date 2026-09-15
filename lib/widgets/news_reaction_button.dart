import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Набор быстрых реакций — совпадает с тем, что уже используется для
/// реакций на сообщения в чате (см. `_kQuickReactions` в
/// `chat_conversation_screen.dart`), чтобы в приложении был единый паттерн.
const List<String> kNewsQuickReactions = ['❤️', '👍', '👎', '😂', '‼️', '❓'];

/// Кнопка реакции на пост в стиле iOS: показывает текущую реакцию
/// пользователя (или нейтральное сердце, если реакции ещё нет) и счётчик.
///
/// На пост можно поставить только одну реакцию: выбор нового эмодзи
/// заменяет предыдущий, повторный выбор активного — снимает реакцию.
class NewsReactionButton extends StatefulWidget {
  const NewsReactionButton({
    super.key,
    required this.emoji,
    required this.count,
    required this.isLoading,
    required this.onSelect,
    this.onCountTap,
  });

  /// Текущая реакция пользователя, `null` — реакции нет.
  final String? emoji;
  final int count;
  final bool isLoading;

  /// Вызывается с выбранным эмодзи, либо с `null`, если реакцию нужно снять.
  final Future<void> Function(String? emoji) onSelect;
  final VoidCallback? onCountTap;

  @override
  State<NewsReactionButton> createState() => _NewsReactionButtonState();
}

class _NewsReactionButtonState extends State<NewsReactionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _select(String? emoji) async {
    if (widget.isLoading) return;
    HapticFeedback.lightImpact();
    unawaited(_controller.forward(from: 0));
    await widget.onSelect(emoji);
  }

  Future<void> _handleTap() async {
    if (widget.isLoading) return;
    if (widget.emoji == null) {
      await _select('❤️');
    } else {
      await _openPicker();
    }
  }

  Future<void> _openPicker() async {
    if (widget.isLoading) return;
    final active = widget.emoji;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        message: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: kNewsQuickReactions.map((emoji) {
              final isActive = active == emoji;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _select(isActive ? null : emoji);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? CupertinoColors.activeBlue.withValues(alpha: 0.15)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              );
            }).toList(),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasReaction = widget.emoji != null;
    final color = hasReaction
        ? CupertinoColors.systemRed
        : CupertinoColors.secondaryLabel.resolveFrom(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onLongPress: _openPicker,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
            child: widget.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CupertinoActivityIndicator(radius: 9),
                  )
                : ScaleTransition(
                    scale: _scale,
                    child: hasReaction
                        ? Text(
                            widget.emoji!,
                            style: const TextStyle(fontSize: 18),
                          )
                        : Icon(CupertinoIcons.heart, size: 20, color: color),
                  ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onCountTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 4, 4),
            child: Text(
              '${widget.count}',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
