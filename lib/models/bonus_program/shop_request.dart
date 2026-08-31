import '../../services/paginated.dart';

/// Заявка на получение товара из магазина (`ShopRequestResource`).
class ShopRequest {
  final int id;
  final String status;
  final String? itemName;

  const ShopRequest({required this.id, required this.status, this.itemName});

  bool get isPending => status == 'pending';

  bool get isApproved => status == 'approved';

  factory ShopRequest.fromJson(Map<String, dynamic> json) {
    final item = json['item'];
    return ShopRequest(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      status: (json['status'] ?? 'pending').toString(),
      itemName: item is Map ? item['name']?.toString() : null,
    );
  }
}
