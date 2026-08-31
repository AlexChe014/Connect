import '../../services/paginated.dart';

/// Тип достижения для ежемесячной формы (`AchievementTypeResource`).
class AchievementType {
  final int id;
  final String title;
  final int pointsCost;
  final bool isActive;

  const AchievementType({
    required this.id,
    required this.title,
    required this.pointsCost,
    required this.isActive,
  });

  factory AchievementType.fromJson(Map<String, dynamic> json) {
    return AchievementType(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      title: (json['title'] ?? '').toString(),
      pointsCost: ApiPaginatedEnvelope.parseInt(json['points_cost']) ?? 0,
      isActive: json['is_active'] == true,
    );
  }
}
