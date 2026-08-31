import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/add_chat_members_request.dart';
import 'package:connect/models/chat/create_chat_request.dart';
import 'package:connect/models/chat/update_chat_message_request.dart';
import 'package:connect/models/chat/update_chat_request.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/models/staff_user.dart';
import 'package:connect/repositories/chat_management_repository.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/repositories/users_repository.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/chat_preferences_service.dart';
import 'package:connect/utils/chat_mapper.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:flutter/foundation.dart';

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
  if (text != null && text.trim().isNotEmpty) {
    return HtmlTextUtils.toPlainText(text);
  }
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

@immutable
class ChatContact {
  const ChatContact({
    required this.userId,
    required this.fullName,
    this.avatarPath,
    this.avatarUrl,
  });

  final int userId;
  final String fullName;
  final String? avatarPath;
  final String? avatarUrl;

  factory ChatContact.fromStaffUser(StaffUser user) {
    return ChatContact(
      userId: user.idAsInt ?? 0,
      fullName: user.chatDisplayName,
      avatarUrl: user.avatarUrl,
    );
  }
}

class ChatService extends ChangeNotifier {
  ChatService._();
  static final ChatService instance = ChatService._();

  String _selfName = 'Я';
  int? _selfUserId;

  String get selfName => _selfName;
  int? get selfUserId => _selfUserId;

  final List<Chat> _chats = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, bool> _messagesLoading = {};
  final Map<String, String?> _messagesError = {};

  bool _isLoading = true;
  bool _isContactsLoading = false;
  String? _error;

  List<Chat> get chats => List.unmodifiable(_chats);
  bool get isLoading => _isLoading;
  bool get isContactsLoading => _isContactsLoading;
  String? get error => _error;

  String? _lastActionError;

  String? get lastActionError => _lastActionError;

  List<ChatContact> _contacts = const [];
  List<ChatContact> get contacts => List.unmodifiable(_contacts);

  List<ChatMessage> messagesFor(String chatId) {
    final list = _messages[chatId];
    if (list == null) return const [];
    return List.unmodifiable(list);
  }

  bool isMessagesLoading(String chatId) => _messagesLoading[chatId] == true;

  String? messagesError(String chatId) => _messagesError[chatId];

  Chat? chatById(String id) {
    for (final c in _chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> init() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    await ChatPreferencesService.instance.ensureLoaded();
    await _refreshSelfProfile();
    await refreshChats();
  }

  Chat _applyLocalFlags(Chat c) {
    final prefs = ChatPreferencesService.instance;
    return c.copyWithFlags(
      isMuted: prefs.isMuted(c.id),
      isFavorite: prefs.isFavorite(c.id),
    );
  }

  Future<void> refreshChats() async {
    final userId = _selfUserId;
    if (userId == null) {
      _error = 'Не удалось определить текущего пользователя';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ChatPreferencesService.instance.ensureLoaded();
      final loaded = await ChatRepository.instance.getChats(
        currentUserId: userId,
      );
      _chats
        ..clear()
        ..addAll(loaded.map(_applyLocalFlags));
      _error = null;
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(String chatId, {bool force = false}) async {
    if (!force && (_messages[chatId]?.isNotEmpty ?? false)) return;

    _messagesLoading[chatId] = true;
    _messagesError[chatId] = null;
    notifyListeners();

    try {
      if (_selfUserId == null) {
        await _refreshSelfProfile();
      }
      final userId = _selfUserId;
      if (userId == null) {
        _messagesError[chatId] = 'Не удалось определить текущего пользователя';
        return;
      }

      final page = await ChatRepository.instance.getMessages(
        int.parse(chatId),
        currentUserId: userId,
      );
      _messages[chatId] = List<ChatMessage>.from(page.messages.data);
      if (page.members.isNotEmpty) {
        final idx = _chats.indexWhere((c) => c.id == chatId);
        if (idx >= 0) {
          _chats[idx] = _chats[idx].copyWithMembers(page.members);
        }
      }
      _upsertLastMessage(chatId);
      _messagesError[chatId] = null;
    } catch (e) {
      _messagesError[chatId] = e.toString();
    } finally {
      _messagesLoading[chatId] = false;
      notifyListeners();
    }
  }

  /// Отмечает входящие сообщения чата как прочитанные — локально (счётчик,
  /// список сообщений) и на сервере.
  Future<void> markChatRead(String chatId) async {
    final chatIntId = int.tryParse(chatId);
    if (chatIntId == null) return;

    var changed = false;

    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx >= 0 && _chats[idx].unreadCount > 0) {
      _chats[idx] = _chats[idx].copyWithUnreadCount(0);
      changed = true;
    }

    final list = _messages[chatId];
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        final m = list[i];
        if (!m.isOutgoing && !m.isRead) {
          list[i] = m.copyWithReadState(isRead: true);
          changed = true;
        }
      }
    }

    if (changed) notifyListeners();

    try {
      await ChatRepository.instance.markRead(chatIntId);
    } catch (_) {}
  }

