import 'package:connect/utils/media_url_utils.dart';

import 'booking_json.dart';

class UserBooking {
  final int id;
  final DateTime datetimeStart;
  final DateTime datetimeEnd;
  final String theme;
  final String? description;
  final bool isPrivate;
  final bool isPassed;

  /// Display helpers (часто используются в UI)
  final String? objectName;
  final String? objectImageUrl;

  const UserBooking({
    required this.id,
    required this.datetimeStart,
    required this.datetimeEnd,
    required this.theme,
    this.description,
    required this.isPrivate,
    required this.isPassed,
    this.objectName,
    this.objectImageUrl,
  });

  factory UserBooking.fromJson(Map<String, dynamic> json) {
    final objectRaw = json['object'];
    String? objectImageUrl;
    if (objectRaw is Map) {
      objectImageUrl = MediaUrlUtils.normalizeFirstUrl(objectRaw['media']);
    }

    return UserBooking(
      id: BookingJson.parseInt(json['id']) ?? 0,
      datetimeStart: BookingJson.parseDateTime(json['datetime_start']),
      datetimeEnd: BookingJson.parseDateTime(json['datetime_end']),
      theme: (json['theme'] as String?)?.trim().isNotEmpty == true
          ? (json['theme'] as String).trim()
          : 'Без темы',
      description: json['description'] as String?,
      isPrivate: BookingJson.parseInt(json['is_private']) == 1,
      isPassed: json['is_passed'] == true,
      objectName: BookingJson.objectNameFromJson(json),
      objectImageUrl: objectImageUrl,
    );
  }
}

