import 'dart:async';

import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_active_call.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/repositories/chat_call_repository.dart';
import 'package:connect/repositories/connector_repository.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/services/connector_invite_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/utils/connector_launch.dart';
import 'package:connect/utils/connector_url_utils.dart';
import 'package:flutter/foundation.dart';

/// Звонки из чатов: создание встречи, приглашение в чат, отслеживание активной комнаты.
class ChatCallService extends ChangeNotifier {
  ChatCallService._();
  static final ChatCallService instance = ChatCallService._();

  static const _inviteMaxAge = Duration(hours: 6);
  static const _pollInterval = Duration(seconds: 20);

  final Map<String, ChatActiveCall> _activeByChat = {};
  final Map<String, Timer> _pollTimers = {};
  final Set<String> _watchingChats = {};
  bool _startingCall = false;

  bool get isStartingCall => _startingCall;

  ChatActiveCall? activeCallFor(String chatId) => _activeByChat[chatId];

  /// Подписка на обновление активного звонка, пока открыт экран чата.
  void watchChat(String chatId) {
    if (_watchingChats.add(chatId)) {
      _pollTimers[chatId]?.cancel();
      _pollTimers[chatId] = Timer.periodic(_pollInterval, (_) {
        unawaited(_refreshChat(chatId));
      });
    }
    unawaited(_refreshChat(chatId));
  }

  void unwatchChat(String chatId) {
    _watchingChats.remove(chatId);
    _pollTimers.remove(chatId)?.cancel();
  }

  /// Создаёт встречу, отправляет ссылку в чат, регистрирует активный звонок.
  Future<void> startCallFromChat(Chat chat) async {
    if (_startingCall) return;
    _startingCall = true;
    notifyListeners();

    try {
      final chatService = ChatService.instance;
      await chatService.init();

      final selfId = chatService.selfUserId;
      final memberIds = chat.isGroup
          ? chat.members
                .map((m) => m.userId)
                .where((id) => selfId == null || id != selfId)
                .toList()
          : chat.peerUserId != null
          ? [chat.peerUserId!]
          : <int>[];

      final topic = chat.isGroup ? chat.title : 'Звонок с ${chat.title}';

      final session = await ConnectorRepository.instance.createInstant(
        topic: topic,
        userIds: memberIds,
      );

      await ConnectorInviteService.instance.inviteChat(
        chatId: chat.id,
        session: session,
        topic: topic,
      );

      if (!chat.isGroup) {
        await ChatCallRepository.instance.ringDirectCall(
          chatId: chat.id,
          room: session.room,
          topic: topic,
        );
      }

      _setActiveCall(
        ChatActiveCall(
          chatId: chat.id,
          room: session.room,
          topic: topic,
          startedAt: DateTime.now(),
          isIncoming: false,
        ),
      );

      await openConnectorSession(session);
    } finally {
      _startingCall = false;
      notifyListeners();
    }
  }

  Future<void> joinActiveCall(ChatActiveCall call) async {
    final session = await ConnectorRepository.instance.join(call.room);
    await openConnectorSession(session);
  }

  Future<void> _refreshChat(String chatId) async {
    final chatService = ChatService.instance;
    final messages = chatService.messagesFor(chatId);
    final selfId = chatService.selfUserId;

    final fromMessages = _callFromMessages(chatId, messages, selfId);
    final cached = _activeByChat[chatId];

    final candidate = _pickNewerCall(fromMessages, cached);
    if (candidate == null) {
      if (cached != null) {
        _activeByChat.remove(chatId);
        notifyListeners();
      }
      return;
    }

    if (DateTime.now().difference(candidate.startedAt) > _inviteMaxAge) {
      if (cached != null) {
        _activeByChat.remove(chatId);
        notifyListeners();
      }
      return;
    }

    final stillActive = await _isRoomJoinable(candidate.room);
    if (!stillActive) {
      if (_activeByChat.containsKey(chatId)) {
        _activeByChat.remove(chatId);
        notifyListeners();
      }
      return;
    }

    if (cached?.room != candidate.room ||
        cached?.isIncoming != candidate.isIncoming) {
      _setActiveCall(candidate);
    }
  }

  ChatActiveCall? _callFromMessages(
    String chatId,
    List<ChatMessage> messages,
    int? selfUserId,
  ) {
    ChatActiveCall? latest;
    for (final m in messages) {
      if (m.isDeleted || m.isSystem) continue;
      if (DateTime.now().difference(m.createdAt) > _inviteMaxAge) continue;

      final room = connectorRoomFromText(m.text);
      if (room == null) continue;

      final text = m.text ?? '';
      final looksLikeInvite =
          text.contains('видеовстреч') || text.contains('/connector/');
      if (!looksLikeInvite) continue;

      final incoming = !m.isOutgoing;
      final call = ChatActiveCall(
        chatId: chatId,
        room: room,
        topic: _topicFromInviteText(text),
        startedAt: m.createdAt,
        isIncoming: incoming,
      );

      if (latest == null || call.startedAt.isAfter(latest.startedAt)) {
        latest = call;
      }
    }
    return latest;
  }

  ChatActiveCall? _pickNewerCall(
    ChatActiveCall? fromMessages,
    ChatActiveCall? cached,
  ) {
    if (fromMessages == null) return cached;
    if (cached == null) return fromMessages;
    return fromMessages.startedAt.isAfter(cached.startedAt)
        ? fromMessages
        : cached;
  }

  String? _topicFromInviteText(String text) {
    final match = RegExp(r'«([^»]+)»').firstMatch(text);
    return match?.group(1)?.trim();
  }

  Future<bool> _isRoomJoinable(String room) async {
    try {
      final meta = await ConnectorRepository.instance.getRoom(room);
      if (meta.canJoin == false) return false;
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return false;
      AppLogger.d(
        'Не удалось проверить комнату $room: ${e.message}',
        name: 'chat.call',
      );
      return true;
    } catch (e, st) {
      AppLogger.d(
        'Не удалось проверить комнату $room',
        name: 'chat.call',
        error: e,
        stackTrace: st,
      );
      return true;
    }
  }

  void _setActiveCall(ChatActiveCall call) {
    _activeByChat[call.chatId] = call;
    notifyListeners();
  }
}
