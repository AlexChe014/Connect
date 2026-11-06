import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_read_receipts.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/utils/chat_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _outgoing({
  Map<int, bool> reads = const {},
  bool readByRecipients = false,
}) => ChatMessage(
  id: '1',
  chatId: '9',
  authorName: 'Я',
  isOutgoing: true,
  createdAt: DateTime(2026, 11, 6),
  recipientReads: reads,
  readByRecipients: readByRecipients,
);

ChatMemberSummary _member(int id, String name) =>
    ChatMemberSummary(userId: id, displayName: name);

void main() {
  group('ChatMapper recipientReads', () {
    ChatMessage map(int senderId) => ChatMapper.mapMessage(
      {
        'id': 1,
        'sender_id': senderId,
        'message': 'Привет',
        'type': 'TEXT',
        'created_at': '2026-11-06T10:00:00+00:00',
        'statuses': [
          {'user_id': 1, 'read': true},
          {'user_id': 2, 'read': true},
          {'user_id': 3, 'read': false},
        ],
      },
      chatId: '9',
      currentUserId: 1,
    );

    test('outgoing keeps per-recipient state without the sender', () {
      final m = map(1);
      expect(m.recipientReads, {2: true, 3: false});
      expect(m.readByRecipients, isFalse);
    });

    test('incoming has no recipient state', () {
      expect(map(2).recipientReads, isEmpty);
    });
  });

  group('copyWithReadBy', () {
    test('one reader of two does not light the double tick', () {
      final m = _outgoing(reads: {2: false, 3: false}).copyWithReadBy(2);
      expect(m.recipientReads, {2: true, 3: false});
      expect(m.readByRecipients, isFalse);
    });

    test('last reader lights the double tick', () {
      final m = _outgoing(reads: {2: true, 3: false}).copyWithReadBy(3);
      expect(m.readByRecipients, isTrue);
    });

    test('member without a status does not count', () {
      final m = _outgoing(reads: {2: false}).copyWithReadBy(7);
      expect(m.recipientReads, {2: false});
      expect(m.readByRecipients, isFalse);
    });

    test('without statuses counts from the given recipients', () {
      final m = _outgoing().copyWithReadBy(2, recipients: const [2, 3]);
      expect(m.recipientReads, {2: true, 3: false});
      expect(m.readByRecipients, isFalse);
    });

    test('direct chat without statuses is simply read', () {
      expect(_outgoing().copyWithReadBy(2).readByRecipients, isTrue);
    });
  });

  group('recipientReadsMergedWith', () {
    test('reply without statuses keeps the known ones', () {
      final previous = _outgoing(reads: {2: true});
      expect(_outgoing().recipientReadsMergedWith(previous), {2: true});
    });

    test('a read status is never reverted', () {
      final previous = _outgoing(reads: {2: true, 3: false});
      final incoming = _outgoing(reads: {2: false, 3: true});
      expect(incoming.recipientReadsMergedWith(previous), {2: true, 3: true});
    });
  });

  group('ChatReadReceipts.of', () {
    final members = [
      _member(1, 'Я'),
      _member(2, 'Борис'),
      _member(3, 'Анна'),
      _member(4, 'Вера'),
      _member(5, 'Глеб'),
    ];

    test('splits members, skips self and those without a status', () {
      final r = ChatReadReceipts.of(
        _outgoing(reads: {2: true, 3: true, 4: false}),
        members,
        selfUserId: 1,
      );
      expect(r.read.map((m) => m.displayName), ['Анна', 'Борис']);
      expect(r.unread.map((m) => m.displayName), ['Вера']);
      expect(r.total, 3);
    });

    test('no statuses yet means nobody has read it', () {
      final r = ChatReadReceipts.of(_outgoing(), members, selfUserId: 1);
      expect(r.read, isEmpty);
      expect(r.unread, hasLength(4));
    });
  });
}
