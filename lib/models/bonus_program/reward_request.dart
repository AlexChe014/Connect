import '../../services/paginated.dart';

/// Заявка на получение приза из магазина или рулетки (`RewardRequestResource`).
class RewardRequest {
  final int id;
  final String type;
  final String status;
  final String? hrComment;
  final String? itemName;

  const RewardRequest({
    required this.id,
    required this.type,
    required this.status,
    this.hrComment,
    this.itemName,
  });

  bool get isPending => status == 'pending';

  bool get isApproved => status == 'approved';

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
    );
  }
}
