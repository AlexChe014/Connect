import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/services/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Ход скачивания файла чата: сколько уже пришло и сколько всего.
@immutable
class ChatFileDownloadProgress {
  const ChatFileDownloadProgress(this.received, this.total);

  final int received;

  /// `null` — сервер не сообщил размер, а в сообщении его тоже нет.
  final int? total;

  /// Доля 0…1 или `null`, если размер неизвестен.
  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }
}

/// Скачивания файлов чата — как в Telegram: с прогрессом «X из Y», отменой
/// и кэшем на диске, чтобы повторное открытие не качало файл заново.
///
/// Живёт отдельно от экрана: пузырь с файлом может уйти из ленты при
/// прокрутке, а загрузка продолжится и подхватится, когда он вернётся.
class ChatFileDownloads {
  ChatFileDownloads._();
  static final ChatFileDownloads instance = ChatFileDownloads._();

  final Map<int, ValueNotifier<ChatFileDownloadProgress?>> _progress = {};
  final Map<int, DownloadCancelToken> _tokens = {};
  final Map<int, Future<File?>> _pending = {};

  /// Файлы, которые точно лежат в кэше, — чтобы карточка сразу показала
  /// иконку документа, а не стрелку «скачать».
  final ValueNotifier<Set<int>> downloaded = ValueNotifier(const {});

  /// `null` — файл сейчас не качается.
  ValueListenable<ChatFileDownloadProgress?> progressOf(int fileId) =>
      _progress.putIfAbsent(fileId, () => ValueNotifier(null));

  bool isDownloading(int fileId) => _pending.containsKey(fileId);

  /// Скачивает файл (или берёт из кэша). `null` — скачивание отменили.
  Future<File?> download(ChatFile file) {
    final pending = _pending[file.id];
    if (pending != null) return pending;
    final future = _download(file).whenComplete(() {
      _pending.remove(file.id);
      _tokens.remove(file.id);
      _progress[file.id]?.value = null;
    });
    _pending[file.id] = future;
    return future;
  }

  void cancel(int fileId) => _tokens[fileId]?.cancel();

  /// Проверяет кэш и отмечает файл в [downloaded], если он уже скачан.
  Future<bool> checkCached(ChatFile file) async {
    if (kIsWeb) return false;
    if (downloaded.value.contains(file.id)) return true;
    final local = await _localFileFor(file);
    final exists = await local.exists();
    if (exists) _markDownloaded(file.id);
    return exists;
  }

  /// Выход из аккаунта: обрываем загрузки и стираем скачанное — файлы
  /// прошлого пользователя не должны достаться следующему.
  Future<void> reset() async {
    for (final token in _tokens.values) {
      token.cancel();
    }
    downloaded.value = const {};
    if (kIsWeb) return;
    try {
      final dir = await _rootDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Кэш — не критично: ОС всё равно чистит его сама.
    }
  }

  Future<File?> _download(ChatFile file) async {
    final local = await _localFileFor(file);
    if (await local.exists()) {
      _markDownloaded(file.id);
      return local;
    }

    final token = DownloadCancelToken();
    _tokens[file.id] = token;
    final notifier = _progress.putIfAbsent(file.id, () => ValueNotifier(null));
    final knownSize = file.size > 0 ? file.size : null;
    notifier.value = ChatFileDownloadProgress(0, knownSize);

    try {
      await ApiClient.instance.downloadToFile(
        ChatRoutes.fileUrl(file.id),
        local,
        cancelToken: token,
        onProgress: (received, total) {
          // Content-Length бывает не тем (gzip) или отсутствует — размер
          // из сообщения надёжнее, если он есть.
          var expected = knownSize ?? total;
          if (expected != null && received > expected) expected = received;
          notifier.value = ChatFileDownloadProgress(received, expected);
        },
      );
    } on DownloadCancelledException {
      return null;
    }

    await _throwIfJsonError(file, local);
    _markDownloaded(file.id);
    return local;
  }

  /// Ошибку бэкенд отдаёт JSON-конвертом с HTTP 200 — маленький «файл»
  /// с `success: false` удаляем и показываем как ошибку.
  Future<void> _throwIfJsonError(ChatFile file, File local) async {
    if (file.mimeType.contains('json')) return;
    final length = await local.length();
    if (length >= 4096) return;
    Object? decoded;
    try {
      decoded = jsonDecode(await local.readAsString());
    } catch (_) {
      return; // Не JSON — это и есть файл.
    }
    if (decoded is! Map || decoded['success'] != false) return;
    await local.delete();
    final data = decoded['data'];
    final error = data is Map ? data['error'] : null;
    throw ApiException(
      200,
      error is String && error.trim().isNotEmpty
          ? error
          : 'Не удалось скачать файл',
    );
  }

  void _markDownloaded(int fileId) {
    if (downloaded.value.contains(fileId)) return;
    downloaded.value = {...downloaded.value, fileId};
  }

  Future<Directory> _rootDir() async {
    final base = await getApplicationCacheDirectory();
    return Directory('${base.path}/chat_files');
  }

  /// `chat_files/<id>/<имя>`: папка по id — у разных файлов имена совпадают,
  /// а исходное имя нужно, чтобы шаринг показал его, а не номер.
  Future<File> _localFileFor(ChatFile file) async {
    final dir = await _rootDir();
    return File('${dir.path}/${file.id}/${_safeName(file)}');
  }

  static String _safeName(ChatFile file) {
    var name = file.originalName.trim();
    if (name.isEmpty) name = file.filename.trim();
    if (name.isEmpty) name = 'file';
    return name.replaceAll(RegExp(r'[/\\:\x00]'), '_');
  }
}
