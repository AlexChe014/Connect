import 'package:connect/models/chat/create_chat_request.dart';
import 'package:connect/models/chat/update_chat_request.dart';
import 'package:connect/repositories/chat_management_repository.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Интеграционные тесты новых chat-роутов.
///
/// Запуск с учётными данными:
/// flutter test test/chat_management_repository_test.dart \
///   --dart-define=CHAT_TEST_EMAIL=... \
///   --dart-define=CHAT_TEST_PASSWORD=...
void main() {
  const email = String.fromEnvironment('CHAT_TEST_EMAIL');
  const password = String.fromEnvironment('CHAT_TEST_PASSWORD');

  group('ChatManagementRepository integration', () {
    setUpAll(() async {
      if (email.isEmpty || password.isEmpty) return;
      SharedPreferences.setMockInitialValues({});
      await AuthService.instance.init();
      await AuthService.instance.login(email, password);
    });

    Future<int> currentUserId() async {
      final user = await AuthService.instance.getStoredUser();
      final id = user?['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();
      return int.parse(id.toString());
    }

    test('createChat and sendTextMessage', () async {
      if (email.isEmpty || password.isEmpty) {
        markTestSkipped('CHAT_TEST_EMAIL / CHAT_TEST_PASSWORD not set');
        return;
      }

      final userId = await currentUserId();

      final created = await ChatManagementRepository.instance.createChat(
        CreateChatRequest(
          title: 'Flutter management test ${DateTime.now().millisecondsSinceEpoch}',
          isGroup: true,
          userIds: const [10],
        ),
        currentUserId: userId,
      );

      expect(created.id, greaterThan(0));
      expect(created.isGroup, isTrue);
      expect(created.members.length, greaterThanOrEqualTo(2));

      final sent = await ChatRepository.instance.sendTextMessage(
        created.id,
        text: 'management repo test message',
        currentUserId: userId,
      );
      expect(sent.text, 'management repo test message');
    });

    test('createDirectChat', () async {
      if (email.isEmpty || password.isEmpty) {
        markTestSkipped('CHAT_TEST_EMAIL / CHAT_TEST_PASSWORD not set');
        return;
      }

      final userId = await currentUserId();

      final direct = await ChatManagementRepository.instance.createChat(
        const CreateChatRequest(
          isGroup: false,
          userIds: [10],
        ),
        currentUserId: userId,
      );

      expect(direct.id, greaterThan(0));
      expect(direct.isGroup, isFalse);
    });

    test('updateChat with PUT', () async {
      if (email.isEmpty || password.isEmpty) {
        markTestSkipped('CHAT_TEST_EMAIL / CHAT_TEST_PASSWORD not set');
        return;
      }

      final userId = await currentUserId();
      final chat = await ChatManagementRepository.instance.createChat(
        CreateChatRequest(
          title: 'PUT probe ${DateTime.now().millisecondsSinceEpoch}',
          isGroup: true,
          userIds: const [10],
        ),
        currentUserId: userId,
      );

      final updated = await ChatManagementRepository.instance.updateChat(
        chat.id,
        const UpdateChatRequest(title: 'Renamed via PUT'),
        currentUserId: userId,
      );
      expect(updated.title, 'Renamed via PUT');
    });

    test('getMessages returns decrypted text', () async {
      if (email.isEmpty || password.isEmpty) {
        markTestSkipped('CHAT_TEST_EMAIL / CHAT_TEST_PASSWORD not set');
        return;
      }

      final userId = await currentUserId();
      final chats = await ChatRepository.instance.getChats(currentUserId: userId);
      if (chats.isEmpty) {
        markTestSkipped('No chats available');
        return;
      }

      final chatId = int.parse(chats.first.id);
      final page = await ChatRepository.instance.getMessages(
        chatId,
        currentUserId: userId,
      );
      for (final m in page.messages.data) {
        if (m.text == null) continue;
        expect(m.text!.contains('eyJ'), isFalse,
            reason: 'message should be plaintext, not encrypted blob');
      }
    });

    test('delete message, member, chat via repository', () async {
      if (email.isEmpty || password.isEmpty) {
        markTestSkipped('CHAT_TEST_EMAIL / CHAT_TEST_PASSWORD not set');
        return;
      }

      final userId = await currentUserId();
      final created = await ChatManagementRepository.instance.createChat(
        CreateChatRequest(
          title: 'Delete test ${DateTime.now().millisecondsSinceEpoch}',
          isGroup: true,
          userIds: const [10],
        ),
        currentUserId: userId,
      );

      final sent = await ChatRepository.instance.sendTextMessage(
        created.id,
        text: 'delete me',
        currentUserId: userId,
      );

      await ChatManagementRepository.instance.deleteMessage(
        created.id,
        int.parse(sent.id),
      );

      await ChatManagementRepository.instance.removeMember(
        created.id,
        10,
        currentUserId: userId,
      );

      try {
        await ChatManagementRepository.instance.deleteChat(created.id);
      } on ApiException catch (e) {
        // DELETE /api/chat/{id} часто блокируется на уровне сервера (403).
        expect(e.statusCode, anyOf(403, 404, 405));
      }
    });
  });
}
