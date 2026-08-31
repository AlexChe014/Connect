import 'dart:io';

import 'package:connect/models/chat_message.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:connect/widgets/cupertino_empty_state.dart';
import 'package:flutter/cupertino.dart';

/// Фото из чата — доступны через «Настройки чата» → «Медиа».
class ChatMediaScreen extends StatefulWidget {
  const ChatMediaScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> {
  bool _loading = true;
  String? _error;
  List<ChatMessage> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ChatService.instance.selfUserId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Не удалось определить текущего пользователя';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await ChatRepository.instance.getAllMessages(
        int.parse(widget.chatId),
        currentUserId: userId,
      );
      final media =
          all
              .where(
                (m) => m.hasMedia && m.attachmentKind == ChatAttachmentKind.image,
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _items = media;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить медиа';
        _loading = false;
      });
    }
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => _MediaViewer(items: _items, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Медиа'),
        border: null,
      ),
      child: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    if (_error != null) {
      return CupertinoEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _error!,
      );
    }
    if (_items.isEmpty) {
      return const CupertinoEmptyState(
        icon: CupertinoIcons.photo_on_rectangle,
        message: 'Здесь появятся фото из чата',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final m = _items[index];
        final localPath = m.localMediaPath;
        return GestureDetector(
          onTap: () => _openViewer(index),
          child:
              localPath != null && localPath.isNotEmpty
                  ? Image.file(File(localPath), fit: BoxFit.cover)
                  : AppNetworkImage(url: m.remoteMediaUrl, fit: BoxFit.cover),
        );
      },
    );
  }
}

class _MediaViewer extends StatelessWidget {
  const _MediaViewer({required this.items, required this.initialIndex});

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