  Future<void> loadContacts() async {
    if (_isContactsLoading) return;
    _isContactsLoading = true;
    notifyListeners();
    try {
      final all = <ChatContact>[];
      String? nextUrl;
      var pageNum = 1;
      while (true) {
        final page = await UsersRepository.instance.getPage(
          url: nextUrl,
          page: pageNum,
        );
        all.addAll(
          page.data
              .where((u) => u.idAsInt != null && u.idAsInt != _selfUserId)
              .map(ChatContact.fromStaffUser),
        );
        final seen = <int>{};
        _contacts = [
          for (final c in all)
            if (c.userId > 0 && seen.add(c.userId)) c,
        ];
        notifyListeners();

        if (page.data.isEmpty || pageNum >= 80) break;

        nextUrl = page.nextPageUrl;
        if (nextUrl != null) {
          pageNum = page.currentPage + 1;
          continue;
        }
        if (page.lastPage != null && page.currentPage < page.lastPage!) {
          if (page.currentPage < pageNum) break;
          pageNum = page.currentPage + 1;
          nextUrl = null;
          continue;
        }
        break;
      }
    } catch (_) {
      if (_contacts.isEmpty) _contacts = const [];
    } finally {
      _isContactsLoading = false;
      notifyListeners();
    }
  }

  Future<List<ChatContact>> searchContacts(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final result = <ChatContact>[];
    final seen = <int>{};
    String? nextUrl;
    var pageNum = 1;
    while (true) {
      final page = await UsersRepository.instance.getPage(
        url: nextUrl,
        q: q,
        page: pageNum,
      );
      for (final u in page.data) {
        if (u.idAsInt == null || u.idAsInt == _selfUserId) continue;
        final c = ChatContact.fromStaffUser(u);
        if (c.userId > 0 && seen.add(c.userId)) result.add(c);
      }

      if (page.data.isEmpty || pageNum >= 20) break;

      nextUrl = page.nextPageUrl;
      if (nextUrl != null) {
        pageNum = page.currentPage + 1;
        continue;
      }
      if (page.lastPage != null && page.currentPage < page.lastPage!) {
        if (page.currentPage < pageNum) break;
        pageNum = page.currentPage + 1;
        nextUrl = null;
        continue;
      }
      break;
    }
    return result;
  }

  Future<void> _refreshSelfProfile() async {
    final u = await AuthService.instance.getStoredUser();
    if (u == null) return;

    final newUserId = _parseInt(u['id']);
    final s = (u['surname'] as String?)?.trim();
    final n = (u['name'] as String?)?.trim();
    final newName = (s != null && s.isNotEmpty && n != null && n.isNotEmpty)
        ? '$s $n'
        : (u['name'] as String?)?.trim() ??
            (u['email'] as String?)?.split('@').first ??
            'Я';

    if (newUserId == _selfUserId && newName == _selfName) return;

    _selfUserId = newUserId;
    _selfName = newName;
    notifyListeners();
  }

  Chat? findDirectChatForUser(int userId) {
    for (final c in _chats) {
      if (!c.isGroup && c.peerUserId == userId) return c;
    }
    return null;
  }

