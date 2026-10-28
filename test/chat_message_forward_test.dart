import 'package:connect/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _msg({
  String id = '10',
  String? text = 'привет',
  bool isSystem = false,
  bool isDeleted = false,
  bool isSending = false,
  String? stickerId,
}) => ChatMessage(
  id: id,
  chatId: '1',
  authorName: 'Автор',
  isOutgoing: true,
  createdAt: DateTime(2026, 10, 27),
  text: text,
  isSystem: isSystem,
  isDeleted: isDeleted,
  isSending: isSending,
  stickerId: stickerId,
);

void main() {
  test('обычное сообщение можно переслать', () {
    expect(_msg().canForward, isTrue);
    expect(_msg(text: null, stickerId: 'smile').canForward, isTrue);
  });

  test('системные, удалённые, неотправленные и пустые — нельзя', () {
    expect(_msg(isSystem: true).canForward, isFalse);
    expect(_msg(isDeleted: true).canForward, isFalse);
    expect(_msg(isSending: true).canForward, isFalse);
    expect(_msg(id: 'local-1').canForward, isFalse);
    expect(_msg(text: '  ').canForward, isFalse);
  });
}
