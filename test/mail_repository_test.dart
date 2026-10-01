import 'dart:convert';
import 'package:connect/repositories/mail_repository.dart';
import 'package:connect/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response response(Object? data, {bool success = true}) => http.Response(
  jsonEncode({'success': success, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final repository = MailRepository.instance;
  test('read, reply and forward accept boolean acknowledgements', () async {
    await http.runWithClient(() async {
      await repository.markRead(connectionId: 1, messageId: 2);
      await repository.markUnread(connectionId: 1, messageId: 2);
      await repository.replyMail(
        const ReplyMailRequest(messageId: 2, to: 'a@b.ru', subject: 'Re'),
      );
      await repository.forwardMail(
        const ForwardMailRequest(messageId: 2, to: 'a@b.ru', subject: 'Fwd'),
      );
    }, () => MockClient((_) async => response(true)));
  });

  test('failed read acknowledgement propagates an error', () async {
    await http.runWithClient(() async {
      await expectLater(
        repository.markRead(connectionId: 1, messageId: 2),
        throwsA(isA<ApiException>()),
      );
    }, () => MockClient((_) async => response(null, success: false)));
  });

  test(
    'wrapped folder tree retains drafts and distinct sent folders',
    () async {
      await http.runWithClient(
        () async {
          final folders = await repository.getMailboxes(1);
          expect(folders.map((f) => f.id), [1, 2, 3, 4]);
          expect(folders[1].depth, 1);
          expect(folders[1].isDrafts, isTrue);
        },
        () => MockClient(
          (_) async => response({
            'folders': [
              {
                'id': 1,
                'name': 'INBOX',
                'children': [
                  {'id': 2, 'name': 'INBOX.Drafts'},
                ],
              },
              {'id': 3, 'name': 'Sent'},
              {'id': 4, 'name': 'Отправленные'},
            ],
          }),
        ),
      );
    },
  );

  test(
    'hides inbox subfolders, archive and an empty duplicate sent folder',
    () async {
      await http.runWithClient(
        () async {
          final folders = await repository.getMailboxes(1);
          expect(folders.map((f) => f.id), [1, 2, 6, 8]);
        },
        () => MockClient(
          (_) async => response([
            {
              'id': 1,
              'name': 'INBOX',
              'children': [
                {'id': 2, 'name': 'INBOX.Drafts'},
                {
                  'id': 3,
                  'name': 'Проекты',
                  'children': [
                    {'id': 4, 'name': 'Клиенты'},
                  ],
                },
              ],
            },
            {'id': 5, 'name': 'INBOX.Рассылки'},
            {'id': 6, 'name': 'Sent', 'emails_count': 12},
            {'id': 7, 'name': 'Отправленные', 'emails_count': 0},
            {'id': 8, 'name': 'Trash'},
            {'id': 9, 'name': 'Архив'},
          ]),
        ),
      );
    },
  );

  test(
    'send selects intended SMTP connection before sending multipart',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          await repository.sendMail(
            const SendMailRequest(
              connectionId: 7,
              to: 'a@b.ru',
              subject: 'Subject',
              body: 'Message',
            ),
          );
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/smtp/set/7')) {
            return response({'id': 7});
          }
          expect(request.body, contains('Message'));
          return response(true);
        }),
      );
      expect(paths.length, 2);
      expect(paths.first, endsWith('/smtp/set/7'));
      expect(paths.last, endsWith('/smtp/send'));
    },
  );
}
