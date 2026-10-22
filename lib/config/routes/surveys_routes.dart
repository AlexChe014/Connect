import '../api_config.dart';

/// URL-ы публичной части модуля опросов: приглашения сотрудника
/// (`/surveys/my/*`, под `auth:sanctum`) и форма прохождения по токену
/// получателя (`/surveys/public/{token}/*`, без авторизации).
class SurveysRoutes {
  SurveysRoutes._();

  static const String _prefix = '/surveys';

  /// `GET /surveys/my` — приглашения текущего пользователя.
  static String get myUrl => '${ApiConfig.baseUrl}$_prefix/my';

  /// `POST /surveys/my/{recipient}/portal-open` — отметка «открыт в портале».
  static String portalOpenUrl(int recipientId) =>
      '${ApiConfig.baseUrl}$_prefix/my/$recipientId/portal-open';

  static String _public(String token) =>
      '${ApiConfig.baseUrl}$_prefix/public/${Uri.encodeComponent(token)}';

  /// `GET /surveys/public/{token}` — опрос, вопросы и состояние кампании.
  static String publicFormUrl(String token) => _public(token);

  /// `POST /surveys/public/{token}/start` — прохождение начато.
  static String publicStartUrl(String token) => '${_public(token)}/start';

  /// `POST /surveys/public/{token}/submit` — `{answers: [{question_id, value}]}`.
  static String publicSubmitUrl(String token) => '${_public(token)}/submit';
}
