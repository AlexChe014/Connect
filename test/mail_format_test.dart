import 'package:connect/models/mail/mail_message.dart';
import 'package:connect/utils/file_size_format.dart';
import 'package:connect/widgets/mail_body_content.dart';
import 'package:connect/widgets/mail_glass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain text with addresses in angle brackets stays plain text', () {
    final message = MailMessage.fromJson({
      'id': 1,
      'subject': 'Re: FW: Внедрение',
      'body_text':
          'Привет!\nВилка от 500 000\n\n'
          'From: Vladimir Zakharov <v.zakharov@x.ru>\n'
          'Sent: Monday <https://x.ru/a>',
      'body_html': null,
    });
    expect(message.htmlContent, isNull);
    expect(MailBodyContent.rendersHtml(message), isFalse);
    expect(message.plainBody, contains('Привет!\nВилка'));
    expect(message.plainBody, contains('<v.zakharov@x.ru>'));
  });

  test('real html is still detected', () {
    final message = MailMessage.fromJson({
      'id': 1,
      'subject': 'S',
      'body_html': '<div>Текст<br></div>',
    });
    expect(MailBodyContent.rendersHtml(message), isTrue);
  });

  test('all recipients and cc are kept, not only the first one', () {
    final message = MailMessage.fromJson({
      'id': 1,
      'subject': 'S',
      'from': {'name': 'Иван', 'email': 'ivan@x.ru'},
      'to': [
        {'name': 'Анна', 'email': 'anna@x.ru'},
        'petr@x.ru',
      ],
      'cc': [
        {'email': 'boss@x.ru'},
      ],
    });
    expect(message.to, 'Анна <anna@x.ru>, petr@x.ru');
    expect(message.cc, 'boss@x.ru');
  });

  test('address list split ignores commas inside quoted names', () {
    expect(
      MailMessage.splitAddresses('"Петров, Пётр" <p@x.ru>, a@x.ru; b@x.ru'),
      ['"Петров, Пётр" <p@x.ru>', 'a@x.ru', 'b@x.ru'],
    );
  });

  test('display name strips quotes and falls back to the address', () {
    expect(mailDisplayName('«1С-Битрикс» <info@1c.ru>'), '1С-Битрикс');
    expect(mailDisplayName('"Иван" <ivan@x.ru>'), 'Иван');
    expect(mailDisplayName('ivan@x.ru'), 'ivan@x.ru');
    expect(mailEmailOnly('Иван <ivan@x.ru>'), 'ivan@x.ru');
  });

  test('outlook cid images are matched to attachments by file name', () {
    const message = MailMessage(
      id: 1,
      subject: 'S',
      from: 'a@x.ru',
      bodyHtml: '<p>Hi</p><img src="cid:image001.png@01DC4277.5F9B7B30">',
      attachments: [
        // Сервер не отдаёт id вложений — у всех 0.
        MailAttachment(id: 0, filename: 'image001.png'),
        MailAttachment(id: 0, filename: 'report.pdf'),
      ],
    );
    final inline = MailBodyContent.inlineAttachments(message);
    expect(inline.map((a) => a.filename), ['image001.png']);
    expect(inline.contains(message.attachments[1]), isFalse);
  });

  test('file size is human readable', () {
    expect(formatFileSize(196), '196 Б');
    expect(formatFileSize(11366), '11,1 КБ');
    expect(formatFileSize(3 * 1024 * 1024), '3,0 МБ');
  });
}
