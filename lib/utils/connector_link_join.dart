import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:url_launcher/url_launcher.dart';

import '../repositories/connector_repository.dart';
import '../services/api_client.dart';
import 'app_logger.dart';
import 'connector_launch.dart';
import 'connector_url_utils.dart';

/// Вход во встречу по ссылке из календаря или брони.
///
/// Ссылка Коннектора открывается в приложении через `GET /connector/join`.
/// Если сервер отказал с 403 («Конференция завершена»), предлагаем войти
/// через портал в браузере: комнату мог ошибочно закрыть вебхук Jitsi,
/// когда кто-то зашёл раньше и вышел, а портал статус не проверяет. Кнопку
/// входа экраны показывают только до конца брони, поэтому отказ здесь —
/// почти наверняка такая ошибка, а не реально прошедшая встреча.
Future<void> joinMeetingLink(BuildContext context, String url) async {
  final room = connectorRoomFromUrl(url);
  if (room == null) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  try {
    final session = await ConnectorRepository.instance.join(room);
    await openConnectorSession(session);
  } catch (e) {
    AppLogger.d('connector join $room failed: $e', name: 'meeting');
    if (!context.mounted) return;
    if (e is ApiException && e.statusCode == 403) {
      await _offerPortal(context, url, e.message);
      return;
    }
    final message = e is ApiException
        ? e.message
        : 'Не удалось подключиться к конференции';
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> _offerPortal(
  BuildContext context,
  String url,
  String serverMessage,
) async {
  final open = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(serverMessage),
      content: const Text(
        'Сервер не пускает во встречу из приложения. '
        'Можно подключиться через портал в браузере.',
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Открыть в браузере'),
        ),
      ],
    ),
  );
  if (open != true) return;
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}
