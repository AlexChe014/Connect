import 'package:connect/config/routes/user_routes.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/utils/user_display_name.dart';
import 'package:flutter/foundation.dart';

/// Имена сотрудников по id для пометки «Переслано от …».
///
/// Сервер у пересланного сообщения отдаёт только `forwarded_from_user_id`.
/// Имя берётся из уже увиденных отправителей, а если человека ещё не
/// встречали — один раз загружается через `GET /user/get/{id}`.
class ChatUserNames extends ChangeNotifier {
  ChatUserNames._();

  static final ChatUserNames instance = ChatUserNames._();

  final Map<int, String> _names = {};
  final Set<int> _requested = {};

  String? nameFor(int userId) => _names[userId];

  /// Запоминает имя отправителя из ответа сервера. Не уведомляет слушателей:
  /// вызывается при разборе сообщений, имя появится при следующей отрисовке.
  void remember(int userId, String name) {
    if (name.isEmpty || name == 'Пользователь') return;
    _names[userId] = name;
  }

  /// Загружает имя, если его ещё нет. Повторно один id не запрашивается.
  Future<void> ensure(int userId) async {
    if (_names.containsKey(userId) || !_requested.add(userId)) return;
    try {
      final decoded = await ApiClient.instance.get(
        UserRoutes.getUserUrl(userId),
      );
      final data = ApiEnvelope.unwrapDataMap(decoded);
      final name = userDisplayNameFromJson(data);
      if (name == 'Пользователь') return;
      _names[userId] = name;
      notifyListeners();
    } catch (_) {
      // Пометка останется «Переслано от Пользователь» — не повод для ошибки.
    }
  }

  void clear() {
    _names.clear();
    _requested.clear();
  }
}
