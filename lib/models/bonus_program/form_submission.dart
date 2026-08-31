import '../../services/paginated.dart';

/// Результат подачи ежемесячной формы достижений (`FormSubmissionResource`).
class FormSubmission {
  final int id;
  final int pointsCost;
  final String status;

  const FormSubmission({
    required this.id,
    required this.pointsCost,
    required this.status,
  });

  bool get isPending => status == 'pending';

  bool get isApproved => status == 'approved';

  factory FormSubmission.fromJson(Map<String, dynamic> json) {
    return FormSubmission(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      pointsCost: ApiPaginatedEnvelope.parseInt(json['points_cost']) ?? 0,
      status: (json['status'] ?? 'pending').toString(),
    );
  }
}
