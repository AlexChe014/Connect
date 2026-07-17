import 'package:connect/models/infrastructure/booking_object_type.dart';

class Space {
  final int id;
  final String name;
  final bool isActive;
  final List<BookingObjectType> types;

  const Space({
    required this.id,
    required this.name,
    required this.isActive,
    this.types = const [],
  });

  factory Space.fromJson(Map<String, dynamic> json) {
    final isActiveRaw = json['is_active'];
    final typesRaw = json['types'];
    return Space(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Этаж #${(json['id'] as num?)?.toInt() ?? 0}',
      isActive: isActiveRaw == true || isActiveRaw == 1 || isActiveRaw == '1',
      types: typesRaw is List
          ? typesRaw
              .whereType<Map>()
              .map((e) => BookingObjectType.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

