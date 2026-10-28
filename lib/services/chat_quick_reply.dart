import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Кнопки «Ответить» / «Прочитано» в уведомлении о сообщении чата.
///
/// iOS обрабатывает их нативно (AppDelegate, категория `CHAT_MESSAGE`) —
/// идентификаторы действий должны совпадать. Android — здесь: колбэк
/// вызывается и в отдельном фоновом изоляте, где нет ни AuthService, ни
/// ApiClient, поэтому запросы идут напрямую по токену из SharedPreferences.
/// Так же 401 из фона не разлогинивает пользователя.
class ChatQuickReply {
  ChatQuickReply._();

  static const replyActionId = 'chat_reply';
  static const markReadActionId = 'chat_mark_read';

  /// Ключ токена — тот же, что у AuthService.
  static const _tokenKey = 'auth_bearer_token';
  static const _timeout = Duration(seconds: 15);

  static const androidActions = <AndroidNotificationAction>[
    AndroidNotificationAction(
      replyActionId,
      'Ответить',
      inputs: [AndroidNotificationActionInput(label: 'Сообщение')],
      semanticAction: SemanticAction.reply,
    ),
    AndroidNotificationAction(
      markReadActionId,
      'Прочитано',
      semanticAction: SemanticAction.markAsRead,
    ),
  ];

  static bool isQuickAction(String? actionId) =>
      actionId == replyActionId || actionId == markReadActionId;

  /// Выполнить действие из уведомления. Возвращает id чата, если
  /// что-то было отправлено на сервер.
  static Future<int?> handle(
    String? actionId,
    String? input,
    Map<String, dynamic> data,
  ) async {
    final chatId = int.tryParse(data['chat_id']?.toString() ?? '');
    if (chatId == null || !isQuickAction(actionId)) return null;

    await ApiConfig.init();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      if (actionId == replyActionId) {
        final text = input?.trim() ?? '';
        if (text.isEmpty) return null;
        final response = await http
            .post(
              Uri.parse(ChatRoutes.messagesUrl(chatId)),
              headers: headers,
              body: jsonEncode({'message': text, 'text': text}),
            )
            .timeout(_timeout);
        if (response.statusCode >= 300) {
          AppLogger.e(
            'Quick reply failed: ${response.statusCode} '
            '${AppLogger.truncate(response.body)}',
            name: 'push',
          );
          return null;
        }
      }
      // Ответили — значит, прочитали.
      await http
          .post(Uri.parse(ChatRoutes.readUrl(chatId)), headers: headers)
          .timeout(_timeout);
      return chatId;
    } catch (e, st) {
      AppLogger.e(
        'Quick action $actionId failed',
        name: 'push',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}

/// Нажатие кнопки уведомления, когда приложение в фоне или убито (Android).
@pragma('vm:entry-point')
Future<void> chatNotificationBackgroundResponse(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatQuickReply.handle(
    response.actionId,
    response.input,
    decodeNotificationPayload(response.payload),
  );
}

/// Пары `key=value` через `&` — формат payload локальных уведомлений.
String encodeNotificationPayload(Map<String, dynamic> data) {
  return data.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
      .join('&');
}

Map<String, dynamic> decodeNotificationPayload(String? payload) {
  final result = <String, dynamic>{};
  if (payload == null) return result;
  for (final part in payload.split('&')) {
    if (part.isEmpty) continue;
    final idx = part.indexOf('=');
    if (idx <= 0) continue;
    result[part.substring(0, idx)] = Uri.decodeComponent(
      part.substring(idx + 1),
    );
  }
  return result;
}
