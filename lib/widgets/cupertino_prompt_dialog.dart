import 'package:flutter/cupertino.dart';

/// Кнопка нижней панели [CupertinoPromptDialog].
class CupertinoPromptDialogAction {
  const CupertinoPromptDialogAction({
    required this.label,
    required this.onPressed,
    this.isDefault = false,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isDefault;
  final bool isDestructive;
}

/// Диалог в стиле [CupertinoAlertDialog], но без фиксированной ширины в
/// 270pt — стандартный алерт тесноват для полей ввода кода. Строится на тех
/// же публичных примитивах ([CupertinoPopupSurface]), просто пошире.
class CupertinoPromptDialog extends StatelessWidget {
  const CupertinoPromptDialog({
    super.key,
    required this.title,
    this.message,
    required this.content,
    required this.actions,
    this.width = 320,
  });

  final String title;
  final String? message;
  final Widget content;
  final List<CupertinoPromptDialogAction> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final separatorColor = CupertinoColors.separator.resolveFrom(context);

    return Center(
      child: SizedBox(
        width: width,
        child: CupertinoPopupSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    content,
                  ],
                ),
              ),
              Container(height: 0.5, color: separatorColor),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) Container(width: 0.5, color: separatorColor),
                      Expanded(child: _ActionButton(action: actions[i])),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final CupertinoPromptDialogAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    final color = action.isDestructive
        ? CupertinoColors.systemRed
        : CupertinoColors.activeBlue;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: action.onPressed,
      child: Center(
        child: Text(
          action.label,
          style: TextStyle(
            fontSize: 17,
            color: enabled ? color : color.withValues(alpha: 0.4),
            fontWeight: action.isDefault ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
