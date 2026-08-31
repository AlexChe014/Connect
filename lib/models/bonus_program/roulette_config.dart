import '../../services/paginated.dart';

/// Настройки рулетки и лимит вращений текущего пользователя
/// (`RouletteController::config` — объединяет `getRouletteConfig` и `getUserSpinState`).
class RouletteConfig {
  final bool enabled;
  final String name;
  final int spinCost;
  final int? monthlySpinLimit;
  final int spinsUsedThisMonth;
  final int? spinsRemainingThisMonth;

  const RouletteConfig({
    required this.enabled,
    required this.name,
    required this.spinCost,
    this.monthlySpinLimit,
    required this.spinsUsedThisMonth,
    this.spinsRemainingThisMonth,
  });

  bool get canSpin =>
      enabled && (spinsRemainingThisMonth == null || spinsRemainingThisMonth! > 0);

  factory RouletteConfig.fromJson(Map<String, dynamic> json) {
    return RouletteConfig(
      enabled: json['enabled'] == true,
      name: (json['name'] ?? 'Розыгрыш').toString(),
      spinCost: ApiPaginatedEnvelope.parseInt(json['spin_cost']) ?? 0,
      monthlySpinLimit: ApiPaginatedEnvelope.parseInt(json['monthly_spin_limit']),
      spinsUsedThisMonth:
          ApiPaginatedEnvelope.parseInt(json['spins_used_this_month']) ?? 0,
      spinsRemainingThisMonth:
          ApiPaginatedEnvelope.parseInt(json['spins_remaining_this_month']),
    );
  }
}
