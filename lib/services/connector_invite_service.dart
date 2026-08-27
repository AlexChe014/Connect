import 'package:connect/models/connector/connector_session.dart';
import 'package:connect/models/staff_user.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/utils/app_logger.dart';

/// Отправка приглашений на видеовстречу в личные чаты.
class ConnectorInviteService {
  ConnectorInviteService._();
  static final ConnectorInviteService instance = ConnectorInviteService._();

  /// Текст приглашения с публичной ссылкой (браузер и приложение).
  static String inviteMessage({
    required ConnectorSession session,
    String? topic,
  }) {
    final link = session.publicUrl.trim().isNotEmpty
        ? session.publicUrl.trim()
        : 'https://connect.xondev.ru/connector/${session.room}';
    final title = (topic ?? session.topic)?.trim();
    final themePart = (title != null && title.isNotEmpty)
        ? ' «$title»'
        : '';
    return 'Вас пригласили на видеовстречу$themePart.\n\n'
        'Подключиться:\n$link';
  }

  /// Создаёт/открывает личный чат с каждым и отправляет ссылку.
  /// Возвращает число успешно отправленных приглашений.
  Future<int> inviteUsers({
    required ConnectorSession session,
    required List<StaffUser> users,
    String? topic,
  }) async {
    if (users.isEmpty) return 0;

    final chat = ChatService.instance;
    await chat.init();

    final text = inviteMessage(session: session, topic: topic);
    var sent = 0;

    for (final user in users) {
      final userId = user.idAsInt;
      if (userId == null) continue;

      try {
        final direct = await chat.createDirect(
          fullName: user.chatDisplayName,
          peerUserId: userId,
          peerAvatarUrl: user.avatarUrl,
        );
        if (direct == null) continue;

        await chat.sendText(direct.id, text);
        sent++;
      } catch (e, st) {
        AppLogger.e(
          'Не удалось отправить приглашение userId=$userId',
          name: 'meeting.invite',
          error: e,
          stackTrace: st,
        );
      }
    }

    return sent;
  }
}
