/// Утилиты для 30-минутных слотов бронирования.
class BookingTimeUtils {
  BookingTimeUtils._();

  static const int slotMinutes = 30;
  static const int slotsPerDay = 48;

  static List<DateTime> slotsForDate(DateTime date) {
    final base = DateTime(date.year, date.month, date.day);
    return List<DateTime>.generate(
      slotsPerDay,
      (i) => base.add(Duration(minutes: slotMinutes * i)),
    );
  }

  static int nearestSlotIndex(
    List<DateTime> slots,
    DateTime target, {
    required bool floorToPrevious,
  }) {
    if (slots.isEmpty) return 0;
    var bestIdx = 0;
    var bestDiff = (slots[0].difference(target).inMinutes).abs();
    for (var i = 1; i < slots.length; i++) {
      final diff = (slots[i].difference(target).inMinutes).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIdx = i;
      }
    }

    if (floorToPrevious) {
      while (bestIdx > 0 && slots[bestIdx].isAfter(target)) {
        bestIdx--;
      }
    } else {
      while (bestIdx < slots.length - 1 && slots[bestIdx].isBefore(target)) {
        bestIdx++;
      }
    }
    return bestIdx;
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Минимальный индекс слота начала: для сегодня — не раньше текущего времени.
  static int minStartIndex(List<DateTime> slots, DateTime date) {
    final now = DateTime.now();
    if (!isSameDay(date, now)) return 0;
    return nearestSlotIndex(slots, now, floorToPrevious: false);
  }

  static String formatHm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String formatDateShort(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  static DateTime slotAt(List<DateTime> slots, int index) {
    if (slots.isEmpty) return DateTime.now();
    return slots[index.clamp(0, slots.length - 1)];
  }

  /// `true`, если интервал валиден: начало не в прошлом, конец строго после начала.
  static bool isRangeValid(DateTime start, DateTime end) {
    final now = DateTime.now();
    if (start.isBefore(now)) return false;
    return end.isAfter(start);
  }
}
