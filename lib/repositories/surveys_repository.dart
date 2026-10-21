import '../config/routes/surveys_routes.dart';
import '../models/surveys/survey_form.dart';
import '../models/surveys/survey_invitation.dart';
import '../services/api_client.dart';
import '../services/api_envelope.dart';

/// Ответ на один вопрос: `value` — строка, вариант, список вариантов,
/// число или для NPS `{score, comment}`.
class SurveyAnswer {
  final int questionId;
  final Object value;

  const SurveyAnswer({required this.questionId, required this.value});

  Map<String, dynamic> toJson() => {'question_id': questionId, 'value': value};
}

/// Публичная часть модуля опросов: приглашения сотрудника и прохождение
/// формы по токену получателя.
class SurveysRepository {
  SurveysRepository._();
  static final SurveysRepository instance = SurveysRepository._();

  Future<List<SurveyInvitation>> getMyInvitations() async {
    final decoded = await ApiClient.instance.get(SurveysRoutes.myUrl);
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось получить список опросов',
    );
    // Список приходит массивом; на случай пагинации — из `data.data`.
    final raw = data is Map ? data['data'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => SurveyInvitation.fromJson(Map<String, dynamic>.from(e)))
        .where((i) => i.token.isNotEmpty)
        .toList(growable: false);
  }

  /// Отметка «опрос открыт на портале» — для воронки кампании.
  Future<void> markPortalOpen(int recipientId) async {
    await ApiClient.instance.post(SurveysRoutes.portalOpenUrl(recipientId));
  }

  Future<SurveyForm> getForm(String token) async {
    final decoded = await ApiClient.instance.get(
      SurveysRoutes.publicFormUrl(token),
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось загрузить опрос',
    );
    return SurveyForm.fromJson(data);
  }

  Future<void> start(String token) async {
    await ApiClient.instance.post(SurveysRoutes.publicStartUrl(token));
  }

  /// Возвращает `success_message` опроса, если бэкенд его прислал.
  Future<String?> submit(String token, List<SurveyAnswer> answers) async {
    final decoded = await ApiClient.instance.post(
      SurveysRoutes.publicSubmitUrl(token),
      body: {'answers': answers.map((a) => a.toJson()).toList()},
    );
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось отправить ответы',
    );
    final message = data is Map ? data['message']?.toString().trim() : null;
    return message == null || message.isEmpty ? null : message;
  }
}
