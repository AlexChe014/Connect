import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../utils/booking_time_utils.dart';
import 'app_glass.dart';

/// Общие Cupertino-пикеры для форм бронирования: выбор одного варианта
/// из короткого списка, дата, получасовой слот времени.

/// Выбор одного варианта из списка (офис/этаж/тип объекта) через
/// нативный `CupertinoActionSheet` — прокручивается сам, если вариантов
/// много, поэтому не переполняется, в отличие от произвольной колонки
/// фиксированной высоты.
Future<T?> showBookingOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T current,
  required String Function(T) labelOf,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (sheetContext) {
      return CupertinoActionSheet(
        title: Text(title),
        actions: options.map((option) {
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, option),
            isDefaultAction: option == current,
            child: Text(labelOf(option)),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Отмена'),
        ),
      );
    },
  );
}

/// Выбор области действия для операции над повторяющейся бронью —
/// применить только к этой записи или ко всей серии. Возвращает `true`
/// (вся серия), `false` (только эта запись) или `null` (отмена).
Future<bool?> showRecurringScopeSheet({
  required BuildContext context,
  required String title,
  required String message,
  String thisLabel = 'Только эту',
  String allLabel = 'Всю серию',
  bool isDestructive = false,
}) {
  return showCupertinoModalPopup<bool>(
    context: context,
    builder: (sheetContext) {
      return CupertinoActionSheet(
        title: Text(title),
        message: Text(message),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, false),
            isDestructiveAction: isDestructive,
            child: Text(thisLabel),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, true),
            isDestructiveAction: isDestructive,
            child: Text(allLabel),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Отмена'),
        ),
      );
    },
  );
}

/// Выбор даты бронирования колесом `CupertinoDatePicker`.
Future<DateTime?> showBookingDateSheet({
  required BuildContext context,
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  var selected = initial.isBefore(firstDate) ? firstDate : initial;

  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (sheetContext) {
      return _PickerSheetScaffold(
        onDone: () => Navigator.pop(sheetContext, selected),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: selected,
          minimumDate: firstDate,
          maximumDate: lastDate,
          onDateTimeChanged: (d) => selected = d,
        ),
      );
    },
  );
}

/// Выбор получасового слота времени колесом `CupertinoPicker`.
/// Слоты младше [minIndex] недоступны для выбора и в колесо не попадают.
Future<int?> showBookingTimeSheet({
  required BuildContext context,
  required String title,
  required List<DateTime> slots,
  required int minIndex,
  required int currentIndex,
}) {
  final availableIndices = List<int>.generate(
    slots.length - minIndex,
    (i) => i + minIndex,
  );
  if (availableIndices.isEmpty) return Future.value(null);

  final clampedCurrent = currentIndex.clamp(minIndex, slots.length - 1);
  var selectedIndex = clampedCurrent;
  final initialItem = availableIndices.indexOf(clampedCurrent);
  final controller = FixedExtentScrollController(
    initialItem: initialItem < 0 ? 0 : initialItem,
  );

  return showCupertinoModalPopup<int>(
    context: context,
    builder: (sheetContext) {
      return _PickerSheetScaffold(
        title: title,
        onDone: () => Navigator.pop(sheetContext, selectedIndex),
        child: CupertinoPicker(
          scrollController: controller,
          itemExtent: 36,
          onSelectedItemChanged: (i) => selectedIndex = availableIndices[i],
          children: availableIndices
              .map(
                (i) => Center(child: Text(BookingTimeUtils.formatHm(slots[i]))),
              )
              .toList(),
        ),
      );
    },
  );
}

/// Плавающая стеклянная панель с колесом выбора — как системные
/// шторки iOS 26: отступ от краёв экрана и скругление со всех сторон.
class _PickerSheetScaffold extends StatelessWidget {
  const _PickerSheetScaffold({
    required this.child,
    required this.onDone,
    this.title,
  });

  final Widget child;
  final VoidCallback onDone;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: AppGlass(
          borderRadius: BorderRadius.circular(32),
          child: SizedBox(
            height: 280,
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                decoration: TextDecoration.none,
                color: label,
                fontSize: 17,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          onPressed: () => Navigator.pop(context),
                          child: Text('Отмена', style: TextStyle(color: label)),
                        ),
                        Expanded(
                          child: title == null
                              ? const SizedBox.shrink()
                              : Text(
                                  title!,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          onPressed: onDone,
                          child: const Text(
                            'Готово',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
