import '../../services/paginated.dart';
import '../../utils/media_url_utils.dart';

/// Приз рулетки (`RoulettePrizeResource`).
class RoulettePrize {
  final int id;
  final String name;
  final double? dropPercent;
  final bool isActive;
  final String? photoUrl;

  const RoulettePrize({
    required this.id,
    required this.name,
    this.dropPercent,
    required this.isActive,
    this.photoUrl,
  });

  factory RoulettePrize.fromJson(Map<String, dynamic> json) {
    final rawPercent = json['drop_percent'];
    return RoulettePrize(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      name: (json['name'] ?? '').toString(),
      dropPercent: rawPercent == null
          ? null
          : double.tryParse(rawPercent.toString()),
      isActive: json['is_active'] == true,
      photoUrl: MediaUrlUtils.normalizeFirstOriginalUrl(json['photo']),
    );
  }
}
