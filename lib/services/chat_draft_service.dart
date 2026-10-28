import 'dart:convert';

import 'package:connect/utils/chat_storage_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальные черновики сообщений в чатах — текст композера сохраняется
/// при выходе из чата и подставляется обратно при повторном открытии
/// (как в WhatsApp/Telegram). Живёт только на устройстве, сервер о
/// черновиках не знает. Хранится отдельно для каждого пользователя.
class ChatDraftService {
  ChatDraftService._();
  static final ChatDraftService instance = ChatDraftService._();

  static const _storageKey = 'chat_drafts';

  Map<String, String> _drafts = {};

  /// Ключ хранилища, под которым загружены [_drafts], — `null`, пока не
  /// загружены (или после выхода из аккаунта).
  String? _loadedKey;

  Future<void> ensureLoaded() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await userScopedChatKey(prefs, _storageKey);
    if (_loadedKey == key) return;
    _drafts = {};
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _drafts = decoded.map((k, v) => MapEntry(k, v as String));
      } catch (_) {
        _drafts = {};
      }
    }
    _loadedKey = key;
  }

  /// Выход из аккаунта: черновики остаются на диске под ключом
  /// пользователя, но из памяти уходят.
  void reset() {
    _drafts = {};
    _loadedKey = null;
  }

  Future<String?> getDraft(String chatId) async {
    await ensureLoaded();
    return _drafts[chatId];
  }

  /// Синхронный доступ к уже загруженному кэшу — для применения черновика
  /// к списку чатов сразу после [ensureLoaded] (см. [ChatService]).
  String? draftFor(String chatId) => _drafts[chatId];

  Future<void> setDraft(String chatId, String text) async {
    await ensureLoaded();
    if (text.trim().isEmpty) {
      if (!_drafts.containsKey(chatId)) return;
      _drafts.remove(chatId);
    } else {
      if (_drafts[chatId] == text) return;
      _drafts[chatId] = text;
    }
    final key = _loadedKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(_drafts));
  }

  Future<void> clearDraft(String chatId) => setDraft(chatId, '');
}
