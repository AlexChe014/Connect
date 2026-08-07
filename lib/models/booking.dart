class Booking {
  final String id;
  final String roomId;
  final String roomName;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? organizer;

  const Booking({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.organizer,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      roomName: json['roomName'] as String,
      title: json['title'] as String,
      startTime: DateTime.tryParse(json['startTime'] as String? ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(json['endTime'] as String? ?? '') ?? DateTime.now(),
      organizer: json['organizer'] as String?,
    );
  }
}
