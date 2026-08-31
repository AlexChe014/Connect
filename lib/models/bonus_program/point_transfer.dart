import '../../services/paginated.dart';

/// Результат перевода баллов (`PointTransferResource`).
class PointTransfer {
  final int id;
  final int points;
  final String? comment;
  final String? recipientName;

  const PointTransfer({
    required this.id,
    required this.points,
    this.comment,
    this.recipientName,
  });

  factory PointTransfer.fromJson(Map<String, dynamic> json) {
    final rawRecipient = json['recipient'];
    String? recipientName;
    if (rawRecipient is Map) {
      final surname = (rawRecipient['surname'] ?? '').toString().trim();
      final name = (rawRecipient['name'] ?? '').toString().trim();
      final full = [surname, name].where((s) => s.isNotEmpty).join(' ');
      recipientName = full.isEmpty ? null : full;
    }

    return PointTransfer(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      points: ApiPaginatedEnvelope.parseInt(json['points']) ?? 0,
      comment: json['comment']?.toString(),
      recipientName: recipientName,
    );
  }
}
