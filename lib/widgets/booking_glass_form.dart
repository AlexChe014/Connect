import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import 'app_glass.dart';
import 'app_icon_badge.dart';
import 'app_title_bar.dart';

/// Общие детали форм раздела «Календарь» (бронь, встреча, видеовстреча)
/// в стиле Liquid Glass: прозрачная шапка над цветным пятном, поля на
/// стеклянных карточках.

/// Экран-форма: прозрачная шапка с кнопкой «назад» и основным действием,
/// под ней прокручиваемый список [children].
class BookingGlassScaffold extends StatelessWidget {
  const BookingGlassScaffold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.canPop = true,
    this.controller,
    this.bottomBar,
    this.bottomBarHeight = 0,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  /// `false` — пока идёт сохранение, «назад» неактивна.
  final bool canPop;

  final ScrollController? controller;

  /// Плавающая панель внизу экрана (над клавиатурой) — например,
  /// форматирование текста; [bottomBarHeight] — место под неё в конце
  /// списка, чтобы последнее поле не пряталось под стекло.
  final Widget? bottomBar;
  final double bottomBarHeight;

  @override
  Widget build(BuildContext context) {
    final groupedBg = AppColors.groupedBackground.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: groupedBg,
        navigationBar: AppTitleBar(
          title: Text(title),
          blur: blur,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            // maybePop, а не pop: экран может перехватить выход через PopScope
            // (письмо с несохранённым текстом спрашивает подтверждение).
            onPressed: canPop ? () => Navigator.maybePop(context) : null,
            child: Icon(
              CupertinoIcons.back,
              size: AppTitleBar.iconSize,
              color: label,
            ),
          ),
          trailing: trailing,
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
              const AppGlassGlow(height: 360),
              Builder(
                // Свой context — под скаффолдом, где в MediaQuery уже учтена
                // высота полупрозрачной шапки.
                builder: (context) => ListView(
                  controller: controller,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 12,
                    bottom: bottomBar == null
                        ? MediaQuery.paddingOf(context).bottom + 32
                        : bottomBarHeight + 16,
                  ),
                  children: children,
                ),
              ),
              if (bottomBar != null)
                Positioned(left: 0, right: 0, bottom: 0, child: bottomBar!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Основное действие формы в шапке — синяя капсула: единственный цветной
/// элемент шапки, сразу видно, чем закончить.
class BookingNavAction extends StatelessWidget {
  const BookingNavAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: CupertinoActivityIndicator(),
      );
    }
    final enabled = onPressed != null;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      minimumSize: Size.zero,
      color: enabled
          ? AppColors.primary
          : CupertinoColors.systemGrey4.resolveFrom(context),
      disabledColor: CupertinoColors.systemGrey4.resolveFrom(context),
      borderRadius: BorderRadius.circular(18),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: enabled
              ? CupertinoColors.white
              : CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

/// Тема и описание крупными полями во всю ширину — как название события
/// в «Календаре» iOS, вместо узкого поля справа от подписи.
class BookingTitleCard extends StatelessWidget {
  const BookingTitleCard({
    super.key,
    required this.themeController,
    required this.themePlaceholder,
    this.descriptionController,
    this.onThemeChanged,
    this.errorText,
    this.autofocus = false,
  });

  final TextEditingController themeController;
  final String themePlaceholder;
  final TextEditingController? descriptionController;
  final ValueChanged<String>? onThemeChanged;
  final String? errorText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final descriptionController = this.descriptionController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppGlass(
            borderRadius: BorderRadius.circular(22),
            shadows: AppGlass.controlShadow,
            child: Column(
              children: [
                CupertinoTextField(
                  controller: themeController,
                  placeholder: themePlaceholder,
                  autofocus: autofocus,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.text,
                  textInputAction: descriptionController == null
                      ? TextInputAction.done
                      : TextInputAction.next,
                  decoration: const BoxDecoration(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                  onChanged: onThemeChanged,
                ),
                if (descriptionController != null) ...[
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  CupertinoTextField(
                    controller: descriptionController,
                    placeholder: 'Описание (необязательно)',
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 6,
                    decoration: const BoxDecoration(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    style: TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (errorText != null) BookingFootnote(errorText!, isError: true),
      ],
    );
  }
}

/// Пояснение под стеклянной секцией.
class BookingFootnote extends StatelessWidget {
  const BookingFootnote(this.text, {super.key, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.3,
          color: isError
              ? CupertinoColors.systemRed.resolveFrom(context)
              : CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

/// Строка выбора значения (день, время, офис…): значок, подпись,
/// текущее значение справа. Без [onTap] — только для чтения.
class BookingPickerRow extends StatelessWidget {
  const BookingPickerRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.onTap,
    this.valueMaxWidth = 170,
    this.fontSize = 15,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final double valueMaxWidth;

  /// 15, а не системные 17: строки форм — справка вокруг темы,
  /// крупный кегль делал карточки тяжёлыми.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: AppIconBadge(icon: icon, color: color),
      title: Text(label, style: TextStyle(fontSize: fontSize)),
      additionalInfo: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: valueMaxWidth),
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
      trailing: onTap == null ? null : const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}

/// Строка-переключатель со значком.
class BookingSwitchRow extends StatelessWidget {
  const BookingSwitchRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: AppIconBadge(icon: icon, color: color),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      // Системный тумблер выше строки с кеглем 15 и смотрится громоздко —
      // слегка уменьшаем, как в компактных списках iOS.
      trailing: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: CupertinoSwitch(
          value: value,
          activeTrackColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// Однострочное поле ввода внутри стеклянной секции: значок слева,
/// текст во всю оставшуюся ширину.
class BookingFieldRow extends StatelessWidget {
  const BookingFieldRow({
    super.key,
    required this.icon,
    required this.color,
    required this.controller,
    required this.placeholder,
    this.keyboardType,
  });

  final IconData icon;
  final Color color;
  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
      child: Row(
        children: [
          AppIconBadge(icon: icon, color: color),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              keyboardType: keyboardType,
              autocorrect: false,
              decoration: const BoxDecoration(),
              padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
              clearButtonMode: OverlayVisibilityMode.editing,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка объекта бронирования на стекле.
class BookingGlassCard extends StatelessWidget {
  const BookingGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
