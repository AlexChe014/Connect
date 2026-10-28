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
        const ForwardMailRequest(
          connectionId: 1,
          messageId: 2,
          to: 'a@b.ru',
          subject: 'Fwd',
        ),
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

  /// Multipart-запросы, отправленные [action], с телами в latin1.
  Future<List<(String, String)>> captureRequests(
    Future<void> Function() action,
  ) async {
    final requests = <(String, String)>[];
    await http.runWithClient(
      action,
      () => MockClient((request) async {
        requests.add((request.url.path, latin1.decode(request.bodyBytes)));
        return response(true);
      }),
    );
    return requests;
  }

  test('send goes once to all recipients from the chosen mailbox', () async {
    final requests = await captureRequests(
      () => repository.sendMail(
        const SendMailRequest(
          connectionId: 7,
          to: 'a@b.ru, Иван <c@d.ru>',
          subject: 'Subject',
          body: 'Message',
          cc: ['e@f.ru'],
        ),
      ),
    );
    expect(requests, hasLength(1));
    final (path, body) = requests.single;
    expect(path, endsWith('/smtp/send'));
    expect(body, contains('name="to[0]"\r\n\r\na@b.ru'));
    expect(body, contains('name="to[1]"\r\n\r\nc@d.ru'));
    expect(body, contains('name="connection_id"\r\n\r\n7'));
    expect(body, contains('name="cc[0]"\r\n\r\ne@f.ru'));
  });

  test('reply sends edited recipients and subject to the reply route', () async {
    final requests = await captureRequests(
      () => repository.replyMail(
        const ReplyMailRequest(
          messageId: 2,
          to: 'a@b.ru, c@d.ru',
          subject: 'Re: Тема',
          body: 'Ответ',
        ),
      ),
    );
    final (path, body) = requests.single;
    expect(path, endsWith('/smtp/reply/2'));
    expect(body, contains('name="to[1]"\r\n\r\nc@d.ru'));
    expect(body, contains('name="subject"'));
    expect(body, contains('name="body_text"'));
  });

  test('forward uses the forward route with the user text only', () async {
    final requests = await captureRequests(
      () => repository.forwardMail(
        const ForwardMailRequest(
          connectionId: 7,
          messageId: 2,
          to: 'a@b.ru, c@d.ru',
          subject: 'Fwd',
          body: 'Посмотри',
          attachments: [
            MailUpload(filename: 'a.pdf', bytes: [1, 2, 3]),
          ],
        ),
      ),
    );
    expect(requests, hasLength(1));
    final (path, body) = requests.single;
    expect(path, endsWith('/smtp/forward/2'));
    expect(body, contains('name="message"'));
    expect(body, contains('name="to[1]"\r\n\r\nc@d.ru'));
    expect(body, contains('filename="a.pdf"'));
  });

  test('bulk mark read sends ids in `emails`', () async {
    Object? sent;
    await http.runWithClient(
      () => repository.markFewRead(connectionId: 1, ids: [5, 6]),
      () => MockClient((request) async {
        sent = jsonDecode(request.body);
        return response(true);
      }),
    );
    expect(sent, {
      'emails': [5, 6],
    });
  });

  test('failed IMAP action (data: false) is an error', () async {
    await http.runWithClient(() async {
      await expectLater(
        repository.deleteMessage(connectionId: 1, messageId: 2),
        throwsA(isA<ApiException>()),
      );
    }, () => MockClient((_) async => response(false)));
  });

  test('letters deleted from trash are not listed', () async {
    await http.runWithClient(
      () async {
        final page = await repository.getMessagesByFolder(
          connectionId: 1,
          folderId: 3,
        );
        expect(page.messages.map((m) => m.id), [1]);
        expect(page.messages.single.isFlagged, isTrue);
      },
      () => MockClient(
        (_) async => response({
          'data': [
            {'id': 1, 'subject': 'A', 'is_flagged': true},
            {'id': 2, 'subject': 'B', 'is_deleted': true},
          ],
          'current_page': 1,
          'last_page': 1,
        }),
      ),
    );
  });
}
