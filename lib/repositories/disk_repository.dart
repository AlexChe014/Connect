import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/routes/disk_routes.dart';
import '../models/disk/disk_entry.dart';
import '../models/disk/disk_share.dart';
import '../services/api_client.dart';
import '../services/api_envelope.dart';
import '../services/auth_service.dart';

/// `/api/nextcloud/*` — файловое хранилище («Диск»).
///
/// Эндпоинты `folders/contents` и `info` намеренно не используются: в
/// бэкенде их контроллер резолвит `$user` не через `Auth::user()`, а через
/// контейнер (в роуте нет сегмента `{user}`), из-за чего сервис обращается
/// к пустой модели пользователя. Для просмотра содержимого папки вместо
/// этого используется корректно работающий `files/list?folder=`.
class DiskRepository {
  DiskRepository._();
  static final DiskRepository instance = DiskRepository._();

  /// Лимит сервера на один загружаемый файл (со слов бэкенда — 100 МБ).
  static const maxUploadBytes = 100 * 1024 * 1024;

  static final _davPrefix = RegExp(r'^/*remote\.php/dav/files/[^/]+(/|$)');

  /// `files/list` отдаёт полные WebDAV-пути (`/remote.php/dav/files/user_1/a.jpg`),
  /// а остальные эндпоинты ждут путь относительно корня пользователя (`a.jpg`):
  /// с полным путём бэкенд отвечает 200 и телом в 1 байт вместо файла, а
  /// путь с ведущим `/` вообще режет WAF (403). Поэтому приводим любой путь
  /// к относительному без ведущего слеша.
  static String toApiPath(String path) =>
      path.replaceFirst(_davPrefix, '').replaceFirst(RegExp(r'^/+'), '');

  /// Последнее известное содержимое папок за текущую сессию: при повторном
  /// входе в папку список показывается сразу, а свежий подгружается тихо.
  final Map<String, DiskListing> _listingCache = {};
  int _cacheGeneration = -1;

  /// Сбрасывает кэши, если с прошлого обращения пользователь вышел из
  /// аккаунта: чужие списки и файлы не должны пережить смену сессии.
  void _checkSession() {
    final generation = AuthService.instance.sessionGeneration;
    if (generation == _cacheGeneration) return;
    final isFirstCheck = _cacheGeneration == -1;
    _cacheGeneration = generation;
    _listingCache.clear();
    _selfOwner = null;
    _downloads.clear();
    _previews.clear();
    _noPreview.clear();
    // Файлы с прошлых запусков оставляем — миниатюры не качаются заново.
    // Ключ кэша — полный WebDAV-путь с логином, чужие файлы другому
    // пользователю не попадутся; место в Caches при нехватке чистит iOS.
    if (!isFirstCheck) _clearing = _clearFileCache();
  }

  /// Логин Nextcloud самого пользователя — владелец корня диска.
  String? _selfOwner;

  /// Файлом или папкой с пользователем поделился кто-то другой: Nextcloud
  /// не даёт делиться ими дальше.
  bool isForeign(String? owner) =>
      owner != null && _selfOwner != null && owner != _selfOwner;

  /// Id сотрудника портала по логину Nextcloud (`<префикс>user_<id>`).
  /// Только при том же префиксе, что у самого пользователя: у учёток
  /// с другим префиксом (`user_1` при `prod_user_7`) число может означать
  /// другого человека.
  int? ownerUserId(String owner) {
    final self = _selfOwner;
    if (self == null) return null;
    final pattern = RegExp(r'^(.*)user_(\d+)$');
    final mine = pattern.firstMatch(self);
    final theirs = pattern.firstMatch(owner);
    if (mine == null || theirs == null) return null;
    if (mine.group(1) != theirs.group(1)) return null;
    return int.tryParse(theirs.group(2)!);
  }

  DiskListing? cachedListing(String folder) {
    _checkSession();
    return _listingCache[toApiPath(folder)];
  }

  Future<DiskListing> listFolder(String folder) async {
    _checkSession();
    final apiPath = toApiPath(folder);
    final decoded = await ApiClient.instance.get(
      DiskRoutes.filesListUrl,
      queryParameters: {'folder': apiPath},
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить содержимое папки',
    );
    final listing = DiskListing.fromJson(
      data,
      folder: apiPath,
      normalize: toApiPath,
    );
    _listingCache[apiPath] = listing;
    if (apiPath.isEmpty && listing.folderOwner != null) {
      _selfOwner = listing.folderOwner;
    }
    return listing;
  }

