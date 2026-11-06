import 'dart:convert';

import 'package:connect/screens/bonus_requests_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

http.Response _page(List<String> names, {String? next}) => http.Response(
  jsonEncode({
    'success': true,
    'data': {
      'data': [
        for (final name in names)
          {
            'id': name.hashCode,
            'type': 'shop',
            'status': 'pending',
            'shop_item': {'name': name},
          },
      ],
      'current_page': next == null ? 2 : 1,
      'next_page_url': next,
    },
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('a page shorter than the screen still loads the next one', (
    tester,
  ) async {
    await initializeDateFormatting('ru_RU');
    tester.view.physicalSize = const Size(1206, 2622);
    addTearDown(tester.view.resetPhysicalSize);

    final client = MockClient((request) async {
      return request.url.queryParameters['page'] == '2'
          ? _page(['Кружка'])
          : _page(['Блокнот'], next: 'https://x.test/my?page=2');
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Material(child: BonusRequestsScreen())),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }, () => client);

    expect(find.text('Блокнот'), findsOneWidget);
    expect(find.text('Кружка'), findsOneWidget);
    expect(find.textContaining('HR свяжется с вами'), findsOneWidget);
  });

  testWidgets('an empty list has no pickup hint', (tester) async {
    final client = MockClient((_) async => _page([]));

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Material(child: BonusRequestsScreen())),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }, () => client);

    expect(find.text('Заявок пока нет'), findsOneWidget);
    expect(find.textContaining('HR свяжется с вами'), findsNothing);
  });
}
