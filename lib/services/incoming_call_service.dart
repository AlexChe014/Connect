import 'dart:async';
import 'dart:io';

import 'package:connect/config/call_config.dart';
import 'package:connect/config/home_tabs.dart';
import 'package:connect/models/chat/chat_call_status.dart';
import 'package:connect/models/incoming_call_payload.dart';
import 'package:connect/repositories/chat_call_repository.dart';
import 'package:connect/repositories/connector_repository.dart';
import 'package:connect/repositories/device_token_repository.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/services/jitsi_meeting_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/utils/connector_launch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar, SnackBarAction, Text;
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Обработка CallKit-событий, когда приложение было в фоне/убито (Android).
@pragma('vm:entry-point')
Future<void> incomingCallBackgroundHandler(CallEvent event) async {
  if (event case CallEventActionCallAccept(:final callKitParams)) {
    await AuthService.instance.init();
    await IncomingCallService.instance.handleBackgroundAccept(callKitParams);
  }
}

/// CallKit (iOS) / ConnectionService (Android) для входящих звонков из чатов.
class IncomingCallService {
  IncomingCallService._();
  static final IncomingCallService instance = IncomingCallService._();

  /// Нативный канал из AppDelegate: вкл/выкл подписку PushKit на VoIP.
  static const _voipPushChannel = MethodChannel('connect/voip_push');
  static const _backendTimeout = Duration(seconds: 5);

  /// callId, которые погашены программно (по событию с сервера). Плагин
  /// сообщает о таком закрытии как о DECLINE/ENDED — без этого фильтра мы бы
  /// отправили `decline` и, например, сбросили звонок, принятый в вебе.
  /// Дублируется в SharedPreferences: FCM на Android приходит в отдельном
  /// фоновом изоляте, а событие CallKit — в основной.
  static const _dismissedPrefsKey = 'callkit_remote_dismissed';

  StreamSubscription<CallEvent?>? _eventSub;

  /// Звонки, отклонённые как «занято», пока шёл другой разговор: после
  /// разговора показываем «Пока вы разговаривали, вам звонили…».
  final Map<String, ({String name, String? chatId})> _missedWhileBusy = {};

  /// Последнее значение, переданное в AppDelegate (`setInCall`).
  bool? _nativeInCall;
  bool _initialized = false;
  String? _lastVoipToken;
  String? _pendingVoipToken;
  final Set<String> _acceptedLocally = {};
  final Set<String> _dismissedRemotely = {};
  final Set<String> _shownCallIds = {};
  bool _acceptInFlight = false;

  bool isAcceptedLocally(String callId) => _acceptedLocally.contains(callId);

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  Future<void> init() async {
    if (_initialized || !isSupported) return;
    _initialized = true;

    _eventSub = FlutterCallkitIncoming.onEvent.listen(_onCallEvent);

    if (Platform.isIOS) {
      _voipPushChannel.setMethodCallHandler(_onVoipChannelCall);
    }
    ChatCallService.instance.addListener(_onBusyChanged);
    JitsiMeetingService.instance.addListener(_onBusyChanged);

    if (Platform.isAndroid) {
      await FlutterCallkitIncoming.onBackgroundMessage(
        incomingCallBackgroundHandler,
      );
      try {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      } catch (e, st) {
        AppLogger.d(
          'Full intent permission request failed',
          name: 'callkit',
          error: e,
          stackTrace: st,
        );
      }
    }

    if (Platform.isIOS) {
      // Не ждём FCM: PushKit-токен регистрируем отдельно.
      unawaited(refreshVoipRegistration(force: true));
    }

    // Accept с lock screen / cold start, пока Dart ещё поднимался.
    unawaited(recoverPendingAcceptedCalls());
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    ChatCallService.instance.removeListener(_onBusyChanged);
    JitsiMeetingService.instance.removeListener(_onBusyChanged);
    _initialized = false;
  }

  /// После логина / FCM: сбросить кэш и снова отправить VoIP на бэкенд.
  Future<void> refreshVoipRegistration({bool force = false}) async {
    if (!isSupported || !Platform.isIOS) return;
    if (force) _lastVoipToken = null;

    if (AuthService.instance.isAuthenticated) {
      await _setVoipPushEnabled(true);
    }

    if (_pendingVoipToken != null &&
        _pendingVoipToken!.isNotEmpty &&
        AuthService.instance.isAuthenticated) {
      await _registerVoipToken(_pendingVoipToken!);
    }

    await _registerVoipTokenWhenReady();
  }