  /// Загружает файл с диска устройства потоком, не читая его в память.
  /// [onProgress] — доля отправленного (0…1).
  Future<void> uploadFile({
    required String filePath,
    required String filename,
    String folder = '',
    void Function(double progress)? onProgress,
  }) async {
    final length = await File(filePath).length();
    final file = await http.MultipartFile.fromPath(
      'file',
      filePath,
      filename: filename,
    );
    final decoded = await ApiClient.instance.postMultipart(
      DiskRoutes.uploadUrl,
      fields: {'folder': toApiPath(folder)},
      files: [file],
      // Минута на ответ сервера плюс время на тело при 32 КБ/с — так
      // крупный файл на медленной сети не обрывается по общему тайм-ауту.
      timeout: Duration(seconds: 60 + length ~/ (32 * 1024)),
      onProgress: onProgress == null
          ? null
          : (sent, total) => onProgress(total > 0 ? sent / total : 0),
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось загрузить файл',
    );
  }

  Future<void> deleteFile(String path) async {
    final decoded = await ApiClient.instance.get(
      DiskRoutes.deleteFileUrl,
      queryParameters: {'path': toApiPath(path)},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось удалить файл',
    );
  }

  Future<void> createFolder(String path, {bool recursive = false}) async {
    final decoded = await ApiClient.instance.post(
      DiskRoutes.createFolderUrl,
      body: {'path': toApiPath(path), 'recursive': recursive},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось создать папку',
    );
  }

  /// Удаляет папку рекурсивно (поведение бэкенда по умолчанию — `recursive`
  /// как query-параметр не передаём: строку `"false"` PHP без строгой
  /// типизации трактует как truthy, так что переключатель всё равно не
  /// сработает так, как ожидается).
  Future<void> deleteFolder(String path) async {
    final decoded = await ApiClient.instance.get(
      DiskRoutes.deleteFolderUrl,
      queryParameters: {'path': toApiPath(path)},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось удалить папку',
    );
  }

  /// Скачанные файлы живут во временной папке, ключ — путь, размер и дата
  /// изменения: изменённый на сервере файл скачается заново.
  final Map<String, Future<File>> _downloads = {};

  /// Очистка кэша после смены сессии; скачивания ждут её, иначе она могла
  /// бы удалить файл, который как раз пишется.
  Future<void>? _clearing;

  Future<Directory> _fileCacheDir() async {
    await _clearing;
    return _rawFileCacheDir();
  }

  Future<Directory> _rawFileCacheDir() async =>
      Directory('${(await getTemporaryDirectory()).path}/disk_files');

  Future<void> _clearFileCache() async {
    try {
      final dir = await _rawFileCacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Временная папка — не страшно, если что-то останется до очистки ОС.
    }
  }

  /// Сторона превью с сервера: миниатюра в списке — 36 pt, до 3x.
  static const previewSize = 128;

  final Map<String, Future<File?>> _previews = {};

  /// Файлы, для которых сервер ответил «превью нет»: до смены сессии
  /// не спрашиваем снова.
  final Set<String> _noPreview = {};

  /// Превью картинки с сервера (кэшируется рядом с файлами). `null` — сервер
  /// превью не отдал (нет его для формата или нет эндпоинта на этом
  /// бэкенде); тогда миниатюру можно сделать из самого файла. Сбой сети
  /// пробрасывается.
  Future<File?> fetchPreview(DiskFile file) {
    _checkSession();
    final key = _cacheKey(file);
    if (_noPreview.contains(key)) return Future.value(null);
    final pending = _previews[key];
    if (pending != null) return pending;
    final future = _fetchPreview(file, key).whenComplete(() {
      _previews.remove(key);
    });
    _previews[key] = future;
    return future;
  }

  Future<File?> _fetchPreview(DiskFile file, String key) async {
    final local = File(
      '${(await _fileCacheDir()).path}/previews/${_fnv1a(key)}_$previewSize',
    );
    if (await local.exists()) return local;
    final List<int> bytes;
    try {
      bytes = await ApiClient.instance.downloadBytes(
        Uri.parse(DiskRoutes.previewUrl)
            .replace(
              queryParameters: {
                'path': toApiPath(file.path),
                'size': '$previewSize',
              },
            )
            .toString(),
      );
    } on ApiException catch (e) {
      // 404 — превью нет; ошибка конвертом с HTTP 200 — тоже не превью.
      if (e.statusCode == 404 || e.statusCode == 200) {
        _noPreview.add(key);
        return null;
      }
      rethrow;
    }
    if (bytes.isEmpty) {
      _noPreview.add(key);
      return null;
    }
    await local.parent.create(recursive: true);
    await local.writeAsBytes(bytes, flush: true);
    return local;
  }

