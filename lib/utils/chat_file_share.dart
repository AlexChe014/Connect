import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/chat_file_downloads.dart';
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

  /// Скачивает через [ChatFileDownloads] — с прогрессом, отменой и кэшем.
  /// Если скачивание отменили, шаринг не открывается.
  static Future<void> share(ChatFile file) async {
    if (kIsWeb) {
      final bytes = await ChatRepository.instance.downloadFile(file.id);
      final name = file.originalName.trim().isEmpty
          ? (file.filename.trim().isEmpty ? 'file' : file.filename)
          : file.originalName;
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

    final local = await ChatFileDownloads.instance.download(file);
    if (local == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(local.path)]));
  }
}
