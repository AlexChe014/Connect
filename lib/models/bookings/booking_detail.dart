import 'package:connect/models/bookings/bookable_object.dart';
import 'package:connect/models/staff_user.dart';

import 'booking_json.dart';
import 'create_booking_request.dart';
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
  final bool isRecurrent;

  /// Кто создал бронь (`creator`) и организатор (`owner`; бэкенд подставляет
  /// создателя, если организатор не указан).
  final int? creatorId;
  final int? ownerId;

  /// Ответ участника на приглашение: `pending` / `accepted` / `rejected`.
  final Map<int, String> participantStatuses;

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
    this.isRecurrent = false,
    this.creatorId,
    this.ownerId,
    this.participantStatuses = const {},
  });

  /// Менять и удалять бронь может только создатель или организатор — так
  /// проверяет бэкенд при удалении. Если сервер не прислал ни того ни
  /// другого, не прячем кнопки: решит сервер.
  bool canManage(int? userId) {
    if (creatorId == null && ownerId == null) return true;
    return userId != null && (userId == creatorId || userId == ownerId);
  }

  /// Перенос по времени. `POST /booking/update` не проверяет занятость
  /// объекта (в отличие от создания), поэтому переговорную, место или
  /// парковку переносить нельзя — можно лишь встречу без объекта
  /// (`model_type` 6, как и при создании — без проверки занятости).
  bool get canReschedule =>
      modelType == null || modelType == CreateBookingRequest.meetingModelType;

  String? statusOf(int userId) => participantStatuses[userId];

  /// Приглашение, на которое пользователь ещё не ответил.
  bool isPendingFor(int? userId) =>
      userId != null && !canManage(userId) && statusOf(userId) == 'pending';

  /// Бэкенд не всегда отдаёт вложенный `recurring{type,...}` — реальный
  /// признак серии в ответе `GET /booking/get/{id}` это `is_recurrent`,
  /// поэтому проверяем оба варианта.
  bool get isRecurring =>
      isRecurrent || (recurring != null && (recurring!.type ?? '').isNotEmpty);

  String get displayObjectName {
    final fromObject = object?.name.trim();
    if (fromObject != null && fromObject.isNotEmpty) return fromObject;
    final name = objectName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Объект бронирования';
  }

  factory BookingDetail.fromJson(Map<String, dynamic> json) {
    final usersRaw = json['participants'] ?? json['users'];
    final userIds = <int>[];
    final participants = <StaffUser>[];
    final statuses = <int, String>{};

    if (usersRaw is List) {
      for (final item in usersRaw) {
        if (item is Map) {
          final map = item.cast<String, dynamic>();
          // API отдаёт участников либо плоским объектом пользователя, либо
          // pivot-записью вида {id, user_id, user: {...}} — разворачиваем
          // вложенный `user`, как для участников чата (см. chat_mapper.dart).
          final nestedUser = map['user'];
          final userJson = nestedUser is Map
              ? nestedUser.cast<String, dynamic>()
              : map;
          final resolvedId = BookingJson.parseInt(
            userJson['id'] ?? map['id'] ?? map['user_id'],
          );
          final effectiveJson = resolvedId != null && userJson['id'] == null
              ? {...userJson, 'id': resolvedId}
              : userJson;
          final user = StaffUser.fromJson(effectiveJson);
          if (user.id.isNotEmpty) participants.add(user);
          final id = resolvedId ?? user.idAsInt;
          if (id != null) userIds.add(id);
          final status = (map['status'] ?? map['pivot']?['status'])
              ?.toString()
              .trim();
          if (id != null && status != null && status.isNotEmpty) {
            statuses[id] = status;
          }
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
      // `BookingResource` кладёт тип и id объекта во вложенный `object`.
      modelType: BookingJson.parseInt(
        json['model_type'] ?? (objectRaw is Map ? objectRaw['model'] : null),
      ),
      modelId: BookingJson.parseInt(
        json['model_id'] ?? (objectRaw is Map ? objectRaw['id'] : null),
      ),
      link: (json['link'] as String?)?.trim(),
      userIds: userIds,
      participants: participants,
      recurring: BookingRecurringInfo.fromBookingJson(json),
      recurringParentId: BookingJson.parseInt(
        json['recurring_parent_id'] ?? json['parent_id'],
      ),
      isRecurrent: BookingJson.parseBool(json['is_recurrent']),
      creatorId:
          _userId(json['creator']) ?? BookingJson.parseInt(json['user_id']),
      ownerId: _userId(json['owner']) ?? BookingJson.parseInt(json['owner_id']),
      participantStatuses: statuses,
    );
  }

  static int? _userId(dynamic raw) {
    if (raw is Map) return BookingJson.parseInt(raw['id']);
    return BookingJson.parseInt(raw);
  }
}
