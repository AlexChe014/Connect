import '../../services/paginated.dart';

/// Операция в журнале баллов (`PointOperationResource`).
class PointOperation {
  final int id;
  final int pointsDelta;
  final String? operationType;
  final String? operationTypeName;
  final String? balanceDirection;
  final String? reasonType;
  final String? description;
  final DateTime? completedAt;
  final DateTime? createdAt;

  const PointOperation({
    required this.id,
    required this.pointsDelta,
    this.operationType,
    this.operationTypeName,
    this.balanceDirection,
    this.reasonType,
    this.description,
    this.completedAt,
    this.createdAt,
  });

  /// `true`, если операция увеличивает баланс.
  bool get isCredit {
    if (balanceDirection != null) return balanceDirection != 'decrease';
    return pointsDelta >= 0;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  factory PointOperation.fromJson(Map<String, dynamic> json) {
    return PointOperation(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      pointsDelta: ApiPaginatedEnvelope.parseInt(json['points_delta']) ?? 0,
      operationType: json['operation_type']?.toString(),
      operationTypeName: json['operation_type_name']?.toString(),
      balanceDirection: json['balance_direction']?.toString(),
      reasonType: json['reason_type']?.toString(),
      description: json['description']?.toString(),
      completedAt: _parseDate(json['completed_at']),
      createdAt: _parseDate(json['created_at']),
    );
  }
}
