class MeetingRoom {
  final String id;
  final String name;
  final int capacity;
  final String? description;
  final List<String> amenities;

  const MeetingRoom({
    required this.id,
    required this.name,
    required this.capacity,
    this.description,
    this.amenities = const [],
  });

  factory MeetingRoom.fromJson(Map<String, dynamic> json) {
    final amenities = json['amenities'];
    return MeetingRoom(
      id: json['id'] as String,
      name: json['name'] as String,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      description: json['description'] as String?,
      amenities: amenities is List
          ? amenities.map((e) => e.toString()).toList()
          : const [],
    );
  }
}
