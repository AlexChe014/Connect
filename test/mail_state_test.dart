import 'package:connect/models/mail/mail_folder.dart';
import 'package:connect/models/mail/mail_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes special folders inside IMAP namespaces', () {
    for (final name in ['INBOX.Drafts', 'INBOX/Черновики', '[Gmail]/Drafts']) {
      final folder = MailFolder(id: 1, name: name, depth: 1);
      expect(folder.isDrafts, isTrue, reason: name);
      expect(folder.isHiddenSystemFolder, isFalse);
    }
    expect(const MailFolder(id: 2, name: 'INBOX.Sent').isSent, isTrue);
    expect(
      const MailFolder(id: 3, name: 'Archive').isHiddenSystemFolder,
      isFalse,
    );
    expect(
      const MailFolder(id: 4, name: 'Contacts').isHiddenSystemFolder,
      isTrue,
    );
  });

  test('current read state takes precedence over stale IMAP field', () {
    final message = MailMessage.fromJson({
      'id': 1,
      'subject': 'Subject',
      'is_read': '1',
      'seen': false,
    });
    expect(message.isRead, isTrue);
    expect(MailMessage.fromJson({'id': 2, 'is_read': 0}).isRead, isFalse);
  });

  test('read acknowledgement preserves message content and attachments', () {
    const original = MailMessage(
      id: 1,
      subject: 'Subject',
      from: 'sender',
      body: 'Text',
      bodyHtml: '<p>Text</p>',
      isRead: false,
      attachments: [MailAttachment(id: 4, filename: 'a.pdf')],
    );
    final read = original.withRead(true);
    expect(read.isRead, isTrue);
    expect(read.bodyHtml, original.bodyHtml);
    expect(read.attachments, original.attachments);
    expect(original.isRead, isFalse);
  });
}