  /// Уже скачанный файл без сети — для миниатюр в списке.
  Future<File?> cachedFile(DiskFile file) async {
    _checkSession();
    final local = await _localFileFor(file);
    return await local.exists() ? local : null;
  }

  /// Локальная копия файла: из кэша или скачанная. Одновременные запросы
  /// одного файла (миниатюра и открытие) делят одно скачивание.
  /// [onProgress] — доля скачанного (0…1), если сервер сообщил размер.
  Future<File> fetchFile(
    DiskFile file, {
    void Function(double progress)? onProgress,
  }) {
    _checkSession();
    final key = _cacheKey(file);
    final pending = _downloads[key];
    if (pending != null) return pending;
    final future = _fetchFile(file, onProgress).whenComplete(() {
      // Блок, а не `=> remove(key)`: `remove` вернул бы этот же future,
      // и `whenComplete` ждал бы сам себя вечно.
      _downloads.remove(key);
    });
    _downloads[key] = future;
    return future;
  }

  Future<File> _fetchFile(
    DiskFile file,
    void Function(double progress)? onProgress,
  ) async {
    final local = await _localFileFor(file);
    if (await local.exists()) return local;

    await ApiClient.instance.downloadToFile(
      Uri.parse(
        DiskRoutes.downloadUrl,
      ).replace(queryParameters: {'path': toApiPath(file.path)}).toString(),
      local,
      onProgress: (received, total) {
        final expected = total ?? file.size;
        if (onProgress != null && expected != null && expected > 0) {
          onProgress((received / expected).clamp(0, 1));
        }
      },
    );

    // Ошибку бэкенд отдаёт тем же JSON-конвертом с HTTP 200 — маленький
    // «файл», начинающийся с `{`, проверяем, прежде чем считать его файлом.
    final length = await local.length();
    if (length < 4096 && !_looksLikeJson(file)) {
      Object? decoded;
      try {
        decoded = jsonDecode(await local.readAsString());
      } catch (_) {
        // Не JSON — это и есть файл.
      }
      if (decoded is Map<String, dynamic> && decoded['success'] == false) {
        await local.delete();
        ApiEnvelope.unwrapData(
          decoded,
          defaultErrorMessage: 'Не удалось скачать файл',
        );
      }
    }
    return local;
  }

  /// Настоящий `.json` на «Диске» нельзя путать с ошибкой сервера.
  static bool _looksLikeJson(DiskFile file) =>
      file.name.toLowerCase().endsWith('.json') ||
      (file.mime?.contains('json') ?? false);

  String _cacheKey(DiskFile file) =>
      '${file.path}|${file.size}|${file.lastModified?.millisecondsSinceEpoch}';

  Future<File> _localFileFor(DiskFile file) async {
    final dir = await _fileCacheDir();
    // Имя файла сохраняем как есть: по расширению его открывают QuickLook
    // и «Поделиться», а уникальность даёт папка с хэшем ключа.
    final safeName = file.name.replaceAll(RegExp(r'[/\\:]'), '_');
    return File('${dir.path}/${_fnv1a(_cacheKey(file))}/$safeName');
  }

  /// FNV-1a (64 бита) — стабильный между запусками хэш для имени папки.
  static String _fnv1a(String input) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  Future<Map<String, dynamic>> createPublicLink(
    String path, {
    String? password,
    String? expireDate,
    String? note,
  }) async {
    final decoded = await ApiClient.instance.post(
      DiskRoutes.createPublicShareUrl,
      body: {
        'path': toApiPath(path),
        if (password != null && password.isNotEmpty) 'password': password,
        if (expireDate != null && expireDate.isNotEmpty)
          'expire_date': expireDate,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось создать публичную ссылку',
    );
  }

  Future<void> shareWithUser(String path, int userId) async {
    final decoded = await ApiClient.instance.post(
      DiskRoutes.shareWithUserUrl,
      body: {'path': toApiPath(path), 'share_with': userId},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось поделиться файлом',
    );
  }

  Future<List<DiskShare>> listShares(String path) async {
    final decoded = await ApiClient.instance.get(
      DiskRoutes.listSharesUrl,
      queryParameters: {'path': toApiPath(path)},
    );
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить список доступов',
    );
    return list
        .whereType<Map>()
        .map((e) => DiskShare.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<void> deleteShare(int shareId) async {
    final decoded = await ApiClient.instance.get(
      DiskRoutes.deleteShareUrl,
      queryParameters: {'share_id': shareId.toString()},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось отозвать доступ',
    );
  }
}
