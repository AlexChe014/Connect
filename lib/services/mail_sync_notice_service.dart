import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Помнит, когда на этом устройстве подключили почтовый ящик. Сервер
/// забирает письма из IMAP фоновой задачей не сразу и порциями, а статуса
/// синхронизации в API нет — поэтому первое время после подключения
/// входящие показывают «письма загружаются», а не «нет писем».
class MailSyncNoticeService {
  MailSyncNoticeService._();
  static final MailSyncNoticeService instance = MailSyncNoticeService._();

  static const _storageKey = 'mail_sync_notice';

  /// Сколько показывать уведомление: большой ящик может грузиться часами.
  static const noticeDuration = Duration(hours: 24);

  /// e-mail ящика (в нижнем регистре) → момент подключения, мс.
  Map<String, int> _connectedAt = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _connectedAt = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        _connectedAt = {};
      }
    }
    _loaded = true;
  }

  /// Ящик подключён недавно — письма, скорее всего, ещё подтягиваются.
  bool isSyncing(String email) {
    final at = _connectedAt[_key(email)];
    if (at == null) return false;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    return age < noticeDuration;
  }

  Future<void> markConnected(String email) async {
    await ensureLoaded();
    _connectedAt[_key(email)] = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  /// Пользователь закрыл уведомление — больше не показываем.
  Future<void> dismiss(String email) async {
    await ensureLoaded();
    if (_connectedAt.remove(_key(email)) == null) return;
    await _save();
  }

  Future<void> _save() async {
    final now = DateTime.now();
    _connectedAt.removeWhere(
      (_, at) =>
          now.difference(DateTime.fromMillisecondsSinceEpoch(at)) >=
          noticeDuration,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_connectedAt));
  }

  static String _key(String email) => email.trim().toLowerCase();
}
