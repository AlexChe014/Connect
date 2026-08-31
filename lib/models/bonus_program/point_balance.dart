import '../../services/paginated.dart';

/// Баланс баллов сотрудника (`UserPointsBalanceResource`).
class PointBalance {
  final int userId;
  final String surname;
  final String name;
  final String? position;
  final int points;
  final int pointsSpentTotal;

  const PointBalance({
    required this.userId,
    required this.surname,
    required this.name,
    this.position,
    required this.points,
    required this.pointsSpentTotal,
  });

  String get fullName =>
      [surname, name].where((s) => s.trim().isNotEmpty).join(' ');

  factory PointBalance.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : <String, dynamic>{};

    return PointBalance(
      userId: ApiPaginatedEnvelope.parseInt(user['id']) ?? 0,
      surname: (user['surname'] ?? '').toString(),
      name: (user['name'] ?? '').toString(),
      position: user['position']?.toString(),
      points: ApiPaginatedEnvelope.parseInt(json['points']) ?? 0,
      pointsSpentTotal:
          ApiPaginatedEnvelope.parseInt(json['points_spent_total']) ?? 0,
    );
  }
}
