import 'dart:async';

import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/add_chat_members_request.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/models/chat/create_chat_request.dart';
import 'package:connect/models/chat/pinned_chat_message.dart';
import 'package:connect/models/chat/update_chat_message_request.dart';
import 'package:connect/models/chat/update_chat_request.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/models/staff_user.dart';
import 'package:connect/repositories/chat_management_repository.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/repositories/users_repository.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/chat_draft_service.dart';
import 'package:connect/services/chat_preferences_service.dart';
import 'package:connect/utils/chat_mapper.dart';
import 'package:connect/utils/chat_realtime_payload.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:flutter/foundation.dart';

String _messagePreview(ChatMessage m) {
  if (m.isDeleted) {
    return 'Сообщение удалено';
  }
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
  final Map<String, List<PinnedChatMessage>> _pinnedMessages = {};
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

  /// Чаты, для которых отметка "прочитано" не была подтверждена сервером
  /// (например, из-за обрыва сети) — повторяем попытку при следующем
  /// [refreshChats], чтобы статус не застревал непрочитанным на сервере.
  final Set<String> _pendingReadSync = {};

  /// Открытый экран переписки — входящие не увеличивают бейдж, сразу read.
  String? _activeChatId;

  List<ChatMessage> messagesFor(String chatId) {
    final list = _messages[chatId];
    if (list == null) return const [];
    return List.unmodifiable(list);
  }

  List<PinnedChatMessage> pinnedMessagesFor(String chatId) {
    final list = _pinnedMessages[chatId];
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
    await ChatDraftService.instance.ensureLoaded();
    await _refreshSelfProfile();
    await refreshChats();
  }

  Chat _applyLocalFlags(Chat c) {
    final prefs = ChatPreferencesService.instance;
    return c
        .copyWithFlags(
          isMuted: prefs.isMuted(c.id),
          isFavorite: prefs.isFavorite(c.id),
        )
        .copyWithDraft(ChatDraftService.instance.draftFor(c.id));
  }

  void setActiveChat(String chatId) {
    _activeChatId = chatId;
  }

  void clearActiveChat(String chatId) {
    if (_activeChatId == chatId) _activeChatId = null;
  }

  Future<void> refreshChats({bool showLoading = true}) async {
    final userId = _selfUserId;
    if (userId == null) {
      _error = 'Не удалось определить текущего пользователя';
      _isLoading = false;
      notifyListeners();
      return;
    }

    if (showLoading) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      await ChatPreferencesService.instance.ensureLoaded();
      await ChatDraftService.instance.ensureLoaded();
      final loaded = await ChatRepository.instance.getChats(
        currentUserId: userId,
      );
      _chats
        ..clear()
        ..addAll(loaded.map(_applyLocalFlags));
      _error = null;
      unawaited(_flushPendingReadSync());
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadMessages(
    String chatId, {
    bool force = false,
    bool showLoading = true,
  }) async {
    if (_messagesLoading[chatId] == true) return;
    if (!force && (_messages[chatId]?.isNotEmpty ?? false)) return;

    final hasLocal = _messages[chatId]?.isNotEmpty ?? false;
    _messagesLoading[chatId] = true;
    _messagesError[chatId] = null;
    if (showLoading && !hasLocal) {
      notifyListeners();
    }

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
      _messages[chatId] = _mergeMessages(
        page.messages.data,
        _messages[chatId],
      );
      if (page.members.isNotEmpty) {
        final idx = _chats.indexWhere((c) => c.id == chatId);
        if (idx >= 0) {
          _chats[idx] = _chats[idx].copyWithMembers(page.members);
        }
      }
      _upsertLastMessage(chatId);
      unawaited(loadPinnedMessages(chatId));
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

    await _syncReadStatus(chatId, chatIntId);
  }

  /// Отправляет отметку "прочитано" на сервер. При ошибке (сеть, таймаут,
  /// сбой бэкенда) чат остаётся в [_pendingReadSync] и будет повторно
  /// отправлен при следующем [refreshChats] — иначе локально сообщение уже
  /// выглядит прочитанным, и повода снова открыть тот же чат может не быть,
  /// из-за чего сервер (и портал) так и не узнают о прочтении.
  Future<void> _syncReadStatus(String chatId, int chatIntId) async {
    try {
      await ChatRepository.instance.markRead(chatIntId);
      _pendingReadSync.remove(chatId);
    } catch (_) {
      _pendingReadSync.add(chatId);
    }
  }

  Future<void> _flushPendingReadSync() async {
    if (_pendingReadSync.isEmpty) return;
    for (final chatId in List<String>.from(_pendingReadSync)) {
      final chatIntId = int.tryParse(chatId);
      if (chatIntId == null) {
        _pendingReadSync.remove(chatId);
        continue;
      }
      await _syncReadStatus(chatId, chatIntId);
    }
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

  Future<void> loadPinnedMessages(String chatId) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    if (userId == null || chatIntId == null) return;

    try {
      final pinned = await ChatRepository.instance.getPinnedMessages(
        chatIntId,
        currentUserId: userId,
      );
      _pinnedMessages[chatId] = List<PinnedChatMessage>.from(pinned);
      final pinnedIds = {for (final p in pinned) p.message.id};
      final list = _messages[chatId];
      if (list != null) {
        for (var i = 0; i < list.length; i++) {
          final m = list[i];
          final shouldPin = pinnedIds.contains(m.id);
          if (m.isPinned != shouldPin) {
            list[i] = m.copyWith(isPinned: shouldPin);
          }
        }
      }
      notifyListeners();
    } catch (_) {
      // Закрепления не критичны для переписки.
    }
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
    if (idx < 0) return;
    final chat = _chats.removeAt(idx);
    _chats.insert(0, chat);
    _sortChats();
    notifyListeners();
  }

  void _sortChats() {
    _chats.sort(Chat.compareForList);
  }

  /// Создание группового чата через API.
  Future<Chat?> createGroup({
    required String title,
    required List<int> userIds,
    String? description,
  }) async {
    final userId = _selfUserId;
    if (userId == null || userIds.isEmpty) return null;

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
    _sortChats();
    notifyListeners();
    return chat;
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
          isPinned: chat.isPinned,
        );
        _chats.insert(0, withAvatar);
        _sortChats();
        notifyListeners();
        return withAvatar;
      }
      _chats.insert(0, chat);
      _sortChats();
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
      _pinnedMessages.remove(chatId);
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
        _pinnedMessages.remove(chatId);
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

    final existingIdx =
        _messages[chatId]?.indexWhere((m) => m.id == messageId) ?? -1;
    final existing = existingIdx >= 0 ? _messages[chatId]![existingIdx] : null;
    if (existing != null && !existing.canStillEdit) {
      _lastActionError =
          'Редактирование доступно в течение 15 минут после отправки';
      notifyListeners();
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
          list[idx] = updated.copyWith(
            replyTo: list[idx].replyTo,
            forwardOf: list[idx].forwardOf,
            readByRecipients: list[idx].readByRecipients,
            reactions: list[idx].reactions,
            isEdited: true,
            files: updated.files.isNotEmpty ? updated.files : list[idx].files,
            isPinned: list[idx].isPinned,
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

    final list = _messages[chatId];
    final idx = list?.indexWhere((m) => m.id == messageId) ?? -1;
    if (idx >= 0 && !list![idx].canStillDelete) {
      _lastActionError = 'Удаление доступно в течение часа после отправки';
      notifyListeners();
      return false;
    }

    try {
      _lastActionError = null;
      await ChatManagementRepository.instance.deleteMessage(
        chatIntId,
        messageIntId,
      );
      if (idx >= 0) {
        list![idx] = list[idx].copyWithDeleted();
      }
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
      isPinned: c.isPinned,
      draftText: c.draftText,
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

  /// Недописанный текст в композере чата — обновляется по мере ввода в
  /// [ChatConversationScreen], чтобы список чатов сразу показывал
  /// "Черновик: …" (см. [ChatDraftService]).
  Future<void> setDraftText(String chatId, String text) async {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    final next = text.trim().isEmpty ? null : text;
    if (idx >= 0 && _chats[idx].draftText != next) {
      _chats[idx] = _chats[idx].copyWithDraft(next);
      notifyListeners();
    }
    await ChatDraftService.instance.setDraft(chatId, text);
  }

  Future<bool> togglePin(String chatId) async {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx < 0) return false;
    final chatIntId = int.tryParse(chatId);
    if (chatIntId == null) return false;

    final next = !_chats[idx].isPinned;
    _chats[idx] = _chats[idx].copyWithDetails(isPinned: next);
    _sortChats();
    notifyListeners();

    try {
      _lastActionError = null;
      if (next) {
        await ChatManagementRepository.instance.pinChat(chatIntId);
      } else {
        await ChatManagementRepository.instance.unpinChat(chatIntId);
      }
      return true;
    } on ApiException catch (e) {
      final rollbackIdx = _chats.indexWhere((c) => c.id == chatId);
      if (rollbackIdx >= 0) {
        _chats[rollbackIdx] = _chats[rollbackIdx].copyWithDetails(
          isPinned: !next,
        );
        _sortChats();
      }
      _lastActionError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      final rollbackIdx = _chats.indexWhere((c) => c.id == chatId);
      if (rollbackIdx >= 0) {
        _chats[rollbackIdx] = _chats[rollbackIdx].copyWithDetails(
          isPinned: !next,
        );
        _sortChats();
      }
      _lastActionError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> pinMessage(String chatId, String messageId) async {
    return _setMessagePinned(chatId, messageId, pinned: true);
  }

  Future<bool> unpinMessage(String chatId, String messageId) async {
    return _setMessagePinned(chatId, messageId, pinned: false);
  }

  Future<bool> _setMessagePinned(
    String chatId,
    String messageId, {
    required bool pinned,
  }) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    final messageIntId = int.tryParse(messageId);
    if (userId == null || chatIntId == null || messageIntId == null) {
      return false;
    }

    try {
      _lastActionError = null;
      if (pinned) {
        await ChatManagementRepository.instance.pinMessage(
          chatIntId,
          messageIntId,
        );
      } else {
        await ChatManagementRepository.instance.unpinMessage(
          chatIntId,
          messageIntId,
        );
      }

      final list = _messages[chatId];
      final idx = list?.indexWhere((m) => m.id == messageId) ?? -1;
      if (idx >= 0) {
        list![idx] = list[idx].copyWith(isPinned: pinned);
      }
      await loadPinnedMessages(chatId);
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

    // Показываем сообщение в ленте сразу, не дожидаясь ответа сервера —
    // иначе при заметной задержке пользователь решает, что тап мимо кнопки
    // не сработал, и отправляет то же самое повторно (дублирование).
    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    _appendMessage(
      chatId,
      ChatMessage(
        id: tempId,
        chatId: chatId,
        authorName: '',
        isOutgoing: true,
        createdAt: DateTime.now(),
        text: t,
        replyTo: replyTo,
        isRead: true,
        isSending: true,
      ),
    );

    try {
      final sent = await ChatRepository.instance.sendTextMessage(
        chatIntId,
        text: t,
        currentUserId: userId,
        repliedMessageId: repliedId,
      );

      _removeLocalMessage(chatId, tempId);
      _appendMessage(
        chatId,
        sent.copyWith(
          text: sent.text ?? t,
          replyTo: replyTo,
          isRead: true,
        ),
      );
    } catch (e) {
      _removeLocalMessage(chatId, tempId);
      rethrow;
    }
  }

  /// Убирает локальное оптимистичное сообщение (по временному id), не трогая
  /// уже подтверждённые сервером сообщения.
  void _removeLocalMessage(String chatId, String tempId) {
    final list = _messages[chatId];
    if (list == null) return;
    final removed = list.any((m) => m.id == tempId);
    list.removeWhere((m) => m.id == tempId);
    if (removed) notifyListeners();
  }

  Future<void> sendMedia(
    String chatId, {
    required List<int> bytes,
    required String fileName,
    String? caption,
    MessageReference? replyTo,
  }) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(chatId);
    if (userId == null || chatIntId == null) return;
    if (bytes.isEmpty) {
      throw ApiException(400, 'Файл пустой');
    }
    if (bytes.length > ChatFile.maxSizeBytes) {
      throw ApiException(400, 'Файл больше 10 МБ');
    }

    final uploaded = await ChatRepository.instance.uploadFile(
      chatId: chatIntId,
      bytes: bytes,
      filename: fileName,
    );
    final repliedId = replyTo != null ? int.tryParse(replyTo.messageId) : null;
    final sent = await ChatRepository.instance.sendMessage(
      chatIntId,
      text: caption ?? '',
      currentUserId: userId,
      repliedMessageId: repliedId,
      fileIds: [uploaded.id],
    );
    _appendMessage(
      chatId,
      sent.copyWith(
        replyTo: replyTo ?? sent.replyTo,
        isRead: true,
        files: sent.files.isNotEmpty ? sent.files : [uploaded],
      ),
    );
  }

  Future<bool> forwardMessage(
    String targetChatId,
    ChatMessage source, {
    required String sourceChatId,
  }) async {
    final userId = _selfUserId;
    final chatIntId = int.tryParse(targetChatId);
    final sourceMessageId = int.tryParse(source.id);
    if (userId == null || chatIntId == null || sourceMessageId == null) {
      return false;
    }

    final text = source.text?.trim();
    if (text == null || text.isEmpty) {
      _lastActionError = 'Пересылка вложений пока не поддерживается';
      notifyListeners();
      return false;
    }

    try {
      _lastActionError = null;
      final sent = await ChatRepository.instance.sendTextMessage(
        chatIntId,
        text: text,
        currentUserId: userId,
        forwardedMessageId: sourceMessageId,
      );

      _appendMessage(
        targetChatId,
        sent.copyWith(
          text: sent.text ?? text,
          forwardOf: sent.forwardOf ??
              MessageReference(
                messageId: source.id,
                authorName: source.authorName,
                textPreview: text,
              ),
          isRead: true,
        ),
      );
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

  void _upsertLastMessage(String chatId) {
    final list = _messages[chatId];
    if (list == null || list.isEmpty) return;
    final last = list.last;
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx < 0) return;
    _chats[idx] = _chats[idx].withPreviewFromMessage(
      last,
      _messagePreview(last),
    );
    _sortChats();
  }

  void _appendMessage(String chatId, ChatMessage m) {
    _upsertMessage(chatId, m, increaseUnread: false);
  }

  /// Локальное системное сообщение (например, о звонке) — существует только
  /// в этой сессии приложения, на сервер не отправляется и не синхронизируется
  /// с другими устройствами/собеседником. [id] должен быть уникальным
  /// (например, привязан к callId), чтобы не задублировать сообщение.
  void appendLocalSystemMessage(String chatId, String text, {required String id}) {
    _appendMessage(
      chatId,
      ChatMessage(
        id: id,
        chatId: chatId,
        authorName: '',
        isOutgoing: false,
        createdAt: DateTime.now(),
        text: text,
        isSystem: true,
        isRead: true,
      ),
    );
  }

  /// Событие Reverb / Echo: новое, правка, удаление, прочтение, состав чата.
  void applyRealtimeEvent({
    required String eventName,
    required Map<String, dynamic> data,
    String? channelName,
  }) {
    final userId = _selfUserId;
    if (userId == null) return;

    var kind = ChatRealtimePayload.classifyEvent(eventName);
    final messageJson = ChatRealtimePayload.extractMessage(data);
    if (kind == ChatRealtimeKind.unknown && messageJson != null) {
      kind = ChatRealtimeKind.created;
    }

    final chatId = ChatRealtimePayload.extractChatId(
      data,
      channelName: channelName,
    );
    if (chatId == null) {
      if (kind == ChatRealtimeKind.members || kind == ChatRealtimeKind.unknown) {
        unawaited(refreshChats(showLoading: false));
      }
      return;
    }

    switch (kind) {
      case ChatRealtimeKind.deleted:
        final messageId = ChatRealtimePayload.extractMessageId(data);
        if (messageId != null) {
          _applyRemoteDeleted(chatId, messageId);
        } else {
          unawaited(refreshChats(showLoading: false));
        }
        return;
      case ChatRealtimeKind.read:
        _applyRemoteRead(chatId, ChatRealtimePayload.extractUserId(data));
        return;
      case ChatRealtimeKind.members:
        unawaited(refreshChatDetails(chatId));
        return;
      case ChatRealtimeKind.updated:
      case ChatRealtimeKind.created:
      case ChatRealtimeKind.unknown:
        break;
    }

    if (messageJson == null) {
      unawaited(refreshChats(showLoading: false));
      if (_messages.containsKey(chatId) || _activeChatId == chatId) {
        unawaited(loadMessages(chatId, force: true, showLoading: false));
      }
      return;
    }

    final mapped = ChatMapper.mapMessage(
      messageJson,
      chatId: chatId,
      currentUserId: userId,
    );
    if (mapped.id.isEmpty) return;

    if (kind == ChatRealtimeKind.updated) {
      _upsertMessage(chatId, mapped.copyWith(isEdited: true), increaseUnread: false);
      return;
    }

    _upsertMessage(
      chatId,
      mapped,
      increaseUnread: !mapped.isOutgoing && _activeChatId != chatId,
    );
    if (!mapped.isOutgoing && _activeChatId == chatId) {
      unawaited(markChatRead(chatId));
    }
  }

  Future<void> applyPushForChat(String chatId) async {
    if (chatId.isEmpty) return;
    unawaited(refreshChats(showLoading: false));
    if (_activeChatId == chatId || _messages.containsKey(chatId)) {
      await loadMessages(chatId, force: true, showLoading: false);
      if (_activeChatId == chatId) {
        unawaited(markChatRead(chatId));
      }
    }
  }

  Future<void> reloadCachedMessages() async {
    final ids = {
      ..._messages.keys.where((id) => _messages[id]?.isNotEmpty == true),
      if (_activeChatId != null) _activeChatId!,
    };
    for (final id in ids) {
      unawaited(loadMessages(id, force: true, showLoading: false));
    }
  }

  void _applyRemoteDeleted(String chatId, String messageId) {
    final list = _messages[chatId];
    final idx = list?.indexWhere((m) => m.id == messageId) ?? -1;
    if (idx >= 0) {
      list![idx] = list[idx].copyWithDeleted();
      _upsertLastMessage(chatId);
      notifyListeners();
    }
  }

  void _applyRemoteRead(String chatId, int? readerId) {
    if (readerId == null || readerId == _selfUserId) {
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx >= 0 && _chats[idx].unreadCount > 0) {
        _chats[idx] = _chats[idx].copyWithUnreadCount(0);
      }
      final list = _messages[chatId];
      if (list != null) {
        for (var i = 0; i < list.length; i++) {
          final m = list[i];
          if (!m.isOutgoing && !m.isRead) {
            list[i] = m.copyWithReadState(isRead: true);
          }
        }
      }
      notifyListeners();
      return;
    }

    final list = _messages[chatId];
    if (list == null) return;
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      if (m.isOutgoing && !m.readByRecipients) {
        list[i] = m.copyWithReadState(readByRecipients: true);
        changed = true;
      }
    }
    if (changed && list.isNotEmpty && list.last.isOutgoing) {
      final chatIdx = _chats.indexWhere((c) => c.id == chatId);
      if (chatIdx >= 0 && !_chats[chatIdx].lastMessageReadByRecipients) {
        _chats[chatIdx] = _chats[chatIdx].copyWithPreview(
          lastMessageReadByRecipients: true,
        );
      }
    }
    if (changed) notifyListeners();
  }

  void _upsertMessage(
    String chatId,
    ChatMessage incoming, {
    required bool increaseUnread,
  }) {
    var chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx < 0) {
      unawaited(refreshChats(showLoading: false));
    }

    var replaced = false;
    final list = _messages.putIfAbsent(chatId, () => <ChatMessage>[]);
    final idx = list.indexWhere((m) => m.id == incoming.id);
    if (idx >= 0) {
      replaced = true;
      final prev = list[idx];
      list[idx] = incoming.copyWith(
        replyTo: incoming.replyTo ?? prev.replyTo,
        forwardOf: incoming.forwardOf ?? prev.forwardOf,
        reactions: prev.reactions,
        isPinned: incoming.isPinned || prev.isPinned,
        readByRecipients: incoming.readByRecipients || prev.readByRecipients,
      );
    } else {
      var message = incoming;
      final replyId = incoming.repliedMessageId;
      if (replyId != null && incoming.replyTo == null) {
        for (final existing in list) {
          if (existing.id == replyId) {
            message = incoming.copyWith(
              replyTo: MessageReference(
                messageId: existing.id,
                authorName: existing.authorName,
                textPreview: ChatMapper.snippet(existing),
              ),
            );
            break;
          }
        }
      }
      list.add(message);
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx < 0) {
      notifyListeners();
      return;
    }

    if (increaseUnread && !replaced) {
      _chats[chatIdx] = _chats[chatIdx].copyWithUnreadCount(
        _chats[chatIdx].unreadCount + 1,
      );
    }

    if (replaced) {
      _upsertLastMessage(chatId);
    } else {
      _chats[chatIdx] = _chats[chatIdx].withPreviewFromMessage(
        incoming,
        _messagePreview(incoming),
      );
      _sortChats();
    }
    notifyListeners();
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> fromServer,
    List<ChatMessage>? previous,
  ) {
    if (previous == null || previous.isEmpty) {
      final sorted = List<ChatMessage>.from(fromServer)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return ChatMapper.attachReplyReferences(sorted).toList();
    }
    final merged = List<ChatMessage>.from(fromServer);
    final ids = {for (final m in merged) m.id};
    for (final m in previous) {
      if (m.id.isEmpty || !ids.add(m.id)) continue;
      merged.add(m);
    }
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ChatMapper.attachReplyReferences(merged).toList();
  }

  int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}

extension on Chat {
  Chat withPreviewFromMessage(ChatMessage m, String? preview) {
    return copyWithPreview(
      lastMessagePreview: preview,
      lastMessageAt: m.createdAt,
      lastMessageIsOutgoing: m.isOutgoing,
      lastMessageReadByRecipients: m.readByRecipients,
    );
  }
}
