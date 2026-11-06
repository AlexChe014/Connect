import 'dart:convert';

import 'package:connect/models/disk/disk_share.dart';
import 'package:connect/repositories/bonus_program_repository.dart';
import 'package:connect/repositories/notifications_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _response(Object? data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('unread badge asks for the count without the list', () async {
    late Uri uri;
    final count = await http.runWithClient(
      () => NotificationsRepository.instance.getUnreadCount(),
      () => MockClient((request) async {
        uri = request.url;
        return _response({'count': 12});
      }),
    );

    expect(count, 12);
    expect(uri.queryParameters['with_items'], '0');
  });

  test('own reward requests are read with status, prize and comment', () async {
    late Uri uri;
    final page = await http.runWithClient(
      () => BonusProgramRepository.instance.getMyRewardRequests(),
      () => MockClient((request) async {
        uri = request.url;
        return _response({
          'data': [
            {
              'id': 1,
              'type': 'shop',
              'status': 'rejected',
              'hr_comment': 'Нет на складе',
              'created_at': '2026-11-01T10:00:00.000000Z',
              'shop_item': {'name': 'Кружка'},
              'roulette_prize': null,
            },
            {
              'id': 2,
              'type': 'roulette',
              'status': 'pending',
              'shop_item': null,
              'roulette_prize': null,
            },
          ],
          'current_page': 1,
          'next_page_url': 'https://x/my?page=2',
        });
      }),
    );

    expect(uri.path, endsWith('/bonus-program/reward-requests/my'));
    expect(page.nextPageUrl, isNotNull);

    final rejected = page.data.first;
    expect(rejected.itemName, 'Кружка');
    expect(rejected.statusLabel, 'Отклонена');
    expect(rejected.hrComment, 'Нет на складе');
    expect(rejected.createdAt, isNotNull);

    final pending = page.data.last;
    expect(pending.itemName, isNull);
    expect(pending.typeLabel, 'Приз колеса');
    expect(pending.statusLabel, 'На рассмотрении');
    expect(pending.createdAt, isNull);
  });

  group('DiskShare.recipientLabel', () {
    DiskShare share(Map<String, dynamic> json) =>
        DiskShare.fromJson({'id': 1, 'path': '/a', ...json});

    test('shows the display name, never the Nextcloud login', () {
      expect(
        share({
          'share_type': 0,
          'share_with': 'prod_user_7',
          'share_with_displayname': 'Петров Пётр',
        }).recipientLabel,
        'Петров Пётр',
      );
      expect(
        share({'share_type': 0, 'share_with': 'prod_user_7'}).recipientLabel,
        'Сотрудник',
      );
    });

    test('public link has its own label', () {
      expect(share({'share_type': 3}).recipientLabel, 'Публичная ссылка');
    });
  });
}
