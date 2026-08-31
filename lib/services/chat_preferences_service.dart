import 'package:shared_preferences/shared_preferences.dart';

/// Локальные пользовательские настройки чатов — mute и избранное.
///
/// На сервере нет понятия "чат отключён"/"избранный", поэтому оба флага
/// живут только на устройстве (аналогично [NotificationPreferencesService]
/// для push-топиков). Это значит, что отключение звука не может подавить
/// пуш, который сервер уже отправил другому устройству того же
/// пользователя, — оно лишь скрывает баннер/звук локально.
class ChatPreferencesService {
  ChatPreferencesService._();
  static final ChatPreferencesService instance = ChatPreferencesService._();

  static const _mutedKey = 'chat_muted_ids';
  static const _favoriteKey = 'chat_favorite_ids';

  Set<String> _muted = {};
  Set<String> _favorites = {};
  bool _loaded = false;

  bool isMuted(String chatId) => _muted.contains(chatId);
  bool isFavorite(String chatId) => _favorites.contains(chatId);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _muted = (prefs.getStringList(_mutedKey) ?? const []).toSet();
    _favorites = (prefs.getStringList(_favoriteKey) ?? const []).toSet();
    _loaded = true;
  }

  Future<void> setMuted(String chatId, bool muted) async {
    await ensureLoaded();
    if (muted) {
      _muted.add(chatId);
    } else {
      _muted.remove(chatId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_mutedKey, _muted.toList());
  }

  Future<void> setFavorite(String chatId, bool favorite) async {
    await ensureLoaded();
    if (favorite) {
      _favorites.add(chatId);
    } else {
      _favorites.remove(chatId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoriteKey, _favorites.toList());
  }
}
