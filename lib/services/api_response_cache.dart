import 'dart:convert';
import 'dart:io';

import 'package:connect/services/auth_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';

/// Последние ответы сервера на телефоне — чтобы экран открывался сразу
/// с прошлыми данными, а свежие подтягивались поверх. Хранится ответ как
/// есть: его разбирает тот же код репозитория, что и живой.
///
/// Лежит в Caches (не попадает в резервные копии, система может сама
/// очистить при нехватке места), отдельно для каждого пользователя;
/// при выходе из аккаунта удаляется ([clearAll]).
class ApiResponseCache {
  ApiResponseCache(
    this.name, {
    this.maxEntriesPerPrefix = const {},
    this.maxEntryBytes = 1024 * 1024,
  }) {
    _instances.add(this);
  }

  static final _instances = <ApiResponseCache>[];

  /// Выход из аккаунта: удаляем кэши всех разделов разом — в том числе
  /// тех, что в этом запуске ещё не открывались.
  static Future<void> clearAll() async {
    for (final cache in _instances) {
      cache._generation++;
    }
    try {
      final base = await getApplicationCacheDirectory();
      final root = Directory('${base.path}/api_cache');
      if (await root.exists()) await root.delete(recursive: true);
    } catch (e) {
      AppLogger.d('ApiCache: не очистить', error: e);
    }
  }

  /// Папка этого кэша, например `mail`.
  final String name;

  /// Сколько последних записей хранить для ключей с данным префиксом
  /// (например, не больше 30 писем `message_`) — остальные без ограничения.
  final Map<String, int> maxEntriesPerPrefix;

  /// Ответы больше этого не сохраняем (письма со встроенными картинками).
  final int maxEntryBytes;

  /// Растёт при каждом [clear] — запись, начатая до выхода из аккаунта,
  /// не должна воскресить удалённый кэш.
  int _generation = 0;

  Future<Directory?> _userDir() async {
    final user = await AuthService.instance.getStoredUser();
    final id = user?['id']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    final base = await getApplicationCacheDirectory();
    return Directory('${base.path}/api_cache/$name/u$id');
  }

  Future<Map<String, dynamic>?> read(String key) async {
    try {
      final dir = await _userDir();
      if (dir == null) return null;
      final file = File('${dir.path}/$key.json');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      AppLogger.d('ApiCache[$name]: не прочитать $key', error: e);
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> decoded) async {
    final generation = _generation;
    try {
      final content = jsonEncode(decoded);
      if (content.length > maxEntryBytes) return;
      final dir = await _userDir();
      if (dir == null || generation != _generation) return;
      await dir.create(recursive: true);
      // Через временный файл: если приложение убьют посреди записи,
      // останется прошлая целая копия, а не обрезанный JSON.
      final tmp = File('${dir.path}/$key.json.tmp');
      await tmp.writeAsString(content, flush: true);
      if (generation != _generation) {
        await tmp.delete();
        return;
      }
      await tmp.rename('${dir.path}/$key.json');
      for (final entry in maxEntriesPerPrefix.entries) {
        if (key.startsWith(entry.key)) {
          await _evict(dir, entry.key, entry.value);
        }
      }
    } catch (e) {
      AppLogger.d('ApiCache[$name]: не сохранить $key', error: e);
    }
  }

  Future<void> remove(String key) async {
    try {
      final dir = await _userDir();
      if (dir == null) return;
      final file = File('${dir.path}/$key.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _evict(Directory dir, String prefix, int keep) async {
    final files = await dir
        .list()
        .where((e) {
          final name = e.uri.pathSegments.last;
          return e is File && name.startsWith(prefix) && name.endsWith('.json');
        })
        .cast<File>()
        .toList();
    if (files.length <= keep) return;
    final withTime = [
      for (final f in files) (file: f, at: await f.lastModified()),
    ]..sort((a, b) => b.at.compareTo(a.at));
    for (final old in withTime.skip(keep)) {
      await old.file.delete();
    }
  }
}
