import 'package:flutter/foundation.dart';

import '../repositories/mail_repository.dart';
import '../repositories/profile_repository.dart';
import 'auth_service.dart';

/// Суммарное число непрочитанных писем во «Входящих» по всем почтовым
/// подключениям пользователя — источник данных для бейджа в боковом меню.
class MailUnreadService extends ChangeNotifier {
  MailUnreadService._();
  static final MailUnreadService instance = MailUnreadService._();

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _isRefreshing = false;
  bool _refreshAgain = false;
  int _generation = 0;
  final ValueNotifier<int> mailChanges = ValueNotifier(0);
  final Map<int, int> _connectionCounts = {};

  void invalidate() {
    mailChanges.value++;
    refresh();
  }

  static int? _parseUserId(Map<String, dynamic>? json) {
    if (json == null) return null;
    final raw = json['id'] ?? json['user_id'];
    if (raw != null) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
    }
    final nested = json['user'];
    if (nested is Map) {
      return _parseUserId(Map<String, dynamic>.from(nested));
    }
    return null;
  }

  Future<int?> _resolveUserId() async {
    try {
      final profile = await ProfileRepository.instance.getProfile();
      final profileId = _parseUserId(profile);
      if (profileId != null) return profileId;
    } catch (_) {}
    return _parseUserId(await AuthService.instance.getStoredUser());
  }

  Future<void> refresh() async {
    if (_isRefreshing) {
      _refreshAgain = true;
      return;
    }
    _isRefreshing = true;
    final generation = _generation;
    final session = AuthService.instance.sessionGeneration;
    try {
      final userId = await _resolveUserId();
      if (generation != _generation ||
          session != AuthService.instance.sessionGeneration) {
        return;
      }
      if (userId == null) {
        _setUnreadCount(0);
        return;
      }
      final connections = await MailRepository.instance.getConnectionsByUser(
        userId,
      );
      if (generation != _generation ||
          session != AuthService.instance.sessionGeneration) {
        return;
      }
      final activeIds = connections
          .where((c) => c.isActive)
          .map((c) => c.id)
          .toSet();
      _connectionCounts.removeWhere((id, _) => !activeIds.contains(id));
      var total = 0;
      for (final connection in connections.where((c) => c.isActive)) {
        try {
          final folders = await MailRepository.instance.getMailboxes(
            connection.id,
          );
          if (generation != _generation ||
              session != AuthService.instance.sessionGeneration) {
            return;
          }
          _connectionCounts[connection.id] = folders
              .where((folder) => folder.isInbox)
              .fold<int>(0, (sum, folder) => sum + (folder.unreadCount ?? 0));
        } catch (_) {
          // Пропускаем недоступное подключение, не обнуляя остальной счёт.
        }
        total += _connectionCounts[connection.id] ?? 0;
      }
      if (generation == _generation &&
          session == AuthService.instance.sessionGeneration) {
        _setUnreadCount(total);
      }
    } catch (_) {
      // Сеть недоступна — оставляем последнее известное значение бейджа.
    } finally {
      _isRefreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        refresh();
      }
    }
  }

  void reset() {
    _generation++;
    _refreshAgain = false;
    _connectionCounts.clear();
    _setUnreadCount(0);
  }

  void _setUnreadCount(int value) {
    if (_unreadCount == value) return;
    _unreadCount = value;
    notifyListeners();
  }
}
