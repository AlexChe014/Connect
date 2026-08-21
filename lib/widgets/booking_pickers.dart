import 'package:flutter/cupertino.dart';

import '../utils/booking_time_utils.dart';

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
    return Container(
      height: 292,
      color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                Expanded(
                  child: title == null
                      ? const SizedBox.shrink()
                      : Text(
                          title!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                ),
                CupertinoButton(onPressed: onDone, child: const Text('Готово')),
              ],
            ),
            Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
