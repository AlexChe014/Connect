/// Дополнение к брони (`/objects/addition/get`).
class BookingAddition {
  final int id;
  final String name;
  final String? description;

  const BookingAddition({
    required this.id,
    required this.name,
    this.description,
  });

  factory BookingAddition.fromJson(Map<String, dynamic> json) {
    return BookingAddition(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Дополнение #${(json['id'] as num?)?.toInt() ?? 0}',
      description: (json['description'] as String?)?.trim(),
    );
  }
}
