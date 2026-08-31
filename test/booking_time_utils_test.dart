import 'package:connect/utils/booking_time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookingTimeUtils.slotsForDate', () {
    test('generates 48 half-hour slots starting at midnight', () {
      final slots = BookingTimeUtils.slotsForDate(DateTime(2026, 3, 7, 15, 30));

      expect(slots.length, BookingTimeUtils.slotsPerDay);
      expect(slots.first, DateTime(2026, 3, 7, 0, 0));
      expect(slots.last, DateTime(2026, 3, 7, 23, 30));
    });
  });

  group('BookingTimeUtils.isSameDay / startOfDay', () {
    test('isSameDay ignores time of day', () {
      expect(
        BookingTimeUtils.isSameDay(
          DateTime(2026, 3, 7, 1),
          DateTime(2026, 3, 7, 23, 59),
        ),
        isTrue,
      );
      expect(
        BookingTimeUtils.isSameDay(DateTime(2026, 3, 7), DateTime(2026, 3, 8)),
        isFalse,
      );
    });

    test('startOfDay zeroes out the time', () {
      expect(
        BookingTimeUtils.startOfDay(DateTime(2026, 3, 7, 14, 45, 30)),
        DateTime(2026, 3, 7),
      );
    });
  });

  group('BookingTimeUtils.formatHm / formatDateShort', () {
    test('formatHm pads single-digit hours and minutes', () {
      expect(BookingTimeUtils.formatHm(DateTime(2026, 1, 1, 9, 5)), '09:05');
      expect(BookingTimeUtils.formatHm(DateTime(2026, 1, 1, 23, 0)), '23:00');
    });

    test('formatDateShort pads day and month', () {
      expect(BookingTimeUtils.formatDateShort(DateTime(2026, 3, 7)), '07.03.2026');
    });
  });

  group('BookingTimeUtils.slotAt', () {
    test('returns the slot at the given index', () {
      final slots = BookingTimeUtils.slotsForDate(DateTime(2026, 3, 7));
      expect(BookingTimeUtils.slotAt(slots, 2), DateTime(2026, 3, 7, 1, 0));
    });

    test('clamps out-of-range indices instead of throwing', () {
      final slots = BookingTimeUtils.slotsForDate(DateTime(2026, 3, 7));
      expect(BookingTimeUtils.slotAt(slots, -5), slots.first);
      expect(BookingTimeUtils.slotAt(slots, 999), slots.last);
    });
  });

  group('BookingTimeUtils.nearestSlotIndex', () {
    final slots = BookingTimeUtils.slotsForDate(DateTime(2026, 3, 7));

    test('floorToPrevious never returns a slot after the target', () {
      final target = DateTime(2026, 3, 7, 10, 20);
      final idx = BookingTimeUtils.nearestSlotIndex(
        slots,
        target,
        floorToPrevious: true,
      );
      expect(slots[idx].isAfter(target), isFalse);
      expect(slots[idx], DateTime(2026, 3, 7, 10, 0));
    });

    test('!floorToPrevious never returns a slot before the target', () {
      final target = DateTime(2026, 3, 7, 10, 20);
      final idx = BookingTimeUtils.nearestSlotIndex(
        slots,
        target,
        floorToPrevious: false,
      );
      expect(slots[idx].isBefore(target), isFalse);
      expect(slots[idx], DateTime(2026, 3, 7, 10, 30));
    });

    test('empty slot list returns 0', () {
      expect(
        BookingTimeUtils.nearestSlotIndex(
          const [],
          DateTime(2026, 3, 7),
          floorToPrevious: true,
        ),
        0,
      );
    });
  });

  group('BookingTimeUtils.minStartIndex', () {
    test('a date other than today has no lower bound', () {
      final farFuture = DateTime.now().add(const Duration(days: 30));
      final slots = BookingTimeUtils.slotsForDate(farFuture);
      expect(BookingTimeUtils.minStartIndex(slots, farFuture), 0);
    });
  });

  group('BookingTimeUtils.isRangeValid', () {
    test('rejects a start time in the past', () {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      final end = start.add(const Duration(hours: 1));
      expect(BookingTimeUtils.isRangeValid(start, end), isFalse);
    });

    test('rejects an end time that does not come after start', () {
      final start = DateTime.now().add(const Duration(hours: 1));
      expect(BookingTimeUtils.isRangeValid(start, start), isFalse);
      expect(
        BookingTimeUtils.isRangeValid(start, start.subtract(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('accepts a future start with an end strictly after it', () {
      final start = DateTime.now().add(const Duration(hours: 1));
      final end = start.add(const Duration(minutes: 30));
      expect(BookingTimeUtils.isRangeValid(start, end), isTrue);
    });
  });
}
