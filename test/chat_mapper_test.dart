import 'package:connect/models/chat_message.dart';
import 'package:connect/utils/chat_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMapper.mapMembers', () {
    test('maps a valid member list', () {
      final members = ChatMapper.mapMembers([
        {
          'user_id': 10,
          'is_admin': true,
          'user': {'name': 'Иван', 'surname': 'Иванов'},
        },
        {
          'user': {'id': 20, 'name': 'Пётр', 'surname': 'Петров'},
        },
      ]);

      expect(members, hasLength(2));
      expect(members[0].userId, 10);
      expect(members[0].displayName, 'Иванов Иван');
      expect(members[0].isAdmin, isTrue);
      // Falls back to user.id when user_id is absent.
      expect(members[1].userId, 20);
      expect(members[1].isAdmin, isFalse);
    });

    test('skips entries without a resolvable user id, keeps the rest', () {
      final members = ChatMapper.mapMembers([
        {'user': null},
        {
          'user_id': 5,
          'user': {'name': 'Ok'},
        },
      ]);
      expect(members, hasLength(1));
      expect(members.single.userId, 5);
    });

    test('non-list input yields an empty list', () {
      expect(ChatMapper.mapMembers(null), isEmpty);
      expect(ChatMapper.mapMembers('not a list'), isEmpty);
    });
  });

  group('ChatMapper.mapMessage', () {
    test('maps a plain text message and marks it outgoing for the sender', () {
      final message = ChatMapper.mapMessage(
        {
          'id': 5,
          'sender_id': 10,
          'sender': {'name': 'Иван', 'surname': 'Иванов'},
          'type': 'TEXT',
          'message': 'Привет',
          'created_at': '2026-01-01T10:00:00Z',
        },
        chatId: '1',
        currentUserId: 10,
      );

      expect(message.isOutgoing, isTrue);
      expect(message.authorName, 'Иванов Иван');
      expect(message.text, 'Привет');
      expect(message.attachmentKind, ChatAttachmentKind.none);
      expect(message.isSystem, isFalse);
    });

    test('resolves a MEDIA message from an attachments URL', () {
      final message = ChatMapper.mapMessage(
        {
          'id': 6,
          'sender_id': 20,
          'type': 'MEDIA',
          'attachments': {'url': 'http://cdn.example.com/img.png'},
        },
        chatId: '1',
        currentUserId: 10,
      );

      expect(message.isOutgoing, isFalse);
      expect(message.attachmentKind, ChatAttachmentKind.image);
      expect(message.remoteMediaUrl, 'http://cdn.example.com/img.png');
      expect(message.text, isNull);
    });

    test('resolves a MEDIA message where the URL is in the message field itself', () {
      final message = ChatMapper.mapMessage(
        {
          'id': 7,
          'sender_id': 20,
          'type': 'MEDIA',
          'message': 'http://cdn.example.com/img2.png',
        },
        chatId: '1',
        currentUserId: 10,
      );

      expect(message.remoteMediaUrl, 'http://cdn.example.com/img2.png');
      expect(message.text, isNull);
    });

    test('marks SYSTEM messages and keeps their text', () {
      final message = ChatMapper.mapMessage(
        {'id': 8, 'type': 'SYSTEM', 'message': 'Пользователь добавлен в чат'},
        chatId: '1',
        currentUserId: 10,
      );

      expect(message.isSystem, isTrue);
      expect(message.text, 'Пользователь добавлен в чат');
    });

    test('missing created_at falls back to now instead of throwing', () {
      final message = ChatMapper.mapMessage(
        {'id': 9, 'sender_id': 10, 'type': 'TEXT', 'message': 'hi'},
        chatId: '1',
        currentUserId: 10,
      );
      expect(
        DateTime.now().difference(message.createdAt).inMinutes.abs(),
        lessThan(1),
      );
    });

    group('read state', () {
      test('a message from myself is always read', () {
        final message = ChatMapper.mapMessage(
          {'id': 1, 'sender_id': 10, 'type': 'TEXT', 'message': 'hi'},
          chatId: '1',
          currentUserId: 10,
        );
        expect(message.isRead, isTrue);
      });

      test('no statuses info defaults to read', () {
        final message = ChatMapper.mapMessage(
          {'id': 1, 'sender_id': 20, 'type': 'TEXT', 'message': 'hi'},
          chatId: '1',
          currentUserId: 10,
        );
        expect(message.isRead, isTrue);
      });

      test('an explicit unread status for me is respected', () {
        final message = ChatMapper.mapMessage(
          {
            'id': 1,
            'sender_id': 20,
            'type': 'TEXT',
            'message': 'hi',
            'statuses': [
              {'user_id': 10, 'read': false},
            ],
          },
          chatId: '1',
          currentUserId: 10,
        );
        expect(message.isRead, isFalse);
      });

      test('readByRecipients is true only when every recipient has read it', () {
        final allRead = ChatMapper.mapMessage(
          {
            'id': 1,
            'sender_id': 10,
            'type': 'TEXT',
            'message': 'hi',
            'statuses': [
              {'user_id': 20, 'read': true},
              {'user_id': 30, 'read': true},
            ],
          },
          chatId: '1',
          currentUserId: 10,
        );
        expect(allRead.readByRecipients, isTrue);

        final partiallyRead = ChatMapper.mapMessage(
          {
            'id': 1,
            'sender_id': 10,
            'type': 'TEXT',
            'message': 'hi',
            'statuses': [
              {'user_id': 20, 'read': true},
              {'user_id': 30, 'read': false},
            ],
          },
          chatId: '1',
          currentUserId: 10,
        );
        expect(partiallyRead.readByRecipients, isFalse);

        final incoming = ChatMapper.mapMessage(
          {
            'id': 1,
            'sender_id': 20,
            'type': 'TEXT',
            'message': 'hi',
            'statuses': [
              {'user_id': 20, 'read': true},
            ],
          },
          chatId: '1',
          currentUserId: 10,
        );
        expect(incoming.readByRecipients, isFalse);
      });
    });
  });

  group('ChatMapper.snippet', () {
    DateTime now() => DateTime(2026, 1, 1);

    test('uses the plain-text message when present', () {
      final m = ChatMessage(
        id: '1',
        chatId: '1',
        authorName: 'A',
        isOutgoing: false,
        createdAt: now(),
        text: '<b>Hello</b>',
      );
      expect(ChatMapper.snippet(m), 'Hello');
    });

    test('falls back to an icon label per attachment kind', () {
      final image = ChatMessage(
        id: '1',
        chatId: '1',
        authorName: 'A',
        isOutgoing: false,
        createdAt: now(),
        attachmentKind: ChatAttachmentKind.image,
      );
      final video = ChatMessage(
        id: '2',
        chatId: '1',
        authorName: 'A',
        isOutgoing: false,
        createdAt: now(),
        attachmentKind: ChatAttachmentKind.video,
      );
      final fileNamed = ChatMessage(
        id: '3',
        chatId: '1',
        authorName: 'A',
        isOutgoing: false,
        createdAt: now(),
        attachmentKind: ChatAttachmentKind.file,
        fileName: 'report.pdf',
      );
      final fileUnnamed = ChatMessage(
        id: '4',
        chatId: '1',
        authorName: 'A',
        isOutgoing: false,
        createdAt: now(),
        attachmentKind: ChatAttachmentKind.file,
      );

      expect(ChatMapper.snippet(image), '📷 Фото');
      expect(ChatMapper.snippet(video), '🎬 Видео');
      expect(ChatMapper.snippet(fileNamed), '📎 report.pdf');
      expect(ChatMapper.snippet(fileUnnamed), '📎 Файл');
    });

    test('a system message without text falls back to a placeholder', () {
      final m = ChatMessage(
        id: '1',
        chatId: '1',
        authorName: 'A',
        isOutgoing: false,
        createdAt: now(),
        isSystem: true,
      );
      expect(ChatMapper.snippet(m), 'Системное сообщение');
    });

    test('a message with no text and no attachment falls back to a generic label', () {
      final m = ChatMessage(
        id: '1',
        chatId: '1',
        authorName: 'A',
        isOutgoing: false,
        createdAt: now(),
      );
      expect(ChatMapper.snippet(m), 'Сообщение');
    });
  });

  group('ChatMapper.attachReplyReferences', () {
    test('links a reply to its source message by id', () {
      final source = ChatMessage(
        id: '1',
        chatId: '1',
        authorName: 'Иван',
        isOutgoing: false,
        createdAt: DateTime(2026, 1, 1),
        text: 'Original message',
      );
      final reply = ChatMessage(
        id: '2',
        chatId: '1',
        authorName: 'Пётр',
        isOutgoing: true,
        createdAt: DateTime(2026, 1, 1, 0, 1),
        text: 'A reply',
        repliedMessageId: '1',
      );

      final result = ChatMapper.attachReplyReferences([source, reply]);

      expect(result[0].replyTo, isNull);
      expect(result[1].replyTo, isNotNull);
      expect(result[1].replyTo!.messageId, '1');
      expect(result[1].replyTo!.authorName, 'Иван');
      expect(result[1].replyTo!.textPreview, 'Original message');
    });

    test('a reply pointing at an unknown id is left without a reference', () {
      final reply = ChatMessage(
        id: '2',
        chatId: '1',
        authorName: 'Пётр',
        isOutgoing: true,
        createdAt: DateTime(2026, 1, 1),
        text: 'A reply',
        repliedMessageId: 'missing',
      );

      final result = ChatMapper.attachReplyReferences([reply]);
      expect(result.single.replyTo, isNull);
    });

    test('an empty list is returned as-is', () {
      expect(ChatMapper.attachReplyReferences(const []), isEmpty);
    });
  });

  group('ChatMapper.mapChat', () {
    test('a titled group chat keeps its title', () {
      final chat = ChatMapper.mapChat(
        {
          'id': 1,
          'is_group': true,
          'title': '  Дизайн-команда  ',
          'members': [],
        },
        currentUserId: 10,
      );
      expect(chat.title, 'Дизайн-команда');
      expect(chat.isGroup, isTrue);
    });

    test('an untitled group chat falls back to a generic label', () {
      final chat = ChatMapper.mapChat(
        {'id': 1, 'is_group': true, 'members': []},
        currentUserId: 10,
      );
      expect(chat.title, 'Группа');
    });

    test('an untitled direct chat uses the peer\'s display name', () {
      final chat = ChatMapper.mapChat(
        {
          'id': 1,
          'is_group': false,
          'members': [
            {
              'user_id': 10,
              'user': {'name': 'Me', 'surname': 'Myself'},
            },
            {
              'user_id': 20,
              'user': {'name': 'Иван', 'surname': 'Иванов'},
            },
          ],
        },
        currentUserId: 10,
      );
      expect(chat.title, 'Иванов Иван');
      expect(chat.peerUserId, 20);
    });

    test('unread_count is parsed whether it arrives as a number or a string', () {
      final chat = ChatMapper.mapChat(
        {'id': 1, 'is_group': true, 'title': 'X', 'unread_count': '3'},
        currentUserId: 10,
      );
      expect(chat.unreadCount, 3);
    });
  });
}
