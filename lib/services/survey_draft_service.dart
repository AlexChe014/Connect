import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Незаконченные ответы опроса: длинный опрос можно закрыть и продолжить
/// позже с того же места. Ключ — токен получателя: он у каждого сотрудника
/// свой, поэтому черновики разных пользователей на одном телефоне не
/// пересекаются. Живёт только на устройстве и удаляется после отправки.
class SurveyDraft {
  /// Выбранные ответы по `question_id`: значение варианта (single),
  /// список значений (multi), число (rating/nps).
  final Map<int, Object> answers;

  /// Текст ответа (text/textarea) или комментарий к nps.
  final Map<int, String> texts;

  const SurveyDraft({this.answers = const {}, this.texts = const {}});

  bool get isEmpty => answers.isEmpty && texts.values.every((t) => t.isEmpty);

  Map<String, dynamic> toJson() => {
    'answers': {
      for (final e in answers.entries)
        '${e.key}': e.value is Set ? (e.value as Set).toList() : e.value,
    },
    'texts': {for (final e in texts.entries) '${e.key}': e.value},
  };

  factory SurveyDraft.fromJson(Map<String, dynamic> json) {
    final answers = <int, Object>{};
    final rawAnswers = json['answers'];
    if (rawAnswers is Map) {
      for (final e in rawAnswers.entries) {
        final id = int.tryParse(e.key.toString());
        if (id != null && e.value != null) answers[id] = e.value as Object;
      }
    }
    final texts = <int, String>{};
    final rawTexts = json['texts'];
    if (rawTexts is Map) {
      for (final e in rawTexts.entries) {
        final id = int.tryParse(e.key.toString());
        if (id != null && e.value is String) texts[id] = e.value as String;
      }
    }
    return SurveyDraft(answers: answers, texts: texts);
  }
}

class SurveyDraftService {
  SurveyDraftService._();
  static final SurveyDraftService instance = SurveyDraftService._();

  static String _key(String token) => 'survey_draft_$token';

  Future<SurveyDraft?> load(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(token));
    if (raw == null || raw.isEmpty) return null;
    try {
      return SurveyDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String token, SurveyDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (draft.isEmpty) {
      await prefs.remove(_key(token));
      return;
    }
    await prefs.setString(_key(token), jsonEncode(draft.toJson()));
  }

  Future<void> clear(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(token));
  }
}
