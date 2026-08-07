import 'package:connect/models/bookings/bookable_object.dart';
import 'package:connect/models/staff_user.dart';

import 'booking_json.dart';
import 'booking_recurring.dart';

/// Полная карточка брони (`GET /booking/get/{id}`).
class BookingDetail {
  final int id;
  final DateTime datetimeStart;
  final DateTime datetimeEnd;
  final String theme;
  final String? description;
  final bool isPrivate;
  final bool isPassed;
  final String? objectName;
  final BookableObject? object;
  final int? modelType;
  final int? modelId;
  final String? link;
  final List<int> userIds;
  final List<StaffUser> participants;
  final BookingRecurringInfo? recurring;
  final int? recurringParentId;

  const BookingDetail({
    required this.id,
    required this.datetimeStart,
    required this.datetimeEnd,
    required this.theme,
    this.description,
    required this.isPrivate,
    required this.isPassed,
    this.objectName,
    this.object,
    this.modelType,
    this.modelId,
    this.link,
    this.userIds = const [],
    this.participants = const [],
    this.recurring,
    this.recurringParentId,
  });

  bool get isRecurring => recurring != null && (recurring!.type ?? '').isNotEmpty;

  String get displayObjectName {
    final fromObject = object?.name.trim();
    if (fromObject != null && fromObject.isNotEmpty) return fromObject;
    final name = objectName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Объект бронирования';
  }

  factory BookingDetail.fromJson(Map<String, dynamic> json) {
    final usersRaw = json['users'];
    final userIds = <int>[];
    final participants = <StaffUser>[];

    if (usersRaw is List) {
      for (final item in usersRaw) {
        if (item is Map) {
          final map = item.cast<String, dynamic>();
          final user = StaffUser.fromJson(map);
          if (user.id.isNotEmpty) participants.add(user);
          final id = BookingJson.parseInt(map['id'] ?? map['user_id']) ?? user.idAsInt;
          if (id != null) userIds.add(id);
        } else {
          final id = BookingJson.parseInt(item);
          if (id != null) userIds.add(id);
        }
      }
    }

    BookableObject? object;
    final objectRaw = json['object'];
    if (objectRaw is Map) {
      object = BookableObject.fromJson(objectRaw.cast<String, dynamic>());
    }

    return BookingDetail(
      id: BookingJson.parseInt(json['id']) ?? 0,
      datetimeStart: BookingJson.parseDateTime(json['datetime_start']),
      datetimeEnd: BookingJson.parseDateTime(json['datetime_end']),
      theme: (json['theme'] as String?)?.trim().isNotEmpty == true
          ? (json['theme'] as String).trim()
          : 'Без темы',
      description: json['description'] as String?,
      isPrivate: BookingJson.parseInt(json['is_private']) == 1,
      isPassed: json['is_passed'] == true,
      objectName: BookingJson.objectNameFromJson(json) ?? object?.name,
      object: object,
      modelType: BookingJson.parseInt(json['model_type']),
      modelId: BookingJson.parseInt(json['model_id']),
      link: (json['link'] as String?)?.trim(),
      userIds: userIds,
      participants: participants,
      recurring: BookingRecurringInfo.fromJson(json['recurring']),
      recurringParentId: BookingJson.parseInt(json['recurring_parent_id'] ?? json['parent_id']),
    );
  }
}
