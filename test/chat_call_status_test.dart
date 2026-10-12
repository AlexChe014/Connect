import 'package:connect/models/chat/chat_call_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatCallStatus.tryParse', () {
    test('parses wire values and aliases', () {
      expect(ChatCallStatus.tryParse('declined'), ChatCallStatus.declined);
      expect(ChatCallStatus.tryParse('canceled'), ChatCallStatus.cancelled);
      expect(ChatCallStatus.tryParse('no_answer'), ChatCallStatus.missed);
      expect(
        ChatCallStatus.tryParse('answered-elsewhere'),
        ChatCallStatus.answeredElsewhere,
      );
      expect(ChatCallStatus.tryParse('BUSY'), ChatCallStatus.busy);
      expect(ChatCallStatus.tryParse(''), isNull);
      expect(ChatCallStatus.tryParse('whatever'), isNull);
    });

    test('final vs in-progress', () {
      expect(ChatCallStatus.ringing.isFinal, isFalse);
      expect(ChatCallStatus.accepted.isFinal, isFalse);
      expect(ChatCallStatus.missed.isFinal, isTrue);
      expect(ChatCallStatus.answeredElsewhere.isFinal, isTrue);
    });
  });

  group('ChatCallSignal', () {
    test('legacy chat_call_ended push with status', () {
      final s = ChatCallSignal.tryParse({
        'type': 'chat_call_ended',
        'call_id': 'abc',
        'status': 'declined',
      })!;
      expect(s.callId, 'abc');
      expect(s.status, ChatCallStatus.declined);
    });

    test('legacy chat_call_ended push without status means ended', () {
      final s = ChatCallSignal.tryParse({
        'type': 'chat_call_ended',
        'call_id': 'abc',
      })!;
      expect(s.status, ChatCallStatus.ended);
    });

    test('chat_call_accepted push', () {
      final s = ChatCallSignal.tryParse({
        'type': 'chat_call_accepted',
        'call_id': 'abc',
        'device_id': 'dev-1',
      })!;
      expect(s.status, ChatCallStatus.accepted);
      expect(s.deviceId, 'dev-1');
    });

    test('Reverb event with nested call payload', () {
      final data = {
        'call': {'call_id': 'xyz', 'status': 'missed', 'chat_id': '7'},
      };
      expect(
        ChatCallSignal.isCallSignal(data, eventName: 'call.status'),
        isTrue,
      );
      final s = ChatCallSignal.tryParse(data, eventName: 'call.status')!;
      expect(s.callId, 'xyz');
      expect(s.status, ChatCallStatus.missed);
      expect(s.chatId, '7');
    });

    test('Reverb event name gives status when payload has none', () {
      const event = 'App\\Events\\Chat\\CallAccepted';
      expect(
        ChatCallSignal.isCallSignal({'call_id': 'q'}, eventName: event),
        isTrue,
      );
      final s = ChatCallSignal.tryParse({'call_id': 'q'}, eventName: event);
      expect(s?.status, ChatCallStatus.accepted);
    });

    test('incoming invite and chat messages are not status signals', () {
      expect(
        ChatCallSignal.isCallSignal({'type': 'chat_call', 'call_id': '1'}),
        isFalse,
      );
      expect(
        ChatCallSignal.isCallSignal(
          {'message': {'id': 1}},
          eventName: 'message.created',
        ),
        isFalse,
      );
    });
  });
}
