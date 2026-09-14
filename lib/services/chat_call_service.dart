import 'dart:async';

import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_active_call.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/repositories/chat_call_repository.dart';
import 'package:connect/repositories/connector_repository.dart';
import 'package:connect/screens/outgoing_call_screen.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/services/connector_invite_service.dart';
import 'package:connect/services/jitsi_meeting_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/utils/connector_launch.dart';
import 'package:connect/utils/connector_url_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Звонки из чатов: групповые (ссылка + плашка) и личные 1:1 (CallKit, без сообщения).
class ChatCallService extends ChangeNotifier {
  ChatCallService._();
  static final ChatCallService instance = ChatCallService._();

  static const _inviteMaxAge = Duration(hours: 6);
  static const _pollInterval = Duration(seconds: 20);

  final Map<String, ChatActiveCall> _activeByChat = {};
  final Map<String, Timer> _pollTimers = {};
  final Set<String> _watchingChats = {};
  final Map<String, String> _endedCalls = {};
  final Set<String> _acceptedCalls = {};
  bool _startingCall = false;

  /// callId активного 1:1 звонка в Jitsi (чтобы hangUp по push).
  String? _liveDirectCallId;

  bool get isStartingCall => _startingCall;

  ChatActiveCall? activeCallFor(String chatId) => _activeByChat[chatId];

  /// Плашку показываем только для групповых звонков.
  ChatActiveCall? bannerCallFor(String chatId) {
    final call = _activeByChat[chatId];
    if (call == null || call.isDirect) return null;
    return call;
  }

  String? endedStatusFor(String callId) => _endedCalls[callId];

  bool isAccepted(String callId) => _acceptedCalls.contains(callId);

  void notifyCallEnded(String callId, String status) {
    _endedCalls[callId] = status;
    _clearActiveByCallId(callId);
    unawaited(_hangUpRemote(callId));
    notifyListeners();
  }

  void notifyCallAccepted(String callId) {
    _acceptedCalls.add(callId);
    notifyListeners();
  }

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

  /// Создаёт встречу и стартует звонок.
  ///
  /// Личный чат: без сообщения в ленту, ring → CallKit/исходящий экран.
  /// Группа: ссылка в чат + плашка.
  Future<void> startCallFromChat(Chat chat) async {
    if (_startingCall) return;
    _startingCall = true;
    notifyListeners();

    try {
      if (!chat.isGroup) {
        final perms = await CallPermissions.ensureForOutgoingCall();
        if (!perms.canStartCall) {
          throw ApiException(
            403,
            perms.denialMessage ?? 'Нет разрешений для звонка',
          );
        }
      }

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
      final isDirect = !chat.isGroup;

      final session = await ConnectorRepository.instance.createInstant(
        topic: topic,
        userIds: memberIds,
        isPrivate: isDirect,
        chatId: isDirect ? chat.id : null,
      );

      // Группам — ссылка в чат. Личным — только системный звонок, без сообщения.
      if (!isDirect) {
        await ConnectorInviteService.instance.inviteChat(
          chatId: chat.id,
          session: session,
          topic: topic,
        );
      }

      String? callId;
      if (isDirect) {
        callId = await ChatCallRepository.instance.ringDirectCall(
          chatId: chat.id,
          room: session.room,
          topic: topic,
        );

        _setActiveCall(
          ChatActiveCall(
            chatId: chat.id,
            room: session.room,
            topic: topic,
            startedAt: DateTime.now(),
            isIncoming: false,
            callId: callId,
            isDirect: true,
          ),
        );

        final outcome = await _showOutgoingCallScreen(
          chat: chat,
          callId: callId,
        );

        if (outcome != OutgoingCallOutcome.proceed) {
          if (callId != null) {
            unawaited(ChatCallRepository.instance.endCall(callId));
          }
          _activeByChat.remove(chat.id);
          notifyListeners();
          return;
        }

        _liveDirectCallId = callId;
        await openConnectorSession(
          session,
          callId: callId,
          endWhenLeave: true,
        );
        return;
      }

      _setActiveCall(
        ChatActiveCall(
          chatId: chat.id,
          room: session.room,
          topic: topic,
          startedAt: DateTime.now(),
          isIncoming: false,
          isDirect: false,
        ),
      );

      await openConnectorSession(session);
    } finally {
      _startingCall = false;
      notifyListeners();
    }
  }

  Future<OutgoingCallOutcome> _showOutgoingCallScreen({
    required Chat chat,
    required String? callId,
  }) async {
    final navigator = AppNavigationService.navigatorKey.currentState;
    if (navigator == null) return OutgoingCallOutcome.proceed;

    final result = await navigator.push<OutgoingCallOutcome>(
      CupertinoPageRoute<OutgoingCallOutcome>(
        fullscreenDialog: true,
        builder: (_) => OutgoingCallScreen(chat: chat, callId: callId),
      ),
    );
    return result ?? OutgoingCallOutcome.cancelled;
  }

  Future<void> joinActiveCall(ChatActiveCall call) async {
    final session = await ConnectorRepository.instance.join(call.room);
    if (call.isDirect) {
      _liveDirectCallId = call.callId;
      await openConnectorSession(
        session,
        callId: call.callId,
        endWhenLeave: true,
      );
    } else {
      await openConnectorSession(session);
    }
  }

  /// Локальный выход из Jitsi: завершить звонок на бэкенде для обеих сторон.
  Future<void> onLocalCallLeft(String? callId) async {
    final id = callId ?? _liveDirectCallId;
    _liveDirectCallId = null;
    if (id == null || id.isEmpty) return;

    _clearActiveByCallId(id);
    notifyListeners();
    await ChatCallRepository.instance.endCall(id);
  }

  Future<void> _hangUpRemote(String callId) async {
    try {
      if (_liveDirectCallId == callId) {
        _liveDirectCallId = null;
        await JitsiMeetingService.instance.hangUp();
      }
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e, st) {
      AppLogger.d(
        'hangUp after call ended failed',
        name: 'chat.call',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _clearActiveByCallId(String callId) {
    final keys = _activeByChat.entries
        .where((e) => e.value.callId == callId)
        .map((e) => e.key)
        .toList();
    for (final k in keys) {
      _activeByChat.remove(k);
    }
  }

  Future<void> _refreshChat(String chatId) async {
    final chat = ChatService.instance.chatById(chatId);
    // Личные чаты: не поднимаем плашку из старых/новых сообщений.
    if (chat != null && !chat.isGroup) {
      final cached = _activeByChat[chatId];
      if (cached == null || !cached.isDirect) {
        if (cached != null && !cached.isDirect) {
          _activeByChat.remove(chatId);
          notifyListeners();
        }
      }
      return;
    }

    final messages = ChatService.instance.messagesFor(chatId);
    final fromMessages = _callFromMessages(chatId, messages);
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

      final call = ChatActiveCall(
        chatId: chatId,
        room: room,
        topic: _topicFromInviteText(text),
        startedAt: m.createdAt,
        isIncoming: !m.isOutgoing,
        isDirect: false,
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
    if (cached == null || cached.isDirect) return fromMessages;
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

  /// Регистрирует входящий 1:1 звонок (после Accept), без плашки.
  void registerIncomingDirectCall({
    required String chatId,
    required String room,
    required String callId,
    String? topic,
  }) {
    _setActiveCall(
      ChatActiveCall(
        chatId: chatId,
        room: room,
        topic: topic,
        startedAt: DateTime.now(),
        isIncoming: true,
        callId: callId,
        isDirect: true,
      ),
    );
    _liveDirectCallId = callId;
  }
}
