import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connect/models/chat.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';

/// Копия чатов на телефоне — чтобы список и переписка открывались сразу,
/// а свежие данные с сервера подтягивались поверх (как в Telegram).
///
/// Список чатов сохраняется из памяти приложения (с уже прочитанными,
/// пришедшими по сокету и т.п.), а сообщения — сырым ответом сервера на
/// первую страницу: его разбирает тот же [ChatMapper], что и живой ответ.
///
/// Лежит в Caches (не попадает в резервные копии, система может сама
/// очистить при нехватке места), отдельно для каждого пользователя;
/// при выходе из аккаунта удаляется целиком.
class ChatCacheService {
  ChatCacheService._();
  static final ChatCacheService instance = ChatCacheService._();

  /// Формат файлов — при несовместимой смене просто поднять.
  static const _version = 1;

  /// Сколько последних открытых чатов хранить с перепиской.
  static const _maxMessageFiles = 40;

  static const _chatsFile = 'chats.json';
  static const _messagesPrefix = 'messages_';

  Directory? _root;
  Timer? _saveChatsDebounce;
  String? _lastChatsJson;
  final Map<String, String> _lastMessagesJson = {};

  /// Растёт при каждом [clear] — запись, начатая до выхода из аккаунта,
  /// не должна воскресить удалённый кэш.
  int _generation = 0;

  Future<Directory> _rootDir() async => _root ??= Directory(
    '${(await getApplicationCacheDirectory()).path}/chat_cache',
  );

  Future<Directory> _userDir(int userId) async =>
      Directory('${(await _rootDir()).path}/v${_version}_u$userId');

  Future<List<Chat>?> readChats(int userId) async {
    try {
      final file = File('${(await _userDir(userId)).path}/$_chatsFile');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List;
      _lastChatsJson = raw;
      return list.whereType<Map<String, dynamic>>().map(_chatFromJson).toList();
    } catch (e) {
      AppLogger.d(
        'ChatCache: не удалось прочитать список чатов',
        name: 'chat.cache',
        error: e,
      );
      return null;
    }
  }

  /// Изменения списка идут пачками (сокет, прочтения) — пишем не чаще
  /// раза в секунду и только если что-то поменялось.
  void scheduleSaveChats(int userId, List<Chat> chats) {
    _saveChatsDebounce?.cancel();
    final generation = _generation;
    _saveChatsDebounce = Timer(const Duration(seconds: 1), () async {
      final json = jsonEncode(chats.map(_chatToJson).toList());
      if (json == _lastChatsJson) return;
      _lastChatsJson = json;
      await _write(userId, _chatsFile, json, generation);
    });
  }

  /// Сырой ответ сервера на первую страницу сообщений чата.
  Future<Map<String, dynamic>?> readMessagesPage(
    int userId,
    String chatId,
  ) async {
    try {
      final file = File(
        '${(await _userDir(userId)).path}/$_messagesPrefix$chatId.json',
      );
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      _lastMessagesJson[chatId] = raw;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.d(
        'ChatCache: не удалось прочитать сообщения $chatId',
        name: 'chat.cache',
        error: e,
      );
      return null;
    }
  }

  Future<void> saveMessagesPage(
    int userId,
    String chatId,
    Map<String, dynamic> decoded,
  ) async {
    final generation = _generation;
    final json = jsonEncode(decoded);
    if (_lastMessagesJson[chatId] == json) return;
    _lastMessagesJson[chatId] = json;
    if (await _write(
      userId,
      '$_messagesPrefix$chatId.json',
      json,
      generation,
    )) {
      await _evictOldMessages(userId);
    }
  }

