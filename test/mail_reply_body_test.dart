import 'package:connect/models/mail/mail_message.dart';
import 'package:connect/utils/mail_reply_body.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

MailMessage message({String? body, String? bodyHtml, String? cc}) =>
    MailMessage(
      id: 1,
      subject: 'Отчёт',
      from: 'Иван <ivan@x.ru>',
      to: 'me@x.ru',
      cc: cc,
      body: body,
      bodyHtml: bodyHtml,
      date: DateTime(2026, 11, 5, 10, 30),
    );

void main() {
  setUpAll(() => initializeDateFormatting('ru_RU'));

  test('new text comes first, then the separator and the quote', () {
    final body = MailReplyBody.build(
      userText: 'Спасибо\nПринято\n',
      original: message(body: 'Отчёт готов', cc: 'anna@x.ru'),
    );

    expect(
      body.text,
      'Спасибо\nПринято\n\n'
      '-----Исходное сообщение-----\n'
      'От: Иван <ivan@x.ru>\n'
      'Дата: 5 ноября 2026, 10:30\n'
      'Кому: me@x.ru\n'
      'Копия: anna@x.ru\n'
      'Тема: Отчёт\n\n'
      'Отчёт готов',
    );
    final html = body.html!;
    expect(html, startsWith('<div>Спасибо<br>Принято</div><hr'));
    expect(html, contains('Иван &lt;ivan@x.ru&gt;'));
    expect(html.indexOf('<hr'), lessThan(html.indexOf('<blockquote')));
    expect(html, contains('>Отчёт готов</blockquote>'));
  });

  test('user text and plain quote are escaped', () {
    final html = MailReplyBody.build(
      userText: '<b>жирный</b>',
      original: message(body: 'a < b\nвторая строка'),
    ).html!;

    expect(html, contains('&lt;b&gt;жирный&lt;'));
    expect(html, contains('a &lt; b<br>вторая строка'));
  });

  test('html quote keeps formatting without document-level markup', () {
    final html = MailReplyBody.build(
      userText: 'Ок',
      original: message(
        bodyHtml:
            '<html><head><style>p{color:red}</style></head><body>'
            '<p style="color:blue">Текст</p>'
            '<script>alert(1)</script>'
            '<img src="CID:image001.png@01"><img src="https://x.ru/a.png">'
            '</body></html>',
      ),
    ).html!;

    expect(html, contains('<p style="color:blue">Текст</p>'));
    expect(html, contains('https://x.ru/a.png'));
    expect(html, isNot(contains('p{color:red}')));
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('image001')));
    expect(html, isNot(contains('<html')));
  });

  test('without an original body the reply stays plain text', () {
    final body = MailReplyBody.build(userText: ' Ок ', original: message());

    expect(body.text, 'Ок');
    expect(body.html, isNull);
  });
}
