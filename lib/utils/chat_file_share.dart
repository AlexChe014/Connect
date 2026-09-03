import 'dart:io';

import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/services/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Скачивает файл чата и открывает системный шаринг.
class ChatFileShare {
  ChatFileShare._();

  static Map<String, String>? imageHeaders(String? url) {
    if (url == null || !url.contains('/chat/files/')) return null;
    final headers = ApiClient.instance.authHeaders;
    return headers.isEmpty ? null : headers;
  }

  static Future<void> share(ChatFile file) async {
    final bytes = await ChatRepository.instance.downloadFile(file.id);
    final name = file.originalName.trim().isEmpty
        ? (file.filename.trim().isEmpty ? 'file' : file.filename)
        : file.originalName;

    if (kIsWeb) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: name,
              mimeType: file.mimeType,
            ),
          ],
        ),
      );
      return;
    }

    final path = '${Directory.systemTemp.path}/$name';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }
}
