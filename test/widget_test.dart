import 'package:flutter_test/flutter_test.dart';

import 'package:connect/main.dart';

void main() {
  testWidgets('App loads and shows login when not authenticated', (WidgetTester tester) async {
    await tester.pumpWidget(const ConnectApp());

    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
