import 'dart:async';

import 'package:connect/config/notification_topics.dart';
import 'package:connect/models/notification_item.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/notification_unread_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationItem.fromJson', () {
    Map<String, dynamic> json({Object? readAt}) => {
      'id': 123,
      'user_id': 42,
      'type': 'booking_created',
      'module': 'calendar',
      'title': 'Новое бронирование',
      'message': 'Иван Иванов пригласил Вас на встречу',
      'data': {'id': 7, 'booking_id': 7, 'room': null, 'link': 'x'},
      'read_at': readAt,
      'created_at': '2026-10-21T14:00:00.000000Z',
    };

    test('прочитанность берётся из read_at', () {
      expect(NotificationItem.fromJson(json()).isRead, isFalse);
      expect(
        NotificationItem.fromJson(
          json(readAt: '2026-10-21T14:00:00.000000Z'),
        ).isRead,
        isTrue,
      );
    });

    test('message попадает в текст, data — как карта', () {
      final item = NotificationItem.fromJson(json());
      expect(item.body, 'Иван Иванов пригласил Вас на встречу');
      expect(item.module, 'calendar');
      expect(item.data['booking_id'], 7);
    });

    test('данные для перехода: тип уведомления важнее поля в data', () {
      final item = NotificationItem.fromJson({
        ...json(),
        'data': {'type': 'other', 'booking_id': 7},
      });
      final nav = item.toNavigationData();
      expect(nav['type'], 'booking_created');
      expect(nav['module'], 'calendar');
      expect(AppNavigationService.resolveBookingId(nav), '7');
    });

    test('id новости из data', () {
      final item = NotificationItem.fromJson({
        'id': 1,
        'type': 'news_created',
        'module': 'feed',
        'title': 't',
        'message': 'm',
        'data': {'id': 55},
        'read_at': null,
      });
      expect(
        AppNavigationService.resolveDataField(item.toNavigationData(), [
          'news_id',
          'id',
        ]),
        '55',
      );
    });
  });

  group('NotificationTopics', () {
    test('бонусные типы', () {
      expect(
        NotificationTopics.isBonusType('bonus_program_point_transfer_received'),
        isTrue,
      );
      expect(NotificationTopics.isBonusType('news_created'), isFalse);
      expect(
        NotificationTopics.byType('bonus_program_shop_request'),
        NotificationTopics.bonusProgram,
      );
    });

    test('иконки новых типов', () {
      expect(NotificationTopics.byType('new_emails'), NotificationTopics.mailNew);
      expect(
        NotificationTopics.byType('document_changes'),
        NotificationTopics.documentApproval,
      );
      expect(NotificationTopics.byType('survey_invite'), NotificationTopics.survey);
    });
  });

  group('NotificationUnreadService', () {
    test('обновляет счётчик и уменьшает его при прочтении', () async {
      final service = NotificationUnreadService(load: () async => 5);
      await service.refresh();
      expect(service.unreadCount, 5);
      service.markRead(2);
      expect(service.unreadCount, 3);
      service.markRead(10);
      expect(service.unreadCount, 0);
    });

    test('ответ, начатый до отметки, не возвращает старое число', () async {
      final completer = Completer<int>();
      final service = NotificationUnreadService(load: () => completer.future);
      final refresh = service.refresh();
      service.markAllRead();
      completer.complete(4);
      await refresh;
      expect(service.unreadCount, 0);
    });

    test('ошибка сети оставляет последнее значение', () async {
      var fail = false;
      final service = NotificationUnreadService(
        load: () async => fail ? throw Exception('offline') : 3,
      );
      await service.refresh();
      fail = true;
      await service.refresh();
      expect(service.unreadCount, 3);
    });
  });

  group('NotificationTopics.canonicalType', () {
    test('maps backend client types to stored types', () {
      expect(NotificationTopics.canonicalType('news'), 'news_created');
      expect(NotificationTopics.canonicalType('document'), 'new_documents');
      expect(NotificationTopics.canonicalType('email'), 'mail');
      expect(NotificationTopics.canonicalType('new_emails'), 'mail');
      expect(NotificationTopics.canonicalType('chat_message'), 'chat_message');
      expect(NotificationTopics.canonicalType(null), '');
    });

    test('byType resolves short names', () {
      expect(NotificationTopics.byType('news'), NotificationTopics.feedPost);
      expect(
        NotificationTopics.byType('document'),
        NotificationTopics.documentApproval,
      );
      expect(NotificationTopics.byType('email'), NotificationTopics.mailNew);
    });
  });
}
