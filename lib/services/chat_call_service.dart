import 'dart:async';

import 'package:connect/config/call_config.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_active_call.dart';
import 'package:connect/models/chat/chat_call_status.dart';
import 'package:connect/models/chat_message.dart';
import 'package:connect/repositories/chat_call_repository.dart';
import 'package:connect/repositories/connector_repository.dart';
import 'package:connect/screens/outgoing_call_screen.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/services/connector_invite_service.dart';
import 'package:connect/services/incoming_call_service.dart';
import 'package:connect/services/jitsi_meeting_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/utils/connector_launch.dart';
import 'package:connect/utils/connector_url_utils.dart';
import 'package:flutter/cupertino.dart';

/// Звонки из чатов: групповые (ссылка + плашка) и личные 1:1 (CallKit, без сообщения).
class ChatCallService extends ChangeNotifier {
  ChatCallService._();
  static final ChatCallService instance = ChatCallService._();

  static const _inviteMaxAge = Duration(hours: 6);
  static const _pollInterval = Duration(seconds: 20);

  final Map<String, ChatActiveCall> _activeByChat = {};
  final Map<String, Timer> _pollTimers = {};
  final Set<String> _watchingChats = {};
  final Map<String, ChatCallStatus> _endedCalls = {};
  final Set<String> _acceptedCalls = {};
  final Set<String> _ringingCalls = {};
  bool _startingCall = false;

  /// callId исходящих 1:1 звонков, начатых с этого устройства. Нужен, чтобы
  /// отличать «собеседник ответил» (мы звонили) от «ответили на другом нашем
  /// устройстве» (звонили нам) при одном и том же событии `accepted`.
  final Set<String> _outgoingCallIds = {};

  /// callId 1:1 звонков, для которых уже показано локальное сообщение
  /// "Начат звонок" — используется, чтобы показать ровно одно сообщение
  /// о завершении и не показывать его для звонков без ответа.
  final Set<String> _callsWithStartMessage = {};

  /// callId активного 1:1 звонка в Jitsi (чтобы hangUp по push).
  String? _liveDirectCallId;
  Timer? _heartbeatTimer;

  bool get isStartingCall => _startingCall;

  /// Пользователь уже занят звонком на этом устройстве: дозвон, разговор
  /// или вход в комнату. Новый входящий 1:1 в этот момент отклоняется как `busy`.
  bool get isBusy =>
      _startingCall ||
      _liveDirectCallId != null ||
      JitsiMeetingService.instance.isInConference;

  /// callId текущего 1:1 разговора на этом устройстве.
  String? get liveDirectCallId => _liveDirectCallId;

  ChatActiveCall? activeCallFor(String chatId) => _activeByChat[chatId];

  /// Плашку показываем только для групповых звонков.
  ChatActiveCall? bannerCallFor(String chatId) {
    final call = _activeByChat[chatId];
    if (call == null || call.isDirect) return null;
    return call;
  }

  ChatCallStatus? endedStatusFor(String callId) => _endedCalls[callId];

  bool isAccepted(String callId) => _acceptedCalls.contains(callId);

  /// Собеседник получил звонок хотя бы на одном устройстве (для «Вызов…»).
  bool isRinging(String callId) => _ringingCalls.contains(callId);

  bool isOutgoing(String callId) => _outgoingCallIds.contains(callId);

