import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/routes/disk_routes.dart';
import '../models/disk/disk_entry.dart';
import '../models/disk/disk_share.dart';
import '../services/api_client.dart';
import '../services/api_envelope.dart';

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

  Future<DiskListing> listFolder(String folder) async {
    final decoded = await ApiClient.instance.get(
      DiskRoutes.filesListUrl,
      queryParameters: {'folder': folder},
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить содержимое папки',
    );
    return DiskListing.fromJson(data);
  }

  Future<void> uploadFile({
    required List<int> bytes,
    required String filename,
    String folder = '',
  }) async {
    final decoded = await ApiClient.instance.postMultipart(
      DiskRoutes.uploadUrl,
      fields: {'folder': folder},
      files: [http.MultipartFile.fromBytes('file', bytes, filename: filename)],
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось загрузить файл',
    );
  }

  Future<void> deleteFile(String path) async {
    final decoded = await ApiClient.instance.get(
      DiskRoutes.deleteFileUrl,
      queryParameters: {'path': path},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось удалить файл',
    );
  }

  Future<void> createFolder(String path, {bool recursive = false}) async {
    final decoded = await ApiClient.instance.post(
      DiskRoutes.createFolderUrl,
      body: {'path': path, 'recursive': recursive},
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
      queryParameters: {'path': path},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось удалить папку',
    );
  }

  /// Возвращает байты файла. Бэкенд отдаёт бинарный поток при успехе, но
  /// при ошибке (даже с HTTP 200) — тот же JSON-конверт `{success:false}`,
  /// поэтому перед возвратом байтов проверяем, не JSON ли это ошибка.
  Future<Uint8List> downloadFile(String path) async {
    final bytes = await ApiClient.instance.downloadBytes(
      Uri.parse(
        DiskRoutes.downloadUrl,
      ).replace(queryParameters: {'path': path}).toString(),
    );

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic> && decoded['success'] == false) {
        ApiEnvelope.unwrapData(
          decoded,
          defaultErrorMessage: 'Не удалось скачать файл',
        );
      }
    } catch (_) {
      // Бинарные данные не декодируются как UTF-8 JSON — это и есть файл.
    }

    return Uint8List.fromList(bytes);
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
        'path': path,
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
      body: {'path': path, 'share_with': userId},
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось поделиться файлом',
    );
  }

  Future<List<DiskShare>> listShares(String path) async {
    final decoded = await ApiClient.instance.get(
      DiskRoutes.listSharesUrl,
      queryParameters: {'path': path},
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
