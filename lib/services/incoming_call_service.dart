import 'dart:async';
import 'dart:io';

import 'package:connect/models/incoming_call_payload.dart';
import 'package:connect/repositories/chat_call_repository.dart';
import 'package:connect/repositories/connector_repository.dart';
import 'package:connect/repositories/device_token_repository.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/call_permissions.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/utils/connector_launch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

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

  StreamSubscription<CallEvent?>? _eventSub;
  bool _initialized = false;
  String? _lastVoipToken;
  String? _pendingVoipToken;
  final Set<String> _acceptedLocally = {};
  bool _acceptInFlight = false;

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  Future<void> init() async {
    if (_initialized || !isSupported) return;
    _initialized = true;

    _eventSub = FlutterCallkitIncoming.onEvent.listen(_onCallEvent);

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
    _initialized = false;
  }

  /// После логина / FCM: сбросить кэш и снова отправить VoIP на бэкенд.
  Future<void> refreshVoipRegistration({bool force = false}) async {
    if (!isSupported || !Platform.isIOS) return;
    if (force) _lastVoipToken = null;

    if (_pendingVoipToken != null &&
        _pendingVoipToken!.isNotEmpty &&
        AuthService.instance.isAuthenticated) {
      await _registerVoipToken(_pendingVoipToken!);
    }

    await _registerVoipTokenWhenReady();
  }

  void clearVoipCache() {
    _lastVoipToken = null;
    _pendingVoipToken = null;
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
      duration: 45000,
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
        if (!call.isAccepted) continue;
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
      case CallEventActionCallAccept(:final callKitParams):
        await _onAccept(callKitParams);
      case CallEventActionCallDecline(:final callKitParams):
        await _onDecline(callKitParams);
      case CallEventActionCallEnded(:final callKitParams):
        if (_acceptedLocally.remove(callKitParams.id)) break;
        await _onDecline(callKitParams);
      case CallEventActionCallTimeout(:final id):
        await _declineByCallId(id);
      case CallEventActionDidUpdateDevicePushTokenVoip():
        await refreshVoipRegistration(force: true);
      default:
        break;
    }
  }

  Future<void> handleBackgroundAccept(CallKitParams params) async {
    await _onAccept(params);
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

      if (callId.isNotEmpty) {
        _acceptedLocally.add(callId);
        unawaited(ChatCallRepository.instance.acceptCall(callId));
      }

      await FlutterCallkitIncoming.setCallConnected(callId);

      if (room == null || room.isEmpty) {
        AppLogger.e('Accept call: room missing', name: 'callkit');
        await FlutterCallkitIncoming.endCall(callId);
        return;
      }

      final mediaOk = await CallPermissions.ensureMediaOnly();
      if (!mediaOk) {
        AppLogger.e('Accept call: media permissions denied', name: 'callkit');
        await FlutterCallkitIncoming.endCall(callId);
        if (callId.isNotEmpty) {
          unawaited(DeviceTokenRepository.instance.declineCall(callId: callId));
        }
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

      final session = await ConnectorRepository.instance.join(room);
      // Не закрываем CallKit до входа в Jitsi — иначе на lock screen
      // приложение может не подняться на передний план.
      await openConnectorSession(
        session,
        callId: callId,
        endWhenLeave: true,
      );
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      AppLogger.e('Accept call: join failed', name: 'callkit', error: e);
      await FlutterCallkitIncoming.endCall(callId);
      if (callId.isNotEmpty) {
        unawaited(ChatCallRepository.instance.endCall(callId));
      }
    } finally {
      _acceptInFlight = false;
    }
  }

  Future<void> _onDecline(CallKitParams params) async {
    await _declineByCallId(params.id);
  }

  Future<void> _declineByCallId(String callId) async {
    if (callId.isEmpty) return;

    ChatCallService.instance.notifyCallEnded(callId, 'declined');

    try {
      await DeviceTokenRepository.instance.declineCall(callId: callId);
    } catch (e, st) {
      AppLogger.d(
        'Decline call API failed (backend may be unavailable)',
        name: 'callkit',
        error: e,
        stackTrace: st,
      );
    }
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
