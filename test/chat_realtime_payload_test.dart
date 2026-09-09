import 'package:connect/utils/chat_realtime_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatRealtimePayload.classifyEvent', () {
    test('maps common Laravel / Echo names', () {
      expect(
        ChatRealtimePayload.classifyEvent(r'App\Events\MessageSent'),
        ChatRealtimeKind.created,
      );
      expect(
        ChatRealtimePayload.classifyEvent('.message.sent'),
        ChatRealtimeKind.created,
      );
      expect(
        ChatRealtimePayload.classifyEvent('MessageUpdated'),
        ChatRealtimeKind.updated,
      );
      expect(
        ChatRealtimePayload.classifyEvent('message.deleted'),
        ChatRealtimeKind.deleted,
      );
      expect(
        ChatRealtimePayload.classifyEvent('MessageRead'),
        ChatRealtimeKind.read,
      );
      expect(
        ChatRealtimePayload.classifyEvent('MemberAdded'),
        ChatRealtimeKind.members,
      );
    });

    test('detects protocol events', () {
      expect(ChatRealtimePayload.isProtocolEvent('pusher:ping'), isTrue);
      expect(ChatRealtimePayload.isProtocolEvent('client-typing'), isTrue);
      expect(ChatRealtimePayload.isProtocolEvent('MessageSent'), isFalse);
    });
  });

  group('ChatRealtimePayload.extractMessage', () {
    test('unwraps nested MessageResource', () {
      final extracted = ChatRealtimePayload.extractMessage({
        'message': {
          'id': 9,
          'chat_id': 3,
          'sender_id': 2,
          'message': 'Привет',
          'type': 'TEXT',
        },
      });
      expect(extracted?['id'], 9);
      expect(extracted?['sender_id'], 2);
    });

    test('accepts a flat message payload', () {
      final extracted = ChatRealtimePayload.extractMessage({
        'id': 4,
        'chat_id': 1,
        'sender_id': 8,
        'message': 'ok',
      });
      expect(extracted?['id'], 4);
    });

    test('does not treat plaintext message field as nested object', () {
      final extracted = ChatRealtimePayload.extractMessage({
        'id': 4,
        'chat_id': 1,
        'sender_id': 8,
        'message': 'просто текст',
      });
      expect(extracted?['message'], 'просто текст');
    });
  });

  group('ChatRealtimePayload ids', () {
    test('reads chat id from payload and channel name', () {
      expect(
        ChatRealtimePayload.extractChatId({'chat_id': 12}),
        '12',
      );
      expect(
        ChatRealtimePayload.extractChatId(
          {'message': {'id': 1, 'chat_id': 7, 'sender_id': 2}},
        ),
        '7',
      );
      expect(
        ChatRealtimePayload.extractChatId(
          const {},
          channelName: 'private-chat.15',
        ),
        '15',
      );
    });

    test('reads message and reader ids', () {
      expect(
        ChatRealtimePayload.extractMessageId({'message_id': 44, 'chat_id': 1}),
        '44',
      );
      expect(
        ChatRealtimePayload.extractUserId({'user_id': 3}),
        3,
      );
    });
  });
}
