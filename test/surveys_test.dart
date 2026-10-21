import 'package:connect/config/notification_topics.dart';
import 'package:connect/models/surveys/survey_form.dart';
import 'package:connect/models/surveys/survey_invitation.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/survey_pending_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 21, 12);

  SurveyInvitation invitation(
    String status, {
    int id = 1,
    String? closesAt,
    String? completedAt,
  }) => SurveyInvitation.fromJson({
    'id': id,
    'token': 'tok-$id',
    'status': status,
    'campaign_id': 7,
    'completed_at': completedAt,
    'closes_at': closesAt,
    'survey': {'id': 3, 'type': 'nps', 'title': ' Опрос '},
  });

  group('SurveyInvitation', () {
    test('parses /surveys/my item', () {
      final i = invitation('sent');
      expect(i.id, 1);
      expect(i.token, 'tok-1');
      expect(i.surveyType, 'nps');
      expect(i.title, 'Опрос');
      expect(i.isPending(now), isTrue);
      expect(i.isNew(now), isTrue);
    });

    test('opened/started are pending but not new', () {
      expect(invitation('opened').isNew(now), isFalse);
      expect(invitation('started').isPending(now), isTrue);
    });

    test('finished, closed and completed are not pending', () {
      expect(invitation('completed').isPending(now), isFalse);
      expect(invitation('expired').isPending(now), isFalse);
      expect(invitation('bounced').isPending(now), isFalse);
      expect(
        invitation('sent', closesAt: '2026-10-20T10:00:00Z').isPending(now),
        isFalse,
      );
      expect(
        invitation('opened', completedAt: '2026-10-20 10:00:00').isPending(now),
        isFalse,
      );
    });
  });

  group('SurveyForm', () {
    test('parses public form payload', () {
      final form = SurveyForm.fromJson({
        'survey': {
          'id': 3,
          'type': 'nps',
          'title': 'Пульс',
          'is_anonymous': 1,
          'submit_button_text': '',
          'success_message': 'Спасибо!',
        },
        'questions': [
          {
            'id': 10,
            'type': 'single',
            'label': 'Офис?',
            'options': [
              'Москва',
              {'value': 'spb', 'label': 'Петербург'},
            ],
            'is_required': true,
          },
          {
            'id': 11,
            'type': 'nps',
            'label': 'Порекомендуете?',
            'settings': {'require_comment_for_detractors': true},
          },
          {
            'id': 12,
            'type': 'rating',
            'label': 'Оценка',
            'settings': {'max': 10},
          },
        ],
        'campaign': {'id': 7, 'closes_at': null, 'is_open': false},
        'already_completed': false,
        'is_preview': false,
      });
      expect(form.survey.isAnonymous, isTrue);
      expect(form.survey.submitButtonText, isNull);
      expect(form.survey.successMessage, 'Спасибо!');
      expect(form.isOpen, isFalse);
      expect(form.campaignId, 7);
      final single = form.questions[0];
      expect(single.isRequired, isTrue);
      expect(single.options.map((o) => o.value), ['Москва', 'spb']);
      expect(single.options.map((o) => o.label), ['Москва', 'Петербург']);
      expect(form.questions[1].requireCommentForDetractors, isTrue);
      expect(form.questions[2].ratingMax, 10);
    });

    test('rating defaults to 5 stars', () {
      expect(SurveyQuestion.fromJson({'id': 1, 'type': 'rating'}).ratingMax, 5);
    });
  });

  group('SurveyPendingService', () {
    test('counts pending invitations and updates locally', () async {
      final service = SurveyPendingService(
        load: () async => [
          invitation('sent', id: 1),
          invitation('started', id: 2),
          invitation('completed', id: 3),
        ],
        now: () => now,
      );
      await service.refresh();
      expect(service.pendingCount, 2);

      service.markOpened('tok-1');
      expect(service.invitations.first.isNew(now), isFalse);
      expect(service.pendingCount, 2);

      service.markCompleted('tok-2');
      expect(service.pendingCount, 1);

      service.reset();
      expect(service.pendingCount, 0);
      expect(service.isLoaded, isFalse);
    });
  });

  group('survey notifications', () {
    test('are recognised by type prefix or module', () {
      expect(NotificationTopics.isSurveyType('survey_invitation'), isTrue);
      expect(NotificationTopics.isSurveyType('survey_reminder'), isTrue);
      expect(NotificationTopics.isSurveyType('custom', 'surveys'), isTrue);
      expect(NotificationTopics.isSurveyType('news_created'), isFalse);
      expect(
        NotificationTopics.byType('survey_reminder'),
        NotificationTopics.survey,
      );
    });

    test('token is taken from data or from the survey link', () {
      expect(AppNavigationService.resolveSurveyToken({'token': 'abc'}), 'abc');
      expect(
        AppNavigationService.resolveSurveyToken({'data': '{"token":"nested"}'}),
        'nested',
      );
      expect(
        AppNavigationService.resolveSurveyToken({
          'link': 'https://portal.example/survey/xyz?utm=1',
        }),
        'xyz',
      );
      expect(AppNavigationService.resolveSurveyToken({}), isNull);
    });
  });
}
