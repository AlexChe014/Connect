import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';

/// Достаёт файл документа из ответа 1С (`/documents/get/file/{service}`) и
/// открывает системный шаринг. Ответ 1С не документирован (см. память
/// "Favorites API docs mismatch" — api-docs.json для этого модуля тоже не
/// заслуживает доверия), поэтому распознаём несколько правдоподобных форм:
/// base64-содержимое в одном из типичных полей либо прямую ссылку на файл.
class DocumentFileShare {
  DocumentFileShare._();

  static const _base64Keys = [
    'file',
    'data',
    'content',
    'base64',
    'filedata',
    'FileData',
  ];

  static const _urlKeys = ['url', 'link', 'fileurl', 'downloadurl'];

  static Future<void> share(
    Map<String, dynamic> response, {
    required String fallbackName,
  }) async {
    final rawName = (response['namefile'] ?? response['filename'] ?? fallbackName)
        .toString()
        .trim();
    final fileName = rawName.isEmpty ? 'Файл' : rawName;

    for (final key in _base64Keys) {
      final raw = response[key];
      if (raw is String && raw.trim().isNotEmpty) {
        final bytes = _tryDecodeBase64(raw);
        if (bytes != null) {
          await _shareBytes(bytes, fileName);
          return;
        }
      }
    }

    for (final key in _urlKeys) {
      final raw = response[key];
      if (raw is String && raw.trim().isNotEmpty) {
        final uri = Uri.tryParse(raw.trim());
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
    }

    throw ApiException(200, 'Сервер не вернул содержимое файла');
  }

  static Uint8List? _tryDecodeBase64(String raw) {
    var value = raw.trim();
    final commaIndex = value.indexOf(',');
    if (value.startsWith('data:') && commaIndex != -1) {
      value = value.substring(commaIndex + 1);
    }
    try {
      return base64Decode(base64.normalize(value));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _shareBytes(Uint8List bytes, String name) async {
    if (kIsWeb) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile.fromData(bytes, name: name)]),
      );
      return;
    }
    final path = '${Directory.systemTemp.path}/$name';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }
}
