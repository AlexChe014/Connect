/// Конфигурация ежемесячной формы достижений (`FormSubmissionController::config`).
class FormConfig {
  final bool periodOpen;
  final String title;
  final String description;
  final bool feedbackEnabled;
  final String feedbackDescription;

  const FormConfig({
    required this.periodOpen,
    required this.title,
    required this.description,
    required this.feedbackEnabled,
    required this.feedbackDescription,
  });

  factory FormConfig.fromJson(Map<String, dynamic> json) {
    return FormConfig(
      periodOpen: json['period_open'] == true,
      title: (json['period_title'] ?? json['title'] ?? 'Заявка на начисление баллов')
          .toString(),
      description: (json['period_description'] ?? json['description'] ?? '')
          .toString(),
      feedbackEnabled: json['feedback_enabled'] == true,
      feedbackDescription: (json['feedback_description'] ?? '').toString(),
    );
  }
}
