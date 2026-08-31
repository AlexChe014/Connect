import '../../services/paginated.dart';

/// Лимиты перевода баллов, настроенные в админ-панели.
class PointTransferConfig {
  final bool enabled;
  final int minPoints;
  final int maxPoints;

  const PointTransferConfig({
    required this.enabled,
    required this.minPoints,
    required this.maxPoints,
  });

  factory PointTransferConfig.fromJson(Map<String, dynamic> json) {
    return PointTransferConfig(
      enabled: json['enabled'] == true,
      minPoints: ApiPaginatedEnvelope.parseInt(json['min_points']) ?? 10,
      maxPoints: ApiPaginatedEnvelope.parseInt(json['max_points']) ?? 0,
    );
  }
}
