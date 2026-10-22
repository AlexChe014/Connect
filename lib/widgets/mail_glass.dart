import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import 'app_glass.dart';

/// Общие детали раздела «Почта» в стиле Liquid Glass.

/// Имя из адреса вида `"Иван Петров" <ivan@x.ru>` — для списка и шапки
/// письма; без имени остаётся сам адрес.
String mailDisplayName(String address) {
  final value = address.trim();
  if (value.isEmpty) return '';
  final bracket = value.indexOf('<');
  if (bracket > 0) {
    final name = value
        .substring(0, bracket)
        .trim()
        .replaceAll(RegExp(r'''^["'«“]+|["'»”]+$'''), '')
        .trim();
    if (name.isNotEmpty) return name;
  }
  return mailEmailOnly(value);
}

/// Только e-mail из `Имя <a@b.ru>`; строка без угловых скобок — как есть.
String mailEmailOnly(String address) {
  final match = RegExp(r'<([^>]+)>').firstMatch(address);
  return (match?.group(1) ?? address).trim();
}

/// Дата в списке писем, как в «Почте» iOS: время — сегодня, «Вчера»,
/// день недели — на этой неделе, дальше число; прошлые годы — с годом.
String formatMailListDate(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('HH:mm', 'ru_RU').format(local);
  if (diff == 1) return 'Вчера';
  if (diff > 1 && diff < 7) {
    final weekday = DateFormat('EEEE', 'ru_RU').format(local);
    return weekday[0].toUpperCase() + weekday.substring(1);
  }
  if (local.year == now.year) {
    return DateFormat('d MMM', 'ru_RU').format(local).replaceAll('.', '');
  }
  return DateFormat('dd.MM.yy', 'ru_RU').format(local);
}

/// Плавающая стеклянная панель внизу экрана (поиск и «написать» в списке,
/// действия с письмом). Отступает от нижнего края с учётом safe area.
class MailFloatingBar extends StatelessWidget {
  const MailFloatingBar({super.key, required this.child});

  /// Высота самой панели — экранам нужна, чтобы оставить под список
  /// место и последнее письмо не пряталось под стекло.
  static const double height = 50;

  /// Сколько места снизу занимает панель вместе с отступами.
  static double reservedHeight(BuildContext context) =>
      height +
      16 +
      MediaQuery.paddingOf(context).bottom.clamp(12, double.infinity);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Над клавиатурой safe area не нужна: CupertinoPageScaffold уже поднял
    // содержимое, а отступ под «полоску» дал бы зазор над клавишами.
    final bottom = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 8.0
        // Без верхней границы: во вкладке «Почта» снизу ещё и таббар.
        : MediaQuery.paddingOf(context).bottom.clamp(12.0, double.infinity);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
      child: SizedBox(height: height, child: child),
    );
  }
}

/// Круглая стеклянная кнопка с иконкой — «написать», действия в панели.
class MailGlassIconButton extends StatelessWidget {
  const MailGlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.size = MailFloatingBar.height,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: AppGlass(
        borderRadius: BorderRadius.circular(size / 2),
        shadows: AppGlass.controlShadow,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size(size, size),
          onPressed: onPressed,
          child: Icon(
            icon,
            size: 22,
            color: color ?? CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

/// Действие внутри стеклянной капсулы-тулбара: иконка над подписью.
class MailBarAction extends StatelessWidget {
  const MailBarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
        : isDestructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    return Expanded(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            // Пять действий в панели — длинная подпись («Ответить всем»)
            // ужимается, а не обрезается многоточием.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
