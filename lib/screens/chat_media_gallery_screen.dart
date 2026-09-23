import 'dart:io';

import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/crash_reporting_service.dart';
import 'package:connect/utils/chat_file_share.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

/// Полноэкранный просмотр фото/видео — открывается из вкладки «Медиа»
/// на экране «Настройки чата».
///
/// Видео здесь не проигрывается инлайн (в приложении нет `video_player`) —
/// как и в самом чате (см. `_openChatFile` в chat_conversation_screen.dart),
/// оно открывается через системный шаринг/просмотрщик.
class MediaViewer extends StatelessWidget {
  const MediaViewer({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<ChatMessage> items;
  final int initialIndex;

  Future<void> _openVideo(BuildContext context, ChatMessage m) async {
    final candidates = m.files.where((f) => f.isVideo);
    if (candidates.isEmpty) return;
    final ChatFile file = candidates.first;
    try {
      await ChatFileShare.share(file);
    } catch (e, st) {
      CrashReportingService.recordNonFatal(e, st, reason: 'chat_video_download');
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось открыть видео')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
        border: null,
      ),
      child: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final m = items[index];
          if (m.attachmentKind == ChatAttachmentKind.video) {
            final hasFile = m.files.any((f) => f.isVideo);
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.play_circle,
                    size: 72,
                    color: CupertinoColors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    m.fileName ?? 'Видео',
                    style: const TextStyle(color: CupertinoColors.white),
                  ),
                  if (hasFile) ...[
                    const SizedBox(height: 16),
                    CupertinoButton.filled(
                      onPressed: () => _openVideo(context, m),
                      child: const Text('Открыть'),
                    ),
                  ],
                ],
              ),
            );
          }

          final localPath = m.localMediaPath;
          return InteractiveViewer(
            child: Center(
              child: localPath != null && localPath.isNotEmpty
                  ? Image.file(File(localPath))
                  : AppNetworkImage(
                      url: m.remoteMediaUrl,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      httpHeaders: ChatFileShare.imageHeaders(m.remoteMediaUrl),
                    ),
            ),
          );
        },
      ),
    );
  }
}
