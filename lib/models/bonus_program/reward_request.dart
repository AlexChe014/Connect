import '../../services/paginated.dart';

/// Заявка на получение приза из магазина или рулетки (`RewardRequestResource`).
class RewardRequest {
  final int id;
  final String type;
  final String status;
  final String? hrComment;
  final String? itemName;
  final DateTime? createdAt;

  const RewardRequest({
    required this.id,
    required this.type,
    required this.status,
    this.hrComment,
    this.itemName,
    this.createdAt,
  });

  bool get isPending => status == 'pending';

  bool get isApproved => status == 'approved';

  bool get isRejected => status == 'rejected';

  String get statusLabel => switch (status) {
    'approved' => 'Одобрена',
    'rejected' => 'Отклонена',
    _ => 'На рассмотрении',
  };

  String get typeLabel => type == 'roulette' ? 'Приз колеса' : 'Магазин';

  factory RewardRequest.fromJson(Map<String, dynamic> json) {
    String? itemName;
    final shopItem = json['shop_item'];
    if (shopItem is Map) itemName = shopItem['name']?.toString();
    final roulettePrize = json['roulette_prize'];
    if (itemName == null && roulettePrize is Map) {
      itemName = roulettePrize['name']?.toString();
    }

    return RewardRequest(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      type: (json['type'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      hrComment: json['hr_comment']?.toString(),
      itemName: itemName,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}