  /// Единая точка входа для статусов звонка из push, VoIP, Reverb,
  /// опроса `GET /chat/call/{id}` и heartbeat. Повторные и запоздавшие
  /// события безопасны: финальный статус фиксируется один раз.
  void applySignal(ChatCallSignal signal) {
    final callId = signal.callId;
    AppLogger.d('Call signal: $signal', name: 'chat.call');

    if (_endedCalls.containsKey(callId)) return;

    switch (signal.status) {
      case ChatCallStatus.calling:
        return;
      case ChatCallStatus.ringing:
        if (_outgoingCallIds.contains(callId) && _ringingCalls.add(callId)) {
          notifyListeners();
        }
        return;
      case ChatCallStatus.accepted:
        if (_outgoingCallIds.contains(callId)) {
          if (_acceptedCalls.add(callId)) notifyListeners();
          return;
        }
        // Звонили нам, а приняли не здесь — веб или другое наше устройство.
        if (IncomingCallService.instance.isAcceptedLocally(callId)) return;
        if (_liveDirectCallId == callId) return;
        _finish(callId, ChatCallStatus.answeredElsewhere);
        return;
      case ChatCallStatus.answeredElsewhere:
      case ChatCallStatus.declinedElsewhere:
        // На устройстве, которое само приняло звонок, это событие не гасит разговор.
        if (_liveDirectCallId == callId ||
            IncomingCallService.instance.isAcceptedLocally(callId)) {
          return;
        }
        _finish(callId, signal.status);
        return;
      case ChatCallStatus.declined:
      case ChatCallStatus.cancelled:
      case ChatCallStatus.missed:
      case ChatCallStatus.busy:
      case ChatCallStatus.ended:
      case ChatCallStatus.failed:
        _finish(callId, signal.status);
        return;
    }
  }

  /// Звонок завершён с любой стороны: зафиксировать статус, убрать CallKit,
  /// выйти из Jitsi, если идёт разговор.
  void notifyCallEnded(String callId, ChatCallStatus status) {
    if (_endedCalls.containsKey(callId)) return;
    _finish(callId, status);
  }

