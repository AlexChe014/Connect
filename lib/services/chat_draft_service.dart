import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Локальные черновики сообщений в чатах — текст композера сохраняется
/// при выходе из чата и подставляется обратно при повторном открытии
/// (как в WhatsApp/Telegram). Живёт только на устройстве, сервер о
/// черновиках не знает.
class ChatDraftService {
  ChatDraftService._();
  static final ChatDraftService instance = ChatDraftService._();

  static const _storageKey = 'chat_drafts';

  Map<String, String> _drafts = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _drafts = decoded.map((k, v) => MapEntry(k, v as String));
      } catch (_) {
        _drafts = {};
      }
    }
    _loaded = true;
  }

  Future<String?> getDraft(String chatId) async {
    await ensureLoaded();
    return _drafts[chatId];
  }

  Future<void> setDraft(String chatId, String text) async {
    await ensureLoaded();
    if (text.trim().isEmpty) {
      if (!_drafts.containsKey(chatId)) return;
      _drafts.remove(chatId);
    } else {
      if (_drafts[chatId] == text) return;
      _drafts[chatId] = text;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_drafts));
  }

  Future<void> clearDraft(String chatId) => setDraft(chatId, '');
}
