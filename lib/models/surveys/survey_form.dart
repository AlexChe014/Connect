import 'survey_json.dart';

/// Типы вопросов опроса.
abstract final class SurveyQuestionType {
  static const text = 'text';
  static const textarea = 'textarea';
  static const single = 'single';
  static const multi = 'multi';
  static const rating = 'rating';
  static const nps = 'nps';
}

/// Вариант ответа вопроса `single`/`multi`. Бэкенд может отдать варианты
/// строками или объектами `{value, label}` — в ответе уходит [value].
class SurveyOption {
  final Object value;
  final String label;

  const SurveyOption({required this.value, required this.label});

  static SurveyOption? fromJson(Object? raw) {
    if (raw is Map) {
      final label = SurveyJson.nonEmpty(
        raw['label'] ?? raw['text'] ?? raw['title'] ?? raw['name'],
      );
      final value = raw['value'] ?? raw['id'] ?? label;
      if (value == null) return null;
      return SurveyOption(value: value, label: label ?? value.toString());
    }
    final label = SurveyJson.nonEmpty(raw);
    if (label == null) return null;
    return SurveyOption(value: label, label: label);
  }
}

class SurveyQuestion {
  final int id;
  final String type;
  final String label;
  final String? description;
  final List<SurveyOption> options;
  final bool isRequired;
  final Map<String, dynamic> settings;

  const SurveyQuestion({
    required this.id,
    required this.type,
    required this.label,
    this.description,
    this.options = const [],
    this.isRequired = false,
    this.settings = const {},
  });

  factory SurveyQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return SurveyQuestion(
      id: SurveyJson.parseInt(json['id']) ?? 0,
      type: (json['type'] ?? SurveyQuestionType.text).toString().trim(),
      label: (json['label'] ?? '').toString().trim(),
      description: SurveyJson.nonEmpty(json['description']),
      options: rawOptions is List
          ? rawOptions
                .map(SurveyOption.fromJson)
                .whereType<SurveyOption>()
                .toList(growable: false)
          : const [],
      isRequired: SurveyJson.parseBool(json['is_required']),
      settings: SurveyJson.map(json['settings']) ?? const {},
    );
  }

  /// Верхняя граница шкалы `rating` (по умолчанию 5 звёзд).
  int get ratingMax {
    final raw = SurveyJson.parseInt(
      settings['max'] ?? settings['scale'] ?? settings['max_rating'],
    );
    if (raw == null || raw < 2) return 5;
    return raw > 10 ? 10 : raw;
  }

  /// NPS 0–6 — детрактор: при этой настройке комментарий обязателен.
  bool get requireCommentForDetractors =>
      SurveyJson.parseBool(settings['require_comment_for_detractors']);

  static bool isDetractorScore(int score) => score <= 6;
}

class SurveyInfo {
  final int id;
  final String type;
  final String title;
  final String? description;
  final bool isAnonymous;
  final String? submitButtonText;
  final String? successMessage;

  const SurveyInfo({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.isAnonymous = false,
    this.submitButtonText,
    this.successMessage,
  });

  factory SurveyInfo.fromJson(Map<String, dynamic> json) => SurveyInfo(
    id: SurveyJson.parseInt(json['id']) ?? 0,
    type: (json['type'] ?? 'survey').toString(),
    title: (json['title'] ?? '').toString().trim(),
    description: SurveyJson.nonEmpty(json['description']),
    isAnonymous: SurveyJson.parseBool(json['is_anonymous']),
    submitButtonText: SurveyJson.nonEmpty(json['submit_button_text']),
    successMessage: SurveyJson.nonEmpty(json['success_message']),
  );
}

/// `GET /surveys/public/{token}`.
class SurveyForm {
  final SurveyInfo survey;
  final List<SurveyQuestion> questions;
  final int? campaignId;
  final DateTime? closesAt;

  /// `campaign: null` бывает только у предпросмотра — тогда форма открыта.
  final bool isOpen;
  final bool alreadyCompleted;

  const SurveyForm({
    required this.survey,
    required this.questions,
    this.campaignId,
    this.closesAt,
    this.isOpen = true,
    this.alreadyCompleted = false,
  });

  factory SurveyForm.fromJson(Map<String, dynamic> json) {
    final campaign = SurveyJson.map(json['campaign']);
    final rawQuestions = json['questions'];
    return SurveyForm(
      survey: SurveyInfo.fromJson(SurveyJson.map(json['survey']) ?? const {}),
      questions: rawQuestions is List
          ? rawQuestions
                .map(SurveyJson.map)
                .whereType<Map<String, dynamic>>()
                .map(SurveyQuestion.fromJson)
                .toList(growable: false)
          : const [],
      campaignId: SurveyJson.parseInt(campaign?['id']),
      closesAt: SurveyJson.parseDate(campaign?['closes_at']),
      isOpen: SurveyJson.parseBool(campaign?['is_open'], defaultValue: true),
      alreadyCompleted: SurveyJson.parseBool(json['already_completed']),
    );
  }
}
