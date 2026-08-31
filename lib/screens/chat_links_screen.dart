import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/cupertino_empty_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

final _urlRegExp = RegExp(r'(https?:\/\/[^\s<>"\)]+)', caseSensitive: false);

class _LinkEntry {
  const _LinkEntry({required this.url, required this.createdAt});

  final String url;
  final DateTime createdAt;
}

/// Ссылки из сообщений чата — доступны через «Настройки чата» → «Ссылки».
class ChatLinksScreen extends StatefulWidget {
  const ChatLinksScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatLinksScreen> createState() => _ChatLinksScreenState();
}

class _ChatLinksScreenState extends State<ChatLinksScreen> {
  bool _loading = true;
  String? _error;
  List<_LinkEntry> _items = const [];

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
      final links = <_LinkEntry>[];
      for (final m in all) {
        final text = m.text;
        if (text == null || text.isEmpty) continue;
        for (final match in _urlRegExp.allMatches(text)) {
          final url = match.group(0)!.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
          links.add(_LinkEntry(url: url, createdAt: m.createdAt));
        }
      }
      links.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _items = links;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить ссылки';
        _loading = false;
      });
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Ссылки'),
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
        icon: CupertinoIcons.link,
        message: 'Здесь появятся ссылки из чата',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        CupertinoListSection.insetGrouped(
          children: _items.map((entry) {
            return CupertinoListTile(
              leading: const Icon(CupertinoIcons.link, color: CupertinoColors.activeBlue),
              title: Text(
                entry.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CupertinoColors.activeBlue),
              ),
              subtitle: Text(
                DateFormat('d MMM yyyy, HH:mm', 'ru_RU').format(entry.createdAt.toLocal()),
              ),
              onTap: () => _open(entry.url),
            );
          }).toList(),
        ),
      ],
    );
  }
}