  /// Выход из аккаунта, пока сессия ещё жива: отвязать VoIP-токен на бэкенде.
  Future<void> unregisterVoipOnBackend() async {
    if (!isSupported || !Platform.isIOS) return;
    if (!AuthService.instance.isAuthenticated) return;

    var token = _lastVoipToken;
    if (token == null || token.isEmpty) {
      try {
        token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      } catch (_) {}
    }
    if (token == null || token.isEmpty) return;

    try {
      await DeviceTokenRepository.instance
          .unregisterVoipToken(token: token)
          .timeout(_backendTimeout);
      AppLogger.d('VoIP token unregistered on backend', name: 'callkit');
    } catch (e, st) {
      AppLogger.e(
        'Failed to unregister VoIP token',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// После выхода / истечения сессии: отписаться от VoIP-пушей на устройстве
  /// и закрыть висящие CallKit-звонки — не зависит от ответа бэкенда.
  Future<void> disableLocally() async {
    if (!isSupported) return;
    _clearVoipCache();
    if (Platform.isIOS) await _setVoipPushEnabled(false);
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e, st) {
      AppLogger.d(
        'endAllCalls on logout failed',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _clearVoipCache() {
    _lastVoipToken = null;
    _pendingVoipToken = null;
  }

  Future<void> _setVoipPushEnabled(bool enabled) async {
    try {
      await _voipPushChannel.invokeMethod<void>('setEnabled', enabled);
    } catch (e, st) {
      AppLogger.e(
        'Failed to set VoIP push enabled=$enabled',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Убрать CallKit/ConnectionService-звонок по событию с сервера (отменён,
  /// принят/отклонён на другом устройстве) — без отправки `decline`.
  Future<void> dismissRemotely(String callId) async {
    if (!isSupported || callId.isEmpty) return;
    if (_acceptedLocally.contains(callId)) {
      // Наш разговор: CallKit уже закрыт после входа в Jitsi.
      try {
        await FlutterCallkitIncoming.endCall(callId);
      } catch (_) {}
      return;
    }
    await _markDismissed(callId);
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e, st) {
      AppLogger.d(
        'dismissRemotely($callId) failed',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _markDismissed(String callId) async {
    _dismissedRemotely.add(callId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_dismissedPrefsKey) ?? <String>[];
      if (list.contains(callId)) return;
      list.add(callId);
      if (list.length > 20) list.removeRange(0, list.length - 20);
      await prefs.setStringList(_dismissedPrefsKey, list);
    } catch (_) {}
  }

  Future<bool> _consumeDismissed(String callId) async {
    if (_dismissedRemotely.remove(callId)) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final list = prefs.getStringList(_dismissedPrefsKey) ?? <String>[];
      if (!list.remove(callId)) return false;
      await prefs.setStringList(_dismissedPrefsKey, list);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Показать системный экран входящего звонка (в т.ч. на lock screen).
  Future<void> showIncomingCall(IncomingCallPayload payload) async {
    if (!isSupported) return;

    final params = CallKitParams(
      id: payload.callId,
      nameCaller: payload.callerName,
      appName: 'Connect',
      avatar: payload.callerAvatar,
      handle: payload.topic ?? payload.callerName,
      type: payload.isVideo ? 1 : 0,
      duration: CallConfig.incomingRingTimeout.inMilliseconds,
      extra: payload.toExtra(),
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Пропущенный звонок',
        callbackText: 'Перезвонить',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Идёт звонок…',
        callbackText: 'Завершить',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1B5E20',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        textAccept: 'Принять',
        textDecline: 'Отклонить',
        incomingCallNotificationChannelName: 'Входящие звонки Connect',
        missedCallNotificationChannelName: 'Пропущенные звонки Connect',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> handlePushData(Map<String, dynamic> data) async {
    if (!IncomingCallPayload.isChatCall(data)) return;
    if (!AuthService.instance.isAuthenticated) return;

    try {
      final payload = IncomingCallPayload.fromData(data);
      final callId = payload.callId;

      // Пуш о вызове пришёл позже отмены (FCM не гарантирует порядок)
      // или повторно (FCM + VoIP / FCM + Reverb).
      if (ChatCallService.instance.endedStatusFor(callId) != null) return;
      if (!_shownCallIds.add(callId)) return;

      if (_isBusyFor(callId)) {
        AppLogger.d(
          'Incoming $callId while busy — auto-decline',
          name: 'callkit',
        );
        _rememberMissed(callId, payload.callerName, payload.chatId);
        unawaited(
          ChatCallRepository.instance.declineCall(
            callId,
            reason: ChatCallEndReason.busy,
          ),
        );
        return;
      }

      await showIncomingCall(payload);
    } catch (e, st) {
      AppLogger.e(
        'Invalid chat_call payload',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Если пользователь ответил на CallKit до готовности Flutter (убитое приложение).
  Future<void> recoverPendingAcceptedCalls() async {
    if (!isSupported) return;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        if (!call.isAccepted) {
          // Ещё звонит: проверяем, не отменён ли звонок, пока мы были в фоне
          // и событие об отмене не дошло (iOS не будит убитое приложение FCM-ом).
          unawaited(_reconcileRinging(call.id));
          continue;
        }
        if (_acceptedLocally.contains(call.id)) continue;
        AppLogger.d(
          'Recovering accepted CallKit call ${call.id}',
          name: 'callkit',
        );
        await _onAccept(call);
      }
    } catch (e, st) {
      AppLogger.d(
        'recoverPendingAcceptedCalls failed',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _onCallEvent(CallEvent? event) async {
    if (event == null) return;

    AppLogger.d('CallKit event: ${event.eventName}', name: 'callkit');

    switch (event) {
      case CallEventActionCallIncoming(:final callKitParams):
        await _onIncomingShown(callKitParams);
      case CallEventActionCallAccept(:final callKitParams):
        await _onAccept(callKitParams);
      case CallEventActionCallDecline(:final callKitParams):
        await _onDecline(callKitParams);
      case CallEventActionCallEnded(:final callKitParams):
        // Закрытие CallKit после входа в Jitsi — разговор продолжается.
        if (_acceptedLocally.contains(callKitParams.id)) break;
        await _onDecline(callKitParams);
      case CallEventActionCallTimeout(:final id):
        await _declineByCallId(id, reason: ChatCallEndReason.timeout);
      case CallEventActionDidUpdateDevicePushTokenVoip():
        await refreshVoipRegistration(force: true);
      default:
        break;
    }
  }

  Future<void> handleBackgroundAccept(CallKitParams params) async {
    await _onAccept(params);
  }

  /// iOS: VoIP-пуш, пришедший во время разговора (AppDelegate не показал
  /// CallKit, см. `isInCall`). Обычно это «занято»; если разговор уже
  /// закончился — handlePushData покажет звонок как обычно.
  Future<void> _onVoipChannelCall(MethodCall call) async {
    if (call.method != 'incomingWhileInCall') return;
    final args = call.arguments;
    if (args is! Map) return;
    await handlePushData(
      args.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  void _onBusyChanged() {
    final busy = ChatCallService.instance.isBusy;
    if (Platform.isIOS && busy != _nativeInCall) {
      _nativeInCall = busy;
      unawaited(
        _voipPushChannel.invokeMethod<void>('setInCall', busy).catchError((
          Object e,
        ) {
          AppLogger.d('setInCall failed', name: 'callkit', error: e);
        }),
      );
    }
    if (!busy && _missedWhileBusy.isNotEmpty) _showMissedWhileBusy();
  }

  void _rememberMissed(String callId, String callerName, String? chatId) {
    final name = callerName.trim();
    _missedWhileBusy[callId] = (
      name: name.isEmpty || name == 'Connect' ? 'коллега' : name,
      chatId: chatId == null || chatId.isEmpty ? null : chatId,
    );
  }

  void _showMissedWhileBusy() {
    final context = AppNavigationService.navigatorKey.currentContext;
    final messenger = context == null
        ? null
        : ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final missed = _missedWhileBusy.values.toList();
    _missedWhileBusy.clear();

    final names = <String>{for (final m in missed) m.name}.join(', ');
    final chats = <String>{
      for (final m in missed)
        if (m.chatId != null) m.chatId!,
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: const Duration(seconds: 8),
          content: Text('Пока вы разговаривали, вам звонили: $names'),
          action: chats.length == 1
              ? SnackBarAction(
                  label: 'Открыть чат',
                  onPressed: () =>
                      AppNavigationService.openChatById(chats.first),
                )
              : null,
        ),
      );
  }

  bool _isBusyFor(String callId) {
    final calls = ChatCallService.instance;
    if (calls.liveDirectCallId == callId) return false;
    return calls.isBusy ||
        (_acceptInFlight && !_acceptedLocally.contains(callId));
  }

  /// CallKit показал входящий (и для FCM-пути, и для VoIP, показанного нативно).
  /// Сообщаем серверу «ringing» — звонящий видит «Вызов…», а сервер
  /// возвращает актуальный статус: устаревший VoIP-пуш сразу гасим.
  Future<void> _onIncomingShown(CallKitParams params) async {
    final callId = params.id;
    if (callId.isEmpty) return;
    _shownCallIds.add(callId);

    if (_isBusyFor(callId)) {
      AppLogger.d('CallKit $callId while busy — auto-decline', name: 'callkit');
      _rememberMissed(
        callId,
        params.nameCaller ?? '',
        params.extra?['chat_id']?.toString(),
      );
      await dismissRemotely(callId);
      unawaited(
        ChatCallRepository.instance.declineCall(
          callId,
          reason: ChatCallEndReason.busy,
        ),
      );
      return;
    }

    if (!AuthService.instance.isAuthenticated) {
      await AuthService.instance.init();
    }
    final status = await ChatCallRepository.instance.markRinging(callId);
    if (status != null &&
        status.isFinal &&
        !_acceptedLocally.contains(callId)) {
      AppLogger.d(
        'CallKit $callId is already ${status.wire} on server — dismissing',
        name: 'callkit',
      );
      ChatCallService.instance.notifyCallEnded(callId, status);
    }
  }

  Future<void> _reconcileRinging(String callId) async {
    if (callId.isEmpty || _acceptedLocally.contains(callId)) return;
    final status = await ChatCallRepository.instance.fetchStatus(callId);
    if (status == null || !status.isFinal) return;
    if (_acceptedLocally.contains(callId)) return;
    ChatCallService.instance.notifyCallEnded(callId, status);
  }

  Future<void> _onAccept(CallKitParams params) async {
    if (_acceptInFlight) return;
    _acceptInFlight = true;

    final extra = params.extra ?? const {};
    final callId = params.id;
    final room = extra['room']?.toString();
    final chatId = extra['chat_id']?.toString();
    final topic = extra['topic']?.toString();

    try {
      if (!AuthService.instance.isAuthenticated) {
        await AuthService.instance.init();
      }

      if (callId.isEmpty) return;
      if (_acceptedLocally.contains(callId)) return;

      // Звонок уже завершён (отменён, принят в вебе) — событие успело дойти.
      final knownEnd = ChatCallService.instance.endedStatusFor(callId);
      if (knownEnd != null) {
        await dismissRemotely(callId);
        return;
      }

      if (room == null || room.isEmpty) {
        AppLogger.e('Accept call: room missing', name: 'callkit');
        await _markDismissed(callId);
        await FlutterCallkitIncoming.endCall(callId);
        unawaited(
          ChatCallRepository.instance.declineCall(
            callId,
            reason: ChatCallEndReason.failed,
          ),
        );
        return;
      }

      _acceptedLocally.add(callId);
      // Ждём подтверждения: сервер закрепляет звонок за этим устройством и
      // гасит его на остальных. Если звонящий уже отменил или звонок приняли
      // в другом месте — в комнату не входим.
      final accept = await ChatCallRepository.instance.acceptCall(callId);
      if (!accept.ok) {
        AppLogger.d(
          'Accept call: rejected by server (${accept.status?.wire})',
          name: 'callkit',
        );
        _acceptedLocally.remove(callId);
        ChatCallService.instance.notifyCallEnded(
          callId,
          accept.status ?? ChatCallStatus.ended,
        );
        return;
      }

      await FlutterCallkitIncoming.setCallConnected(callId);

      final mediaOk = await CallPermissions.ensureMediaOnly();
      if (!mediaOk) {
        AppLogger.e('Accept call: media permissions denied', name: 'callkit');
        await FlutterCallkitIncoming.endCall(callId);
        unawaited(
          ChatCallRepository.instance.endCall(
            callId,
            reason: ChatCallEndReason.failed,
          ),
        );
        return;
      }

      if (chatId != null && chatId.isNotEmpty) {
        ChatCallService.instance.registerIncomingDirectCall(
          chatId: chatId,
          room: room,
          callId: callId,
          topic: topic,
        );
      }

      // Принятие звонка идёт мимо обычной навигации (нативный оверлей
      // CallKit/Jitsi), поэтому глубина корневого стека не меняется. Если до
      // звонка пользователь был глубоко в другом разделе, после разговора
      // кнопка «на главный экран» остаётся видна на любом экране. Сворачиваем
      // стек до вкладки «Чаты», как это уже делает openChatById для пуш-уведомлений.
      AppNavigationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
        arguments: {'initialIndex': HomeTabs.chats},
      );

      final session = await ConnectorRepository.instance.join(room);
      // Не закрываем CallKit до входа в Jitsi — иначе на lock screen
      // приложение может не подняться на передний план.
      final peer = ChatCallService.instance.peerFor(chatId);
      await openConnectorSession(
        session,
        callId: callId,
        endWhenLeave: true,
        title: peer.title ?? params.nameCaller,
        avatarUrl: peer.avatarUrl ?? params.avatar,
      );
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      AppLogger.e('Accept call: join failed', name: 'callkit', error: e);
      await FlutterCallkitIncoming.endCall(callId);
      if (callId.isNotEmpty) {
        unawaited(
          ChatCallService.instance.onLocalCallLeft(
            callId,
            reason: ChatCallEndReason.failed,
          ),
        );
      }
    } finally {
      _acceptInFlight = false;
    }
  }

  Future<void> _onDecline(CallKitParams params) async {
    await _declineByCallId(params.id);
  }

  Future<void> _declineByCallId(
    String callId, {
    ChatCallEndReason reason = ChatCallEndReason.declined,
  }) async {
    if (callId.isEmpty) return;

    // Закрыли мы сами по событию с сервера — это не отказ пользователя.
    if (await _consumeDismissed(callId)) return;
    if (_acceptedLocally.contains(callId)) return;
    if (ChatCallService.instance.endedStatusFor(callId) != null) return;

    ChatCallService.instance.notifyCallEnded(
      callId,
      reason == ChatCallEndReason.timeout
          ? ChatCallStatus.missed
          : ChatCallStatus.declined,
    );
    await ChatCallRepository.instance.declineCall(callId, reason: reason);
  }

  Future<void> _registerVoipTokenWhenReady() async {
    // ~45 с: PushKit часто приходит после cold start / после логина.
    for (var i = 0; i < 20; i++) {
      try {
        final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (token != null && token.isNotEmpty) {
          await _registerVoipToken(token);
          return;
        }
        AppLogger.d(
          'VoIP token not ready yet (attempt ${i + 1})',
          name: 'callkit',
        );
      } catch (e, st) {
        AppLogger.d(
          'getDevicePushTokenVoIP failed (attempt ${i + 1})',
          name: 'callkit',
          error: e,
          stackTrace: st,
        );
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
    AppLogger.e(
      'VoIP token was never available after retries',
      name: 'callkit',
    );
  }

  Future<void> _registerVoipToken(String token) async {
    if (token == _lastVoipToken) {
      AppLogger.d('VoIP token unchanged, skip POST', name: 'callkit');
      return;
    }

    if (!AuthService.instance.isAuthenticated) {
      _pendingVoipToken = token;
      AppLogger.d(
        'VoIP token cached until login (${token.length} chars)',
        name: 'callkit',
      );
      return;
    }

    try {
      await DeviceTokenRepository.instance.registerVoipToken(token: token);
      _lastVoipToken = token;
      _pendingVoipToken = null;
      AppLogger.d(
        'VoIP token registered on backend (${token.length} chars)',
        name: 'callkit',
      );
    } catch (e, st) {
      AppLogger.e(
        'Failed to register VoIP token',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
  }
}