  void _moveChatToTop(String chatId) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx <= 0) return;
    final chat = _chats.removeAt(idx);
    _chats.insert(0, chat);
    notifyListeners();
  }

  /// Создание группового чата через API.
  Future<Chat?> createGroup({
    required String title,
    required List<int> userIds,
    String? description,
  }) async {
    final userId = _selfUserId;
    if (userId == null || userIds.isEmpty) return null;

    try {
      final record = await ChatManagementRepository.instance.createChat(
        CreateChatRequest(
          title: title,
          description: description,
          isGroup: true,
          userIds: userIds,
        ),
        currentUserId: userId,
      );
      final chat = ChatMapper.fromRecord(record, currentUserId: userId);
      _chats.insert(0, chat);
      notifyListeners();
      return chat;
    } catch (_) {
      return null;
    }
  }

  Future<Chat?> createDirect({
    required String fullName,
    String? peerAvatarPath,
    int? peerUserId,
    String? peerAvatarUrl,
  }) async {
    if (peerUserId != null) {
      final existing = findDirectChatForUser(peerUserId);
      if (existing != null) {
        _moveChatToTop(existing.id);
        return existing;
      }
    }

    final userId = _selfUserId;
    if (userId == null || peerUserId == null) return null;

    try {
      final record = await ChatManagementRepository.instance.createChat(
        CreateChatRequest(isGroup: false, userIds: [peerUserId]),
        currentUserId: userId,
      );
      final chat = ChatMapper.fromRecord(record, currentUserId: userId).copyWithDetails(
        title: fullName,
      );
      if (peerAvatarPath != null || peerAvatarUrl != null) {
        final withAvatar = Chat(
          id: chat.id,
          title: chat.title,
          avatarPath: chat.avatarPath,
          avatarUrl: chat.avatarUrl,
          peerAvatarPath: peerAvatarPath,
          peerAvatarUrl: peerAvatarUrl ?? chat.peerAvatarUrl,
          peerUserId: peerUserId,
          isGroup: false,
          description: chat.description,
          creatorId: chat.creatorId,
          members: chat.members,
          lastMessagePreview: chat.lastMessagePreview,
          lastMessageAt: chat.lastMessageAt,
        );
        _chats.insert(0, withAvatar);
        notifyListeners();
        return withAvatar;
      }
      _chats.insert(0, chat);
      notifyListeners();
      return chat;
    } catch (_) {
      return null;
    }
  }

  Future<Chat?> refreshChatDetails(String chatId) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    if (userId == null || chatIntId == null) return null;

    try {
      final chat = await ChatRepository.instance.getChat(
        chatIntId,
        currentUserId: userId,
      );
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx >= 0) {
        final prev = _chats[idx];
        _chats[idx] = chat.copyWithDetails(
          avatarPath: prev.avatarPath,
          title: chat.title.isNotEmpty ? chat.title : prev.title,
          unreadCount: prev.unreadCount,
          isMuted: prev.isMuted,
          isFavorite: prev.isFavorite,
        );
      }
      notifyListeners();
      return chatById(chatId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateChat(
    String chatId, {
    String? title,
    String? description,
  }) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    if (userId == null || chatIntId == null) return false;

    try {
      final record = await ChatManagementRepository.instance.updateChat(
        chatIntId,
        UpdateChatRequest(title: title, description: description),
        currentUserId: userId,
      );
      final updated = ChatMapper.fromRecord(record, currentUserId: userId);
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx >= 0) {
        final prev = _chats[idx];
        _chats[idx] = updated.copyWithDetails(
          avatarPath: prev.avatarPath,
          lastMessagePreview: prev.lastMessagePreview,
          lastMessageAt: prev.lastMessageAt,
          unreadCount: prev.unreadCount,
          isMuted: prev.isMuted,
          isFavorite: prev.isFavorite,
        );
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteChat(String chatId) async {
    final chatIntId = int.tryParse(chatId);
    if (chatIntId == null) return false;

    try {
      _lastActionError = null;
      await ChatManagementRepository.instance.deleteChat(chatIntId);
      _chats.removeWhere((c) => c.id == chatId);
      _messages.remove(chatId);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastActionError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> addMembers(String chatId, List<int> userIds) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    if (userId == null || chatIntId == null || userIds.isEmpty) return false;

    try {
      final record = await ChatManagementRepository.instance.addMembers(
        chatIntId,
        AddChatMembersRequest(userIds: userIds),
        currentUserId: userId,
      );
      final updated = ChatMapper.fromRecord(record, currentUserId: userId);
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx >= 0) {
        final prev = _chats[idx];
        _chats[idx] = updated.copyWithDetails(
          avatarPath: prev.avatarPath,
          lastMessagePreview: prev.lastMessagePreview,
          lastMessageAt: prev.lastMessageAt,
          unreadCount: prev.unreadCount,
          isMuted: prev.isMuted,
          isFavorite: prev.isFavorite,
        );
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeMember(String chatId, int memberUserId) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    if (userId == null || chatIntId == null) return false;

    try {
      _lastActionError = null;
      await ChatManagementRepository.instance.removeMember(
        chatIntId,
        memberUserId,
        currentUserId: userId,
      );
      if (memberUserId == userId) {
        _chats.removeWhere((c) => c.id == chatId);
        _messages.remove(chatId);
      } else {
        await refreshChatDetails(chatId);
      }
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastActionError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateMessage(
    String chatId,
    String messageId,
    String text,
  ) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    final messageIntId = int.tryParse(messageId);
    if (userId == null || chatIntId == null || messageIntId == null) {
      return false;
    }

    try {
      final updated = await ChatManagementRepository.instance.updateMessage(
        chatIntId,
        messageIntId,
        UpdateChatMessageRequest(text: text),
        currentUserId: userId,
      );
      final list = _messages[chatId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.id == messageId);
        if (idx >= 0) {
          list[idx] = ChatMessage(
            id: updated.id,
            chatId: updated.chatId,
            authorName: updated.authorName,
            isOutgoing: updated.isOutgoing,
            createdAt: updated.createdAt,
            text: updated.text,
            attachmentKind: updated.attachmentKind,
            remoteMediaUrl: updated.remoteMediaUrl,
            replyTo: list[idx].replyTo,
            forwardOf: list[idx].forwardOf,
            isSystem: updated.isSystem,
            repliedMessageId: updated.repliedMessageId,
            isRead: updated.isRead,
            authorAvatarUrl: updated.authorAvatarUrl,
            readByRecipients: list[idx].readByRecipients,
          );
        }
      }
      _upsertLastMessage(chatId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteMessage(String chatId, String messageId) async {
    final chatIntId = int.tryParse(chatId);
    final messageIntId = int.tryParse(messageId);
    if (chatIntId == null || messageIntId == null) return false;

    try {
      _lastActionError = null;
      await ChatManagementRepository.instance.deleteMessage(
        chatIntId,
        messageIntId,
      );
      final list = _messages[chatId];
      list?.removeWhere((m) => m.id == messageId);
      _upsertLastMessage(chatId);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastActionError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      notifyListeners();
      return false;
    }
  }

  void setChatAvatar(String chatId, String avatarPath) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx < 0) return;
    final c = _chats[idx];
    _chats[idx] = Chat(
      id: c.id,
      title: c.title,
      avatarPath: avatarPath,
      avatarUrl: c.avatarUrl,
      peerAvatarPath: c.peerAvatarPath,
      peerAvatarUrl: c.peerAvatarUrl,
      peerUserId: c.peerUserId,
      isGroup: c.isGroup,
      description: c.description,
      creatorId: c.creatorId,
      members: c.members,
      lastMessagePreview: c.lastMessagePreview,
      lastMessageAt: c.lastMessageAt,
      unreadCount: c.unreadCount,
      isMuted: c.isMuted,
      isFavorite: c.isFavorite,
    );
    notifyListeners();
  }

  /// Локальный тумблер звука чата (см. [ChatPreferencesService]) —
  /// на сервере такого понятия нет, поэтому пуши для замьюченного чата
  /// на этом устройстве просто не показываются баннером/звуком.
  Future<void> toggleMute(String chatId) async {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx < 0) return;
    final next = !_chats[idx].isMuted;
    _chats[idx] = _chats[idx].copyWithFlags(isMuted: next);
    notifyListeners();
    await ChatPreferencesService.instance.setMuted(chatId, next);
  }

  Future<void> toggleFavorite(String chatId) async {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx < 0) return;
    final next = !_chats[idx].isFavorite;
    _chats[idx] = _chats[idx].copyWithFlags(isFavorite: next);
    notifyListeners();
    await ChatPreferencesService.instance.setFavorite(chatId, next);
  }

  Future<void> sendText(
    String chatId,
    String text, {
    MessageReference? replyTo,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;

    final userId = _selfUserId;
    if (userId == null) return;

    final chatIntId = int.tryParse(chatId);
    if (chatIntId == null) return;

    final repliedId = replyTo != null ? int.tryParse(replyTo.messageId) : null;

    try {
      final sent = await ChatRepository.instance.sendTextMessage(
        chatIntId,
        text: t,
        currentUserId: userId,
        repliedMessageId: repliedId,
      );

      _appendMessage(
        chatId,
        ChatMessage(
          id: sent.id,
          chatId: sent.chatId,
          authorName: sent.authorName,
          isOutgoing: sent.isOutgoing,
          createdAt: sent.createdAt,
          text: sent.text ?? t,
          replyTo: replyTo,
          repliedMessageId: sent.repliedMessageId,
          isRead: true,
          authorAvatarUrl: sent.authorAvatarUrl,
          readByRecipients: sent.readByRecipients,
        ),
      );
    } catch (e) {
      rethrow;
    }
  }

  void sendMedia(
    String chatId, {
    required String path,
    required ChatAttachmentKind kind,
    String? caption,
    String? fileName,
    MessageReference? replyTo,
  }) {
    // Отправка медиа через API пока не подключена.
  }

  void forwardMessage(
    String targetChatId,
    ChatMessage source, {
    required String sourceChatId,
  }) {
    // Пересылка через API пока не подключена.
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

  void _appendMessage(String chatId, ChatMessage m) {
    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(m);
    _upsertLastMessage(chatId);
    notifyListeners();
  }

  int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}

extension on Chat {
  Chat withPreview(String? preview, DateTime? at) {
    return copyWithPreview(
      lastMessagePreview: preview,
      lastMessageAt: at,
    );
  }
}
