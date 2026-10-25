import 'dart:convert';

import 'package:connect/services/survey_draft_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SurveyDraft', () {
    test('survives json round trip', () {
      final draft = SurveyDraft(
        answers: {
          1: 'yes',
          2: {'a', 'b'},
          3: 9,
        },
        texts: {4: 'Комментарий'},
      );
      final restored = SurveyDraft.fromJson(
        jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
      );
      expect(restored.answers[1], 'yes');
      expect(restored.answers[2], ['a', 'b']);
      expect(restored.answers[3], 9);
      expect(restored.texts[4], 'Комментарий');
    });

    test('empty draft removes stored value', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SurveyDraftService.instance;
      await service.save('t1', const SurveyDraft(answers: {1: 5}));
      expect((await service.load('t1'))?.answers[1], 5);
      await service.save('t1', const SurveyDraft(texts: {1: ''}));
      expect(await service.load('t1'), isNull);
    });
  });
}
