import 'dart:io';

import 'package:connect/models/chat_message.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:flutter/cupertino.dart';

/// Полноэкранный просмотр фото/видео — открывается из вкладки «Медиа»
/// на экране «Настройки чата».
class MediaViewer extends StatelessWidget {
  const MediaViewer({super.key, required this.items, required this.initialIndex});

  final List<ChatMessage> items;
  final int initialIndex;

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
          final localPath = m.localMediaPath;
          return InteractiveViewer(
            child: Center(
              child:
                  localPath != null && localPath.isNotEmpty
                      ? Image.file(File(localPath))
                      : AppNetworkImage(
                        url: m.remoteMediaUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
            ),
          );
        },
      ),
    );
  }
}
