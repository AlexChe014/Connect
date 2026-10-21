import 'survey_json.dart';

/// Статус получателя кампании: `queued → sent → delivered → opened →
/// started → completed`, плюс терминальные `bounced` и `expired`.
abstract final class SurveyRecipientStatus {
  static const queued = 'queued';
  static const sent = 'sent';
  static const delivered = 'delivered';
  static const opened = 'opened';
  static const started = 'started';
  static const completed = 'completed';
  static const bounced = 'bounced';
  static const expired = 'expired';

  /// Приглашение ещё не открывали — для маркера «Новый» в списке.
  static const unopened = {queued, sent, delivered};

  /// Пройти опрос по такому приглашению уже нельзя.
  static const finished = {completed, bounced, expired};
}

/// Элемент `GET /surveys/my` — приглашение текущего пользователя.
class SurveyInvitation {
  final int id;
  final String token;
  final String status;
  final int? campaignId;
  final DateTime? completedAt;
  final DateTime? closesAt;
  final int? surveyId;
  final String surveyType;
  final String title;

  const SurveyInvitation({
    required this.id,
    required this.token,
    required this.status,
    required this.title,
    this.surveyType = 'survey',
    this.campaignId,
    this.completedAt,
    this.closesAt,
    this.surveyId,
  });

  factory SurveyInvitation.fromJson(Map<String, dynamic> json) {
    final survey = SurveyJson.map(json['survey']) ?? const {};
    return SurveyInvitation(
      id: SurveyJson.parseInt(json['id']) ?? 0,
      token: (json['token'] ?? '').toString(),
      status: (json['status'] ?? '').toString().trim().toLowerCase(),
      campaignId: SurveyJson.parseInt(json['campaign_id']),
      completedAt: SurveyJson.parseDate(json['completed_at']),
      closesAt: SurveyJson.parseDate(json['closes_at']),
      surveyId: SurveyJson.parseInt(survey['id']),
      surveyType: (survey['type'] ?? 'survey').toString(),
      title: (survey['title'] ?? '').toString().trim(),
    );
  }

  SurveyInvitation copyWith({String? status, DateTime? completedAt}) =>
      SurveyInvitation(
        id: id,
        token: token,
        status: status ?? this.status,
        title: title,
        surveyType: surveyType,
        campaignId: campaignId,
        completedAt: completedAt ?? this.completedAt,
        closesAt: closesAt,
        surveyId: surveyId,
      );

  bool get isCompleted =>
      status == SurveyRecipientStatus.completed || completedAt != null;

  bool isClosed(DateTime now) {
    final closes = closesAt;
    return closes != null && !closes.isAfter(now);
  }

  /// Опрос ждёт ответа: не пройден, не истёк и кампания ещё принимает ответы.
  bool isPending(DateTime now) =>
      token.isNotEmpty &&
      !isCompleted &&
      !SurveyRecipientStatus.finished.contains(status) &&
      !isClosed(now);

  /// Новый — пользователь ещё ни разу не открывал приглашение.
  bool isNew(DateTime now) =>
      isPending(now) && SurveyRecipientStatus.unopened.contains(status);
}
