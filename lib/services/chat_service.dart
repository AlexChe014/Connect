import 'package:connect/config/api_config.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/auth_service.dart';
import 'package:flutter/foundation.dart';

String _newId() => 'id_${DateTime.now().microsecondsSinceEpoch}';

String _messagePreview(ChatMessage m) {
  if (m.forwardOf != null) {
    return 'Переслано: ${_snippet(m.text, m.fileName, m.attachmentKind)}';
  }
  if (m.replyTo != null) {
    return _snippet(m.text, m.fileName, m.attachmentKind);
  }
  return _snippet(m.text, m.fileName, m.attachmentKind);
}

String _snippet(String? text, String? fileName, ChatAttachmentKind kind) {
  if (text != null && text.trim().isNotEmpty) return text.trim();
  switch (kind) {
    case ChatAttachmentKind.image:
      return '📷 Фото';
    case ChatAttachmentKind.video:
      return '🎬 Видео';
    case ChatAttachmentKind.file:
      return '📎 ${fileName ?? 'Файл'}';
    case ChatAttachmentKind.none:
      return 'Сообщение';
  }
}

/// Локальное хранение чатов (mock или сервер). При `useMockApi` данные в памяти.
class ChatService extends ChangeNotifier {
  ChatService._();
  static final ChatService instance = ChatService._();

  String _selfName = 'Я';

  String get selfName => _selfName;

  final List<Chat> _chats = [];
  final Map<String, List<ChatMessage>> _messages = {};

  List<Chat> get chats => List.unmodifiable(_chats);

  List<ChatMessage> messagesFor(String chatId) {
    final list = _messages[chatId];
    if (list == null) return const [];
    return List.unmodifiable(list);
  }

