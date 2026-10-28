import 'package:connect/services/chat_file_downloads.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator;

/// Кружок скачивания как в Telegram: пока файл качается — кольцо прогресса
/// с крестиком «остановить» внутри, иначе — [idle].
///
/// Нажатие сюда не обрабатывается: отмену делает тот, кто держит тап
/// (карточка файла, кнопка шаринга), через [ChatFileDownloads.cancel].
class ChatDownloadRing extends StatelessWidget {
  const ChatDownloadRing({
    super.key,
    required this.fileId,
    required this.color,
    required this.idle,
    this.size = 40,
  });

  final int fileId;
  final Color color;
  final Widget idle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatFileDownloadProgress?>(
      valueListenable: ChatFileDownloads.instance.progressOf(fileId),
      builder: (context, progress, _) {
        if (progress == null) return idle;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: TweenAnimationBuilder<double>(
                    // Плавно догоняем новое значение, чтобы кольцо не дёргалось
                    // от кусков разного размера.
                    tween: Tween(end: progress.fraction ?? 0),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: progress.fraction == null ? null : value,
                      strokeWidth: 2.5,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
              Icon(CupertinoIcons.xmark, size: size * 0.38, color: color),
            ],
          ),
        );
      },
    );
  }
}
