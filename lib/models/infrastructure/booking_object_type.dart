class BookingObjectType {
  final int id;
  final int typeId;
  final int spaceId;
  final String name;

  const BookingObjectType({
    required this.id,
    required this.typeId,
    required this.spaceId,
    required this.name,
  });

  factory BookingObjectType.fromJson(Map<String, dynamic> json) {
    return BookingObjectType(
      id: (json['id'] as num?)?.toInt() ?? 0,
      typeId: (json['type_id'] as num?)?.toInt() ?? 0,
      spaceId: (json['space_id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Тип #${(json['type_id'] as num?)?.toInt() ?? 0}',
    );
  }
}