  Chat? chatById(String id) {
    for (final c in _chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> init() async {
    await _refreshSelfName();
    if (_chats.isNotEmpty) return;
    _seed();
    notifyListeners();
  }

  Future<void> _refreshSelfName() async {
    final u = await AuthService.instance.getStoredUser();
    if (u == null) return;
    final s = (u['surname'] as String?)?.trim();
    final n = (u['name'] as String?)?.trim();
    if (s != null && s.isNotEmpty && n != null && n.isNotEmpty) {
      _selfName = '$s $n';
    } else {
      _selfName = (u['name'] as String?)?.trim() ??
          (u['email'] as String?)?.split('@').first ??
          'Я';
    }
    notifyListeners();
  }

  void _seed() {
    const g1 = 'chat_group_1';
    const d1 = 'chat_direct_1';
    _chats.addAll([
      Chat(
        id: g1,
        title: 'Команда проекта',
        isGroup: true,
        memberNames: const ['Анна Смирнова', 'Пётр Волков', 'Вы'],
        lastMessagePreview: 'Договорились на 15:00',
        lastMessageAt: DateTime.now().subtract(const Duration(minutes: 12)),
      ),
      Chat(
        id: d1,
        title: 'Анна Смирнова',
        isGroup: false,
        lastMessagePreview: 'Отчёт лежит в общей папке',
        lastMessageAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ]);

    _messages[g1] = [
      ChatMessage(
        id: 'm1',
        chatId: g1,
        authorName: 'Пётр Волков',
        isOutgoing: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        text: 'Коллеги, сегодня синк в 15:00, ок?',
      ),
      ChatMessage(
        id: 'm2',
        chatId: g1,
        authorName: 'Анна Смирнова',
        isOutgoing: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
        text: 'Да, напомню в календаре.',
      ),
      ChatMessage(
        id: 'm3',
        chatId: g1,
        authorName: _selfName,
        isOutgoing: true,
        createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
        text: 'Договорились на 15:00',
      ),
    ];
    _messages[d1] = [
      ChatMessage(
        id: 'm4',
        chatId: d1,
        authorName: 'Анна Смирнова',
        isOutgoing: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        text: 'Отчёт лежит в общей папке',
      ),
    ];
    for (var i = 0; i < _chats.length; i++) {
      _chats[i] = _chats[i].withPreviewFrom(_messages[_chats[i].id] ?? const []);
    }
  }

  void _upsertLastMessage(String chatId) {
    final list = _messages[chatId];
    if (list == null || list.isEmpty) return;
    final last = list.last;
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx < 0) return;
    _chats[idx] = _chats[idx].withPreview(
      _messagePreview(last),
      last.createdAt,
    );
    _chats.sort((a, b) {
      final at = a.lastMessageAt;
      final bt = b.lastMessageAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  }

  Future<Chat> createGroup({
    required String title,
    required List<String> otherMemberNames,
  }) async {
    if (!ApiConfig.useMockApi) {
      try {
        final data = await ApiClient.instance.post(
          '${ApiConfig.chatsBaseUrl}/groups',
          body: {
            'title': title,
            'member_names': [...otherMemberNames, _selfName],
          },
        );
        final m = data['data'] as Map<String, dynamic>? ?? data;
        final c = _chatFromJson(m);
        _chats.insert(0, c);
        _messages[c.id] = [];
        notifyListeners();
        return c;
      } catch (_) {
        // fallthrough to local
      }
    }
    final id = _newId();
    final allMembers = <String>{...otherMemberNames, _selfName}.toList()..sort();
    final c = Chat(
      id: id,
      title: title,
      isGroup: true,
      memberNames: allMembers,
      lastMessageAt: DateTime.now(),
    );
    _chats.insert(0, c);
    _messages[id] = [
      ChatMessage(
        id: _newId(),
        chatId: id,
        authorName: _selfName,
        isOutgoing: true,
        createdAt: DateTime.now(),
        text: 'Группа «$title» создана',
      ),
    ];
    _upsertLastMessage(id);
    notifyListeners();
    return c;
  }

  static Chat _chatFromJson(Map<String, dynamic> m) {
    return Chat(
      id: m['id'] as String,
      title: m['title'] as String? ?? 'Чат',
      isGroup: m['is_group'] as bool? ?? true,
      memberNames: (m['member_names'] as List?)?.map((e) => '$e').toList() ?? const [],
      lastMessagePreview: m['last_message'] as String?,
      lastMessageAt: m['last_at'] != null
          ? DateTime.tryParse('${m['last_at']}')
          : null,
    );
  }

  /// Текстовое сообщение, опционально с ответом.
  void sendText(
    String chatId,
    String text, {
    MessageReference? replyTo,
  }) {
    final t = text.trim();
    if (t.isEmpty) return;
    _appendMessage(
      chatId,
      ChatMessage(
        id: _newId(),
        chatId: chatId,
        authorName: _selfName,
        isOutgoing: true,
        createdAt: DateTime.now(),
        text: t,
        replyTo: replyTo,
      ),
    );
  }

  void sendMedia(
    String chatId, {
    required String path,
    required ChatAttachmentKind kind,
    String? caption,
    String? fileName,
    MessageReference? replyTo,
  }) {
    if (path.isEmpty) return;
    _appendMessage(
      chatId,
      ChatMessage(
        id: _newId(),
        chatId: chatId,
        authorName: _selfName,
        isOutgoing: true,
        createdAt: DateTime.now(),
        text: caption?.trim().isNotEmpty == true ? caption!.trim() : null,
        attachmentKind: kind,
        localMediaPath: path,
        fileName: fileName,
        replyTo: replyTo,
      ),
    );
  }

  void forwardMessage(
    String targetChatId,
    ChatMessage source, {
    required String sourceChatId,
  }) {
    final fromChat = chatById(sourceChatId);
    final ref = MessageReference(
      messageId: source.id,
      authorName: source.authorName,
      textPreview: _snippet(
        source.text,
        source.fileName,
        source.attachmentKind,
      ),
      sourceChatTitle: fromChat?.title,
    );
    _appendMessage(
      targetChatId,
      ChatMessage(
        id: _newId(),
        chatId: targetChatId,
        authorName: _selfName,
        isOutgoing: true,
        createdAt: DateTime.now(),
        text: source.text,
        attachmentKind: source.attachmentKind,
        localMediaPath: source.localMediaPath,
        fileName: source.fileName,
        forwardOf: ref,
      ),
    );
  }

  void _appendMessage(String chatId, ChatMessage m) {
    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(m);
    _upsertLastMessage(chatId);
    notifyListeners();
  }
}

extension on Chat {
  Chat withPreview(String? preview, DateTime? at) {
    return Chat(
      id: id,
      title: title,
      isGroup: isGroup,
      memberNames: memberNames,
      lastMessagePreview: preview,
      lastMessageAt: at,
    );
  }

  Chat withPreviewFrom(List<ChatMessage> list) {
    if (list.isEmpty) {
      return withPreview(null, null);
    }
    final last = list.last;
    return withPreview(_messagePreview(last), last.createdAt);
  }
}
