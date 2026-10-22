import 'package:flutter/foundation.dart';

import '../repositories/notifications_repository.dart';
import 'auth_service.dart';

/// Число непрочитанных уведомлений — источник бейджа «Уведомления» в
/// боковом меню, точки на кнопке меню и колокольчика в профиле.
class NotificationUnreadService extends ChangeNotifier {
  NotificationUnreadService({Future<int> Function()? load})
    : _load = load ?? NotificationsRepository.instance.getUnreadCount;
  static final instance = NotificationUnreadService();

  final Future<int> Function() _load;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _isRefreshing = false;
  bool _refreshAgain = false;
  int _generation = 0;

  /// Фоновое обновление: при ошибке сети остаётся последнее значение.
  Future<void> refresh() async {
    if (_isRefreshing) {
      _refreshAgain = true;
      return;
    }
    _isRefreshing = true;
    final generation = _generation;
    final session = AuthService.instance.sessionGeneration;
    try {
      final count = await _load();
      if (generation == _generation &&
          session == AuthService.instance.sessionGeneration) {
        _setUnreadCount(count);
      }
    } catch (_) {
    } finally {
      _isRefreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        await refresh();
      }
    }
  }

  /// Локально уменьшает счётчик после отметки уведомления прочитанным.
  /// Ответ `/unread`, начатый до отметки, отбрасываем: в нём старое число.
  void markRead([int count = 1]) {
    if (count <= 0) return;
    _generation++;
    _setUnreadCount((_unreadCount - count).clamp(0, _unreadCount));
  }

  void markAllRead() {
    _generation++;
    _setUnreadCount(0);
  }

  void reset() {
    _generation++;
    _refreshAgain = false;
    _setUnreadCount(0);
  }

  void _setUnreadCount(int value) {
    if (_unreadCount == value) return;
    _unreadCount = value;
    notifyListeners();
  }
}
