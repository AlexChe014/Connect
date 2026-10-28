import 'dart:io';

import 'package:connect/config/routes/chat_routes.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/chat_file_downloads.dart';
import 'package:connect/services/crash_reporting_service.dart';
import 'package:connect/utils/chat_file_share.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:connect/widgets/chat_download_ring.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

/// Полноэкранный просмотр фото/видео — открывается из вкладки «Медиа»
/// на экране «Настройки чата».
///
/// Видео здесь не проигрывается инлайн (в приложении нет `video_player`) —
/// как и в самом чате (см. `_openChatFile` в chat_conversation_screen.dart),
/// оно открывается через системный шаринг/просмотрщик.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<ChatMessage> items;
  final int initialIndex;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _sharing = false;

  List<ChatMessage> get items => widget.items;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Файл, который сейчас на экране: у сообщения их может быть несколько,
  /// показывается тот, чей URL лежит в `remoteMediaUrl`.
  ChatFile? _currentFile() {
    if (_index < 0 || _index >= items.length) return null;
    final m = items[_index];
    if (m.files.isEmpty) return null;
    for (final f in m.files) {
      if (ChatRoutes.fileUrl(f.id) == m.remoteMediaUrl) return f;
    }
    return m.files.first;
  }

  Future<void> _shareCurrent() async {
    final file = _currentFile();
    if (file == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      await ChatFileShare.share(file);
    } catch (e, st) {
      CrashReportingService.recordNonFatal(e, st, reason: 'chat_media_share');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Не удалось скачать файл')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openVideo(BuildContext context, ChatMessage m) async {
    final candidates = m.files.where((f) => f.isVideo);
    if (candidates.isEmpty) return;
    final ChatFile file = candidates.first;
    try {
      await ChatFileShare.share(file);
    } catch (e, st) {
      CrashReportingService.recordNonFatal(
        e,
        st,
        reason: 'chat_video_download',
      );
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
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
        border: null,
        trailing: _currentFile() == null
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                // Пока файл качается, кнопка показывает прогресс и по тапу
                // останавливает скачивание.
                onPressed: _sharing
                    ? () => ChatFileDownloads.instance.cancel(
                        _currentFile()!.id,
                      )
                    : _shareCurrent,
                child: _sharing
                    ? ChatDownloadRing(
                        fileId: _currentFile()!.id,
                        color: CupertinoColors.white,
                        size: 30,
                        idle: const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        ),
                      )
                    : const Icon(
                        CupertinoIcons.share,
                        color: CupertinoColors.white,
                      ),
              ),
      ),
      child: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final m = items[index];
          if (m.attachmentKind == ChatAttachmentKind.video) {
            final videoFile = m.files.where((f) => f.isVideo).firstOrNull;
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
                  if (videoFile != null) ...[
                    const SizedBox(height: 16),
                    _VideoOpenButton(
                      file: videoFile,
                      onOpen: () => _openVideo(context, m),
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

/// «Открыть» для видео; пока оно качается — кольцо с крестиком и «X из Y»,
/// тап останавливает скачивание.
class _VideoOpenButton extends StatelessWidget {
  const _VideoOpenButton({required this.file, required this.onOpen});

  final ChatFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final downloads = ChatFileDownloads.instance;
    return ValueListenableBuilder<ChatFileDownloadProgress?>(
      valueListenable: downloads.progressOf(file.id),
      builder: (context, progress, _) {
        if (progress == null) {
          return CupertinoButton.filled(
            onPressed: onOpen,
            child: const Text('Открыть'),
          );
        }
        final total = progress.total;
        final received = ChatFile.formatBytes(progress.received);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => downloads.cancel(file.id),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatDownloadRing(
                fileId: file.id,
                color: CupertinoColors.white,
                size: 52,
                idle: const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Text(
                total == null
                    ? received
                    : '$received из ${ChatFile.formatBytes(total)}',
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
