import 'package:connect/models/chat_message.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/cupertino_empty_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Файлы из чата — доступны через «Настройки чата» → «Файлы».
class ChatFilesScreen extends StatefulWidget {
  const ChatFilesScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatFilesScreen> createState() => _ChatFilesScreenState();
}

class _ChatFilesScreenState extends State<ChatFilesScreen> {
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
      final files =
          all
              .where(
                (m) => m.hasMedia && m.attachmentKind == ChatAttachmentKind.file,
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _items = files;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить файлы';
        _loading = false;
      });
    }
  }

  IconData _iconFor(String? fileName) {
    final ext = (fileName ?? '').split('.').last.toLowerCase();
    if (ext == 'pdf') return CupertinoIcons.doc_richtext;
    if (['zip', 'rar', '7z'].contains(ext)) return CupertinoIcons.archivebox;
    if (['mp3', 'wav', 'm4a', 'aac'].contains(ext)) {
      return CupertinoIcons.music_note;
    }
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
      return CupertinoIcons.videocam_fill;
    }
    return CupertinoIcons.doc_fill;
  }

  Future<void> _open(ChatMessage m) async {
    final url = m.remoteMediaUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Файлы'),
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
        icon: CupertinoIcons.doc,
        message: 'Здесь появятся файлы из чата',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        CupertinoListSection.insetGrouped(
          children: _items.map((m) {
            return CupertinoListTile(
              leading: Icon(_iconFor(m.fileName), color: CupertinoColors.activeBlue),
              title: Text(m.fileName ?? 'Файл'),
              subtitle: Text(
                DateFormat('d MMM yyyy, HH:mm', 'ru_RU').format(m.createdAt.toLocal()),
              ),
              onTap: () => _open(m),
            );
          }).toList(),
        ),
      ],
    );
  }
}
