import '../../services/paginated.dart';
import '../../utils/media_url_utils.dart';

/// Товар магазина баллов (`ShopItemResource`).
class ShopItem {
  final int id;
  final String name;
  final String? description;
  final int price;
  final int? stock;
  final bool isActive;
  final String? photoUrl;

  const ShopItem({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.stock,
    required this.isActive,
    this.photoUrl,
  });

  /// `null` — запас не ограничен.
  bool get isOutOfStock => stock != null && stock! <= 0;

  factory ShopItem.fromJson(Map<String, dynamic> json) {
    return ShopItem(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      price: ApiPaginatedEnvelope.parseInt(json['price']) ?? 0,
      stock: ApiPaginatedEnvelope.parseInt(json['stock']),
      isActive: json['is_active'] == true,
      photoUrl: MediaUrlUtils.normalizeFirstUrl(json['photo']),
    );
  }
}
