import 'package:connect/models/bookings/booking_detail.dart';
import 'package:connect/models/bookings/update_booking_request.dart';
import 'package:connect/models/bookings/user_booking.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _fields(UpdateBookingRequest request) => {
  for (final entry in request.toFormEntries()) entry.key: entry.value,
};

void main() {
  group('UpdateBookingRequest.additionsPayload', () {
    test('untouched order is not sent, zero steppers do not count', () {
      expect(UpdateBookingRequest.additionsPayload({}, {}), isNull);
      expect(
        UpdateBookingRequest.additionsPayload({1: 2}, {1: 2, 3: 0}),
        isNull,
      );
    });

    test('changed order replaces the old one', () {
      expect(UpdateBookingRequest.additionsPayload({1: 2}, {1: 3, 2: 1}), {
        1: 3,
        2: 1,
      });
      expect(UpdateBookingRequest.additionsPayload({1: 2, 2: 1}, {2: 1}), {
        2: 1,
      });
    });

    test('removing everything sends zeros, an empty list cannot be sent', () {
      expect(UpdateBookingRequest.additionsPayload({1: 2, 2: 1}, {1: 0}), {
        1: 0,
        2: 0,
      });
    });
  });

  test('new fields reach the form only when set', () {
    expect(
      _fields(
        const UpdateBookingRequest(
          isPrivate: false,
          modelType: 1,
          modelId: 9,
          additions: {4: 0},
        ),
      ),
      {'is_private': '0', 'model_type': '1', 'model_id': '9', 'add[4]': '0'},
    );
    expect(_fields(const UpdateBookingRequest()), isEmpty);
  });

  test(
    'BookingDetail reads privacy, additions and space from the resource',
    () {
      final detail = BookingDetail.fromJson({
        'id': 1,
        'datetime_start': '2026-11-10T10:00:00+03:00',
        'datetime_end': '2026-11-10T11:00:00+03:00',
        'theme': 'Встреча',
        'is_private': true,
        'additions': [
          {'id': 2, 'name': 'Чай', 'count': 3},
          {'id': 4, 'name': 'Кофе', 'count': 0},
        ],
        'object': {
          'model': 1,
          'id': 5,
          'name': 'Переговорная',
          'space': {'id': 7},
        },
      });

      expect(detail.isPrivate, isTrue);
      expect(detail.additionQuantities, {2: 3});
      expect(detail.spaceId, 7);
      expect(detail.modelType, 1);
    },
  );

  group('место брони', () {
    Map<String, dynamic> json(int model, String name) => {
      'id': 1,
      'datetime_start': 1794000000,
      'datetime_end': 1794003600,
      'theme': 'Совещание',
      'object': {'model': model, 'id': 1, 'name': name},
    };

    test('служебный объект встречи местом не считается', () {
      final raw = json(6, 'Встреча');
      expect(BookingDetail.fromJson(raw).displayObjectName, isEmpty);
      expect(UserBooking.fromJson(raw).objectName, isNull);
    });

    test('настоящий объект показывается', () {
      final raw = json(1, 'Переговорная');
      expect(BookingDetail.fromJson(raw).displayObjectName, 'Переговорная');
      expect(UserBooking.fromJson(raw).objectName, 'Переговорная');
    });

    test('без объекта вместо места нет запасного текста', () {
      final raw = json(1, 'x')..remove('object');
      expect(BookingDetail.fromJson(raw).displayObjectName, isEmpty);
    });
  });
}