  void _finish(String callId, ChatCallStatus status) {
    _endedCalls[callId] = status;
    _ringingCalls.remove(callId);
    _appendCallEndedMessage(callId);
    _clearActiveByCallId(callId);
    unawaited(_hangUpRemote(callId));
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

      if (isDirect) {
        final ring = await ChatCallRepository.instance.ringDirectCall(
          chatId: chat.id,
          room: session.room,
          topic: topic,
        );
        final callId = ring.callId;
        final ringStatus = ring.status;
        if (callId != null) {
          _outgoingCallIds.add(callId);
          // `busy` — собеседник занят; `accepted` — встречный вызов, сервер
          // склеил его с нашим, и можно сразу входить в комнату.
          if (ringStatus == ChatCallStatus.accepted) _acceptedCalls.add(callId);
          if (ringStatus != null && ringStatus.isFinal) {
            _endedCalls[callId] = ringStatus;
          }
        }
        final ringFailure = callId == null
            ? (ringStatus ?? ChatCallStatus.failed)
            : (ringStatus != null && ringStatus.isFinal ? ringStatus : null);

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

        // Без call_id собеседник звонок не получил — сразу показываем причину,
        // а не 30 секунд гудков в пустоту.
        final outcome = await _showOutgoingCallScreen(
          chat: chat,
          callId: callId,
          initialFailure: ringFailure,
        );

        if (outcome != OutgoingCallOutcome.proceed) {
          final reason = switch (outcome) {
            OutgoingCallOutcome.timeout => ChatCallEndReason.timeout,
            _ => ChatCallEndReason.cancelled,
          };
          // Если звонок уже завершила другая сторона/сервер, повторно не шлём.
          if (callId != null && !_endedCalls.containsKey(callId)) {
            _endedCalls[callId] = outcome == OutgoingCallOutcome.timeout
                ? ChatCallStatus.missed
                : ChatCallStatus.cancelled;
            unawaited(
              ChatCallRepository.instance.endCall(callId, reason: reason),
            );
          }
          _activeByChat.remove(chat.id);
          notifyListeners();
          return;
        }

        _liveDirectCallId = callId;
        _appendCallStartedMessage(chat.id, callId);
        _startHeartbeat(callId);
        final peer = peerFor(chat.id);
        await openConnectorSession(
          session,
          callId: callId,
          endWhenLeave: true,
          // Собеседник уже ответил и вошёл в комнату раньше нас.
          peerAnswered: true,
          title: peer.title,
          avatarUrl: peer.avatarUrl,
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
    ChatCallStatus? initialFailure,
  }) async {
    final navigator = AppNavigationService.navigatorKey.currentState;
    if (navigator == null) {
      return callId == null
          ? OutgoingCallOutcome.failed
          : OutgoingCallOutcome.proceed;
    }

    final result = await navigator.push<OutgoingCallOutcome>(
      CupertinoPageRoute<OutgoingCallOutcome>(
        fullscreenDialog: true,
        builder: (_) => OutgoingCallScreen(
          chat: chat,
          callId: callId,
          initialFailure: initialFailure,
        ),
      ),
    );
    return result ?? OutgoingCallOutcome.cancelled;
  }

  /// Опрос статуса исходящего звонка — страховка, если push/сокет потерялся.
  Future<void> pollCallStatus(String callId) async {
    if (_endedCalls.containsKey(callId)) return;
    final status = await ChatCallRepository.instance.fetchStatus(callId);
    if (status == null) return;
    applySignal(ChatCallSignal(callId: callId, status: status));
  }

  Future<void> joinActiveCall(ChatActiveCall call) async {
    final session = await ConnectorRepository.instance.join(call.room);
    if (call.isDirect) {
      _liveDirectCallId = call.callId;
      _startHeartbeat(call.callId);
      final peer = peerFor(call.chatId);
      await openConnectorSession(
        session,
        callId: call.callId,
        endWhenLeave: true,
        // Возврат в свой звонок: собеседник уже на линии. Входящий —
        // звонящий ждёт ответа и войдёт после нас.
        peerAnswered: !call.isIncoming,
        title: peer.title,
        avatarUrl: peer.avatarUrl,
      );
    } else {
      await openConnectorSession(session);
    }
  }

  /// Имя и аватар собеседника 1:1 для экрана звонка — из списка чатов.
  ({String? title, String? avatarUrl}) peerFor(String? chatId) {
    final chat = chatId == null ? null : ChatService.instance.chatById(chatId);
    if (chat == null) return (title: null, avatarUrl: null);
    final peerAvatar = chat.peerAvatarUrl?.trim();
    return (
      title: chat.title,
      avatarUrl: peerAvatar != null && peerAvatar.isNotEmpty
          ? peerAvatar
          : chat.avatarUrl,
    );
  }

  /// Локальный выход из Jitsi: завершить звонок на бэкенде для обеих сторон.
  Future<void> onLocalCallLeft(
    String? callId, {
    ChatCallEndReason reason = ChatCallEndReason.hangup,
  }) async {
    final id = callId ?? _liveDirectCallId;
    if (id == null || id.isEmpty) return;
    if (_liveDirectCallId == id) {
      _liveDirectCallId = null;
      _stopHeartbeat();
    }

    _appendCallEndedMessage(id);
    _clearActiveByCallId(id);
    notifyListeners();
    // Звонок уже завершила другая сторона — сервер в курсе.
    if (_endedCalls.containsKey(id)) return;
    _endedCalls[id] = reason == ChatCallEndReason.failed
        ? ChatCallStatus.failed
        : ChatCallStatus.ended;
    await ChatCallRepository.instance.endCall(id, reason: reason);
  }

  /// Выход из аккаунта: завершить текущий разговор, пока токен ещё жив.
  Future<void> endLiveCallForLogout() async {
    final id = _liveDirectCallId;
    if (id == null) return;
    await JitsiMeetingService.instance.hangUp();
    await onLocalCallLeft(id);
  }

  void _startHeartbeat(String? callId) {
    _stopHeartbeat();
    if (callId == null || callId.isEmpty) return;
    _heartbeatTimer = Timer.periodic(CallConfig.heartbeatInterval, (_) async {
      if (_liveDirectCallId != callId) {
        _stopHeartbeat();
        return;
      }
      final status = await ChatCallRepository.instance.heartbeat(callId);
      if (status != null && status.isFinal) {
        AppLogger.d(
          'Heartbeat: call $callId is ${status.wire} on server — hanging up',
          name: 'chat.call',
        );
        applySignal(ChatCallSignal(callId: callId, status: status));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _hangUpRemote(String callId) async {
    try {
      if (_liveDirectCallId == callId) {
        _liveDirectCallId = null;
        _stopHeartbeat();
        await JitsiMeetingService.instance.hangUp();
      }
      await IncomingCallService.instance.dismissRemotely(callId);
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

    final state = await _roomState(candidate.room);
    // Комната открыта, но в ней никого нет — плашка «войти» ни к чему:
    // бэкенд не закрывает встречи, когда все вышли.
    if (!state.joinable || state.participants == 0) {
      if (_activeByChat.containsKey(chatId)) {
        _activeByChat.remove(chatId);
        notifyListeners();
      }
      return;
    }

    final fresh = candidate.copyWith(participantsCount: state.participants);
    if (cached?.room != fresh.room ||
        cached?.isIncoming != fresh.isIncoming ||
        cached?.participantsCount != fresh.participantsCount) {
      _setActiveCall(fresh);
    }
  }

  ChatActiveCall? _callFromMessages(String chatId, List<ChatMessage> messages) {
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

  /// Можно ли войти во встречу и сколько в ней людей (`null` — неизвестно).
  /// Если проверить не удалось, плашку не прячем.
  Future<({bool joinable, int? participants})> _roomState(String room) async {
    try {
      final meta = await ConnectorRepository.instance.getRoom(room);
      return (
        joinable: meta.canJoin != false,
        participants: meta.participantsCount,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return (joinable: false, participants: null);
      AppLogger.d(
        'Не удалось проверить комнату $room: ${e.message}',
        name: 'chat.call',
      );
      return (joinable: true, participants: null);
    } catch (e, st) {
      AppLogger.d(
        'Не удалось проверить комнату $room',
        name: 'chat.call',
        error: e,
        stackTrace: st,
      );
      return (joinable: true, participants: null);
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
    _appendCallStartedMessage(chatId, callId);
    _startHeartbeat(callId);
  }

  /// Локальное сообщение "Начат звонок" — только для этого устройства,
  /// без обращения к бэкенду. Нужно, пока бэкенд не прислал сообщение
  /// `CALL` этого звонка: оно персистентно и заменяет локальные записи
  /// (см. [ChatService.appendLocalSystemMessage]).
  void _appendCallStartedMessage(String chatId, String? callId) {
    if (callId == null || callId.isEmpty) return;
    if (!_callsWithStartMessage.add(callId)) return;
    if (ChatService.instance.hasServerCallMessage(chatId, callId)) return;
    ChatService.instance.appendLocalSystemMessage(
      chatId,
      'Начат звонок',
      id: 'call_start_$callId',
    );
  }

  /// Локальное сообщение "Звонок завершён · MM:SS" — показывается только
  /// если для этого callId было показано сообщение о начале (то есть звонок
  /// был реально принят, а не пропущен/отклонён), и только один раз, даже
  /// если и локальный выход из комнаты, и push о завершении сработают оба.
  void _appendCallEndedMessage(String callId) {
    if (!_callsWithStartMessage.remove(callId)) return;

    ChatActiveCall? call;
    for (final c in _activeByChat.values) {
      if (c.callId == callId) {
        call = c;
        break;
      }
    }
    if (call == null) return;
    if (ChatService.instance.hasServerCallMessage(call.chatId, callId)) return;

    final duration = DateTime.now().difference(call.startedAt);
    ChatService.instance.appendLocalSystemMessage(
      call.chatId,
      'Звонок завершён · ${_formatCallDuration(duration)}',
      id: 'call_end_$callId',
    );
  }

  String _formatCallDuration(Duration d) {
    final duration = d.isNegative ? Duration.zero : d;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}
