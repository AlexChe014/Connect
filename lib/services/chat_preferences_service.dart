import 'package:connect/utils/chat_storage_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальные пользовательские настройки чатов — mute, избранное и
/// закрепление строки «Согласование».
///
/// На сервере нет понятия "чат отключён"/"избранный", поэтому оба флага
/// живут только на устройстве (аналогично [NotificationPreferencesService]
/// для push-топиков), отдельно для каждого пользователя. Это значит, что
/// отключение звука не может подавить пуш, который сервер уже отправил
/// другому устройству того же пользователя, — оно лишь скрывает
/// баннер/звук локально.
class ChatPreferencesService {
  ChatPreferencesService._();
  static final ChatPreferencesService instance = ChatPreferencesService._();

  static const _mutedKey = 'chat_muted_ids';
  static const _favoriteKey = 'chat_favorite_ids';
  static const _approvalsPinnedKey = 'chat_approvals_pinned';

  Set<String> _muted = {};
  Set<String> _favorites = {};
  bool _approvalsPinned = true;

  /// Ключи хранилища, под которыми загружены настройки, — `null`, пока не
  /// загружены (или после выхода из аккаунта).
  _Keys? _keys;

  /// Закреплена ли системная строка «Согласование» (по умолчанию — да).
  bool get approvalsPinned => _approvalsPinned;

  bool isMuted(String chatId) => _muted.contains(chatId);
  bool isFavorite(String chatId) => _favorites.contains(chatId);

  Future<void> ensureLoaded() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = _Keys(
      muted: await userScopedChatKey(prefs, _mutedKey),
      favorite: await userScopedChatKey(prefs, _favoriteKey),
      approvalsPinned: await userScopedChatKey(prefs, _approvalsPinnedKey),
    );
    if (_keys?.muted == keys.muted) return;
    _muted = (prefs.getStringList(keys.muted) ?? const []).toSet();
    _favorites = (prefs.getStringList(keys.favorite) ?? const []).toSet();
    _approvalsPinned = prefs.getBool(keys.approvalsPinned) ?? true;
    _keys = keys;
  }

  /// Выход из аккаунта: настройки остаются на диске под ключом
  /// пользователя, но из памяти уходят.
  void reset() {
    _muted = {};
    _favorites = {};
    _approvalsPinned = true;
    _keys = null;
  }

  Future<void> setMuted(String chatId, bool muted) async {
    await ensureLoaded();
    if (muted) {
      _muted.add(chatId);
    } else {
      _muted.remove(chatId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keys!.muted, _muted.toList());
  }

  Future<void> setApprovalsPinned(bool pinned) async {
    await ensureLoaded();
    _approvalsPinned = pinned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keys!.approvalsPinned, pinned);
  }

  Future<void> setFavorite(String chatId, bool favorite) async {
    await ensureLoaded();
    if (favorite) {
      _favorites.add(chatId);
    } else {
      _favorites.remove(chatId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keys!.favorite, _favorites.toList());
  }
}

class _Keys {
  const _Keys({
    required this.muted,
    required this.favorite,
    required this.approvalsPinned,
  });

  final String muted;
  final String favorite;
  final String approvalsPinned;
}
