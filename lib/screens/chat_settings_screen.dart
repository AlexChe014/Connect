import 'dart:io';

import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/screens/chat_media_gallery_screen.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/app_network_image.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:connect/widgets/cupertino_empty_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar, showModalBottomSheet;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

final _urlRegExp = RegExp(r'(https?:\/\/[^\s<>"\)]+)', caseSensitive: false);

class _LinkEntry {
  const _LinkEntry({required this.url, required this.createdAt});

  final String url;
  final DateTime createdAt;
}

class _FileAccent {
  const _FileAccent(this.icon, this.color, this.label);

  final IconData icon;
  final Color color;
  final String label;
}

String _domainFor(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host.replaceFirst(RegExp(r'^www\.'), '');
}

/// Заголовок для группировки списка по дате — «Сегодня» / «Вчера» / дата.
String _dateSectionLabel(DateTime date) {
  final now = DateTime.now();
  final local = date.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  switch (today.difference(day).inDays) {
    case 0:
      return 'Сегодня';
    case 1:
      return 'Вчера';
  }
  final pattern = local.year == now.year ? 'd MMMM' : 'd MMMM yyyy';
  return DateFormat(pattern, 'ru_RU').format(local);
}

Map<String, List<T>> _groupByDate<T>(
  List<T> items,
  DateTime Function(T) dateOf,
) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    (groups[_dateSectionLabel(dateOf(item))] ??= []).add(item);
  }
  return groups;
}

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key, required this.chat});

  final Chat chat;

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  final _service = ChatService.instance;
  late Chat _chat;
  bool _busy = false;

  int _galleryTab = 0;
  bool _galleryLoading = true;
  String? _galleryError;
  List<ChatMessage> _media = const [];
  List<ChatMessage> _files = const [];
  List<_LinkEntry> _links = const [];

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _service.addListener(_onService);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
    _loadGallery();
  }

  @override
  void dispose() {
    _service.removeListener(_onService);
    super.dispose();
  }

  void _onService() {
    if (!mounted) return;
    final updated = _service.chatById(widget.chat.id);
    if (updated != null) {
      setState(() => _chat = updated);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await _service.refreshChatDetails(widget.chat.id);
    if (mounted) setState(() => _busy = false);
  }

  bool get _canManage => _chat.canManage(_service.selfUserId);

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editChat() async {
    final titleCtrl = TextEditingController(text: _chat.title);
    final descCtrl = TextEditingController(text: _chat.description ?? '');

    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Редактировать чат'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: titleCtrl,
                placeholder: 'Название',
                autofocus: true,
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: descCtrl,
                placeholder: 'Описание',
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.updateChat(
      _chat.id,
      title: titleCtrl.text.trim(),
      description: descCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack(success ? 'Чат обновлён' : 'Не удалось обновить чат');
  }

  Future<void> _addMembers() async {
    await _service.loadContacts();
    if (!mounted) return;

    final existingIds = _chat.members.map((m) => m.userId).toSet();
    final candidates = _service.contacts
        .where((c) => c.userId > 0 && !existingIds.contains(c.userId))
        .toList();

    if (candidates.isEmpty) {
      _showSnack('Нет доступных контактов для добавления');
      return;
    }

    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: _AddMembersSheet(candidates: candidates),
        );
      },
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.addMembers(_chat.id, selected.toList());
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack(
      success ? 'Участники добавлены' : 'Не удалось добавить участников',
    );
  }

  Future<void> _removeMember(ChatMemberSummary member) async {
    final selfId = _service.selfUserId;
    if (selfId == null) return;
    if (member.userId == _chat.creatorId) return;

    final isSelf = member.userId == selfId;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(isSelf ? 'Выйти из чата?' : 'Удалить участника?'),
        content: Text(
          isSelf
              ? 'Вы покинете этот чат.'
              : 'Удалить ${member.displayName} из чата?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(isSelf ? 'Выйти' : 'Удалить'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.removeMember(_chat.id, member.userId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (isSelf && success) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    _showSnack(
      success
          ? 'Участник удалён'
          : (_service.lastActionError ?? 'Не удалось удалить участника'),
    );
  }

  Future<void> _deleteChat() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить чат?'),
        content: const Text(
          'Чат будет помечен как удалённый для всех участников.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final success = await _service.deleteChat(_chat.id);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!success) {
      _showSnack(_service.lastActionError ?? 'Не удалось удалить чат');
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _call() async {
    if (ChatCallService.instance.isStartingCall) return;

    try {
      await ChatCallService.instance.startCallFromChat(_chat);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось начать видеозвонок';
      _showSnack(message);
    }
  }

  void _openSearch() {
    Navigator.of(context).pop('search');
  }

  Future<void> _loadGallery() async {
    final userId = _service.selfUserId;
    if (userId == null) {
      setState(() {
        _galleryLoading = false;
        _galleryError = 'Не удалось определить текущего пользователя';
      });
      return;
    }
    setState(() {
      _galleryLoading = true;
      _galleryError = null;
    });
    try {
      final all = await ChatRepository.instance.getAllMessages(
        int.parse(_chat.id),
        currentUserId: userId,
      );
      final media =
          all
              .where(
                (m) =>
                    m.hasMedia &&
                    (m.attachmentKind == ChatAttachmentKind.image ||
                        m.attachmentKind == ChatAttachmentKind.video),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final files =
          all
              .where(
                (m) => m.hasMedia && m.attachmentKind == ChatAttachmentKind.file,
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
        _media = media;
        _files = files;
        _links = links;
        _galleryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _galleryError = 'Не удалось загрузить данные';
        _galleryLoading = false;
      });
    }
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => MediaViewer(items: _media, initialIndex: index),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  _FileAccent _fileAccentFor(String? fileName) {
    final ext = (fileName ?? '').split('.').last.toLowerCase();
    if (ext == 'pdf') {
      return const _FileAccent(
        CupertinoIcons.doc_richtext,
        CupertinoColors.systemRed,
        'PDF',
      );
    }
    if (['zip', 'rar', '7z'].contains(ext)) {
      return const _FileAccent(
        CupertinoIcons.archivebox,
        CupertinoColors.systemOrange,
        'Архив',
      );
    }
    if (['mp3', 'wav', 'm4a', 'aac'].contains(ext)) {
      return const _FileAccent(
        CupertinoIcons.music_note,
        CupertinoColors.systemPink,
        'Аудио',
      );
    }
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
      return const _FileAccent(
        CupertinoIcons.videocam_fill,
        CupertinoColors.systemPurple,
        'Видео',
      );
    }
    if (['doc', 'docx', 'txt', 'rtf'].contains(ext)) {
      return const _FileAccent(
        CupertinoIcons.doc_text_fill,
        CupertinoColors.systemBlue,
        'Документ',
      );
    }
    return const _FileAccent(
      CupertinoIcons.doc_fill,
      CupertinoColors.systemGrey,
      'Файл',
    );
  }

  Future<void> _openFile(ChatMessage m) async {
    final url = m.remoteMediaUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildGalleryTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: _galleryTab,
        backgroundColor: CupertinoColors.systemGrey5.resolveFrom(context),
        thumbColor: CupertinoColors.systemBackground.resolveFrom(context),
        onValueChanged: (value) {
          if (value != null) setState(() => _galleryTab = value);
        },
        children: const {
          0: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Медиа'),
          ),
          1: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Файлы'),
          ),
          2: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Ссылки'),
          ),
        },
      ),
    );
  }

  Widget _buildGalleryContent(BuildContext context) {
    if (_galleryLoading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }
    if (_galleryError != null) {
      return SizedBox(
        height: 160,
        child: CupertinoEmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          message: _galleryError!,
        ),
      );
    }
    switch (_galleryTab) {
      case 0:
        return _buildMediaGrid();
      case 1:
        return _buildFilesList();
      default:
        return _buildLinksList();
    }
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildMediaGrid() {
    if (_media.isEmpty) {
      return const SizedBox(
        height: 160,
        child: CupertinoEmptyState(
          icon: CupertinoIcons.photo_on_rectangle,
          message: 'Здесь появятся фото и видео из чата',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('${_media.length} ФОТО И ВИДЕО'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground
                .resolveFrom(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: _media.length,
              itemBuilder: (context, index) {
                final m = _media[index];
                final localPath = m.localMediaPath;
                return GestureDetector(
                  onTap: () => _openViewer(index),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      localPath != null && localPath.isNotEmpty
                          ? Image.file(File(localPath), fit: BoxFit.cover)
                          : AppNetworkImage(
                              url: m.remoteMediaUrl,
                              fit: BoxFit.cover,
                            ),
                      if (m.attachmentKind == ChatAttachmentKind.video)
                        Container(
                          alignment: Alignment.bottomLeft,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                CupertinoColors.black.withValues(alpha: 0.45),
                                CupertinoColors.black.withValues(alpha: 0),
                              ],
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.play_fill,
                            color: CupertinoColors.white,
                            size: 15,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilesList() {
    if (_files.isEmpty) {
      return const SizedBox(
        height: 160,
        child: CupertinoEmptyState(
          icon: CupertinoIcons.doc,
          message: 'Здесь появятся файлы из чата',
        ),
      );
    }
    final groups = _groupByDate(_files, (m) => m.createdAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.expand((group) {
        return [
          _sectionLabel(group.key.toUpperCase()),
          CupertinoListSection.insetGrouped(
            children: group.value.map((m) {
              final accent = _fileAccentFor(m.fileName);
              return CupertinoListTile(
                leading: _iconBadge(accent.icon, accent.color),
                title: Text(
                  m.fileName ?? 'Файл',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '${accent.label} · '
                  '${DateFormat('HH:mm', 'ru_RU').format(m.createdAt.toLocal())}',
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _openFile(m),
              );
            }).toList(),
          ),
        ];
      }).toList(),
    );
  }

  Widget _buildLinksList() {
    if (_links.isEmpty) {
      return const SizedBox(
        height: 160,
        child: CupertinoEmptyState(
          icon: CupertinoIcons.link,
          message: 'Здесь появятся ссылки из чата',
        ),
      );
    }
    final groups = _groupByDate(_links, (e) => e.createdAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.expand((group) {
        return [
          _sectionLabel(group.key.toUpperCase()),
          CupertinoListSection.insetGrouped(
            children: group.value.map((entry) {
              final domain = _domainFor(entry.url);
              final label = domain.isEmpty ? entry.url : domain;
              return CupertinoListTile(
                leading: Container(
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: chatAvatarColor(label),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.link,
                    size: 15,
                    color: CupertinoColors.white,
                  ),
                ),
                title: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  entry.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CupertinoColors.activeBlue),
                ),
                trailing: Text(
                  DateFormat('HH:mm', 'ru_RU').format(entry.createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
                onTap: () => _openLink(entry.url),
              );
            }).toList(),
          ),
        ];
      }).toList(),
    );
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selfId = _service.selfUserId;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Настройки чата'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: _busy
              ? const Center(child: CupertinoActivityIndicator(radius: 14))
              : ListView(
                  padding: const EdgeInsets.only(top: 20, bottom: 32),
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _canManage && _chat.isGroup ? _editChat : null,
                        child: ChatAvatar(chat: _chat, radius: 40),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _chat.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: CupertinoColors.label,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_chat.description != null &&
                        _chat.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                        child: Text(
                          _chat.description!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _QuickActionButton(
                              icon: CupertinoIcons.phone_fill,
                              label: 'Звонок',
                              color: CupertinoColors.systemGreen,
                              onTap: _call,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _QuickActionButton(
                              icon: _chat.isFavorite
                                  ? CupertinoIcons.star_fill
                                  : CupertinoIcons.star,
                              label: 'Избранное',
                              color: CupertinoColors.systemYellow,
                              active: _chat.isFavorite,
                              onTap: () => _service.toggleFavorite(_chat.id),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _QuickActionButton(
                              icon: _chat.isMuted
                                  ? CupertinoIcons.bell_slash_fill
                                  : CupertinoIcons.bell_fill,
                              label: 'Звук',
                              color: CupertinoColors.systemGrey,
                              active: _chat.isMuted,
                              onTap: () => _service.toggleMute(_chat.id),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _QuickActionButton(
                              icon: CupertinoIcons.search,
                              label: 'Поиск',
                              color: CupertinoColors.systemBlue,
                              onTap: _openSearch,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildGalleryTabs(context),
                    _buildGalleryContent(context),
                    if (_canManage && _chat.isGroup)
                      CupertinoListSection.insetGrouped(
                        children: [
                          CupertinoListTile(
                            leading: _iconBadge(
                              CupertinoIcons.person_add_solid,
                              CupertinoColors.systemGreen,
                            ),
                            title: const Text('Добавить участников'),
                            trailing: const CupertinoListTileChevron(),
                            onTap: _addMembers,
                          ),
                        ],
                      ),
                    if (_chat.isGroup && _chat.members.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                        child: Text(
                          'УЧАСТНИКИ (${_chat.members.length})',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      CupertinoListSection.insetGrouped(
                        margin: EdgeInsets.zero,
                        children: _chat.members.map((m) {
                          final isCreator = m.userId == _chat.creatorId;
                          final canRemove =
                              m.userId == selfId || (_canManage && !isCreator);
                          final roleLabel = [
                            if (isCreator) 'Создатель',
                            if (m.isAdmin && !isCreator) 'Администратор',
                          ].join(' · ');
                          return CupertinoListTile(
                            leading: MemberAvatar(
                              displayName: m.displayName,
                              avatarUrl: m.avatarUrl,
                              radius: 18,
                            ),
                            title: Text(m.displayName),
                            subtitle: roleLabel.isEmpty
                                ? null
                                : Text(roleLabel),
                            trailing: canRemove
                                ? GestureDetector(
                                    onTap: () => _removeMember(m),
                                    child: Icon(
                                      m.userId == selfId
                                          ? CupertinoIcons.square_arrow_right
                                          : CupertinoIcons.minus_circle,
                                      color: CupertinoColors.systemRed,
                                    ),
                                  )
                                : null,
                          );
                        }).toList(),
                      ),
                    ],
                    if (_canManage && _chat.isGroup) ...[
                      const SizedBox(height: 20),
                      CupertinoListSection.insetGrouped(
                        children: [
                          CupertinoListTile(
                            leading: _iconBadge(
                              CupertinoIcons.delete_solid,
                              CupertinoColors.systemRed,
                            ),
                            title: const Text(
                              'Удалить чат',
                              style: TextStyle(color: CupertinoColors.systemRed),
                            ),
                            onTap: _deleteChat,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _AddMembersSheet extends StatefulWidget {
  const _AddMembersSheet({required this.candidates});

  final List<ChatContact> candidates;

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Добавить участников',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                CupertinoListSection.insetGrouped(
                  margin: EdgeInsets.zero,
                  children: widget.candidates.map((c) {
                    final checked = _selected.contains(c.userId);
                    return CupertinoListTile(
                      leading: MemberAvatar(
                        displayName: c.fullName,
                        avatarUrl: c.avatarUrl,
                        radius: 18,
                      ),
                      title: Text(c.fullName),
                      trailing: checked
                          ? const Icon(
                              CupertinoIcons.checkmark_circle_fill,
                              color: CupertinoColors.activeBlue,
                            )
                          : const Icon(
                              CupertinoIcons.circle,
                              color: CupertinoColors.systemGrey3,
                            ),
                      onTap: () {
                        setState(() {
                          if (checked) {
                            _selected.remove(c.userId);
                          } else {
                            _selected.add(c.userId);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: const Text('Добавить'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.15)
                  : CupertinoColors.systemGrey5.resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.label.resolveFrom(context),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
