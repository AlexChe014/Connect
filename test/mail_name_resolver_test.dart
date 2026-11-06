import 'dart:async';

import 'package:connect/services/mail_name_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('finds the name of a bare address and notifies listeners', () async {
    final asked = <String>[];
    final resolver = MailNameResolver(
      lookup: (email) async {
        asked.add(email);
        return 'Иванова Анна';
      },
    );
    var notified = 0;
    resolver.addListener(() => notified++);

    expect(resolver.displayName('A.Ivanova@x.ru'), 'A.Ivanova@x.ru');
    expect(resolver.displayName('a.ivanova@x.ru'), 'a.ivanova@x.ru');
    await settle();

    expect(asked, ['a.ivanova@x.ru']);
    expect(notified, 1);
    expect(resolver.displayName('A.Ivanova@x.ru'), 'Иванова Анна');
    await settle();
    expect(asked, hasLength(1));
  });

  test('an address with a name is not looked up', () async {
    final resolver = MailNameResolver(
      lookup: (_) async => fail('lookup should not run'),
    );

    expect(resolver.displayName('Пётр <p@x.ru>'), 'Пётр');
    expect(resolver.displayName('Без адреса'), 'Без адреса');
    await settle();
  });

  test('an external address stays and is asked once', () async {
    var calls = 0;
    final resolver = MailNameResolver(
      lookup: (_) async {
        calls++;
        return null;
      },
    );

    resolver.displayName('news@tilda.ws');
    await settle();

    expect(resolver.displayName('news@tilda.ws'), 'news@tilda.ws');
    await settle();
    expect(calls, 1);
  });

  test('a failed lookup is not repeated right away', () async {
    var calls = 0;
    final resolver = MailNameResolver(
      lookup: (_) async {
        calls++;
        throw Exception('offline');
      },
    );

    resolver.displayName('a@x.ru');
    await settle();

    expect(resolver.displayName('a@x.ru'), 'a@x.ru');
    await settle();
    expect(calls, 1);
  });

  test('clear drops the answer of a request from the previous user', () async {
    final answer = Completer<String?>();
    final resolver = MailNameResolver(lookup: (_) => answer.future);

    resolver.displayName('a@x.ru');
    await settle();
    resolver.clear();
    answer.complete('Чужое имя');
    await settle();

    expect(resolver.displayName('a@x.ru'), 'a@x.ru');
  });

  test('runs at most four lookups at a time', () async {
    final answers = <Completer<String?>>[];
    final resolver = MailNameResolver(
      lookup: (_) {
        final answer = Completer<String?>();
        answers.add(answer);
        return answer.future;
      },
    );

    for (var i = 0; i < 6; i++) {
      resolver.displayName('u$i@x.ru');
    }
    await settle();
    expect(answers, hasLength(4));

    answers.first.complete(null);
    await settle();
    expect(answers, hasLength(5));
  });
}