  Future<void> removeMessages(int userId, String chatId) async {
    _lastMessagesJson.remove(chatId);
    try {
      final file = File(
        '${(await _userDir(userId)).path}/$_messagesPrefix$chatId.json',
      );
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Выход из аккаунта: на телефоне не остаётся чужой переписки.
  Future<void> clear() async {
    _generation++;
    _saveChatsDebounce?.cancel();
    _lastChatsJson = null;
    _lastMessagesJson.clear();
    try {
      final root = await _rootDir();
      if (await root.exists()) await root.delete(recursive: true);
    } catch (e) {
      AppLogger.d(
        'ChatCache: не удалось очистить кэш',
        name: 'chat.cache',
        error: e,
      );
    }
  }

  Future<bool> _write(
    int userId,
    String name,
    String content,
    int generation,
  ) async {
    try {
      final dir = await _userDir(userId);
      if (generation != _generation) return false;
      await dir.create(recursive: true);
      // Через временный файл: если приложение убьют посреди записи,
      // останется прошлая целая копия, а не обрезанный JSON.
      final tmp = File('${dir.path}/$name.tmp');
      await tmp.writeAsString(content, flush: true);
      if (generation != _generation) {
        await tmp.delete();
        return false;
      }
      await tmp.rename('${dir.path}/$name');
      return true;
    } catch (e) {
      AppLogger.d(
        'ChatCache: не удалось сохранить $name',
        name: 'chat.cache',
        error: e,
      );
      return false;
    }
  }

  Future<void> _evictOldMessages(int userId) async {
    try {
      final dir = await _userDir(userId);
      final files = await dir
          .list()
          .where(
            (e) =>
                e is File &&
                e.uri.pathSegments.last.startsWith(_messagesPrefix) &&
                e.path.endsWith('.json'),
          )
          .cast<File>()
          .toList();
      if (files.length <= _maxMessageFiles) return;
      final withTime = [
        for (final f in files) (file: f, at: await f.lastModified()),
      ]..sort((a, b) => b.at.compareTo(a.at));
      for (final old in withTime.skip(_maxMessageFiles)) {
        await old.file.delete();
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _chatToJson(Chat c) => {
    'id': c.id,
    'title': c.title,
    'avatarPath': c.avatarPath,
    'avatarUrl': c.avatarUrl,
    'peerAvatarPath': c.peerAvatarPath,
    'peerAvatarUrl': c.peerAvatarUrl,
    'peerUserId': c.peerUserId,
    'isGroup': c.isGroup,
    'description': c.description,
    'creatorId': c.creatorId,
    'members': [
      for (final m in c.members)
        {
          'userId': m.userId,
          'displayName': m.displayName,
          'avatarUrl': m.avatarUrl,
          'isAdmin': m.isAdmin,
          'isOnline': m.isOnline,
        },
    ],
    'lastMessagePreview': c.lastMessagePreview,
    'lastMessageAt': c.lastMessageAt?.toIso8601String(),
    'lastMessageIsOutgoing': c.lastMessageIsOutgoing,
    'lastMessageReadByRecipients': c.lastMessageReadByRecipients,
    'unreadCount': c.unreadCount,
    'isPinned': c.isPinned,
    // isMuted / isFavorite / draftText не храним — их источник
    // ChatPreferencesService и ChatDraftService.
  };

  static Chat _chatFromJson(Map<String, dynamic> j) => Chat(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    avatarPath: j['avatarPath'] as String?,
    avatarUrl: j['avatarUrl'] as String?,
    peerAvatarPath: j['peerAvatarPath'] as String?,
    peerAvatarUrl: j['peerAvatarUrl'] as String?,
    peerUserId: j['peerUserId'] as int?,
    isGroup: j['isGroup'] as bool? ?? false,
    description: j['description'] as String?,
    creatorId: j['creatorId'] as int?,
    members: [
      for (final m in (j['members'] as List? ?? const []).whereType<Map>())
        ChatMemberSummary(
          userId: m['userId'] as int,
          displayName: m['displayName'] as String? ?? '',
          avatarUrl: m['avatarUrl'] as String?,
          isAdmin: m['isAdmin'] as bool? ?? false,
          isOnline: m['isOnline'] as bool?,
        ),
    ],
    lastMessagePreview: j['lastMessagePreview'] as String?,
    lastMessageAt: DateTime.tryParse(j['lastMessageAt'] as String? ?? ''),
    lastMessageIsOutgoing: j['lastMessageIsOutgoing'] as bool? ?? false,
    lastMessageReadByRecipients:
        j['lastMessageReadByRecipients'] as bool? ?? false,
    unreadCount: j['unreadCount'] as int? ?? 0,
    isPinned: j['isPinned'] as bool? ?? false,
  );
}
