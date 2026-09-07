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

  /// Лимиты из `GET /settings/get?module=bonus_program`.
  factory PointTransferConfig.fromSettings(Map<String, dynamic> json) {
    return PointTransferConfig(
      enabled: _parseBool(
        json['transfer_enabled'] ?? json['enabled'],
        defaultValue: true,
      ),
      minPoints:
          ApiPaginatedEnvelope.parseInt(json['transfer_min_points']) ?? 10,
      maxPoints: ApiPaginatedEnvelope.parseInt(json['transfer_max_points']) ?? 0,
    );
  }

  static bool _parseBool(Object? value, {required bool defaultValue}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value?.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return defaultValue;
  }
}
