import 'dart:async';
import 'dart:io';

import 'package:connect/models/incoming_call_payload.dart';
import 'package:connect/repositories/connector_repository.dart';
import 'package:connect/repositories/device_token_repository.dart';
import 'package:connect/services/auth_service.dart';
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
    }

    if (Platform.isAndroid) {
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
      unawaited(_registerVoipTokenWhenReady());
    }
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    _initialized = false;
  }

  Future<void> refreshVoipRegistration() async {
    if (!isSupported || !Platform.isIOS) return;
    await _registerVoipTokenWhenReady();
  }

  /// Показать системный экран входящего звонка.
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
        isShowCallback: true,
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
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Обработка FCM data / VoIP push (foreground и Android background).
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

  Future<void> _onCallEvent(CallEvent? event) async {
    if (event == null) return;

    AppLogger.d('CallKit event: ${event.eventName}', name: 'callkit');

    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        await _onAccept(callKitParams);
      case CallEventActionCallDecline(:final callKitParams):
        await _onDecline(callKitParams);
      case CallEventActionCallEnded(:final callKitParams):
        await _onDecline(callKitParams);
      case CallEventActionCallTimeout(:final id):
        await _declineByCallId(id);
      case CallEventActionDidUpdateDevicePushTokenVoip():
        await _registerVoipTokenWhenReady();
      default:
        break;
    }
  }

  Future<void> handleBackgroundAccept(CallKitParams params) async {
    await _onAccept(params);
  }

  Future<void> _onAccept(CallKitParams params) async {
    final extra = params.extra ?? const {};
    final callId = params.id;
    final room = extra['room']?.toString();

    await FlutterCallkitIncoming.setCallConnected(callId);

    if (room == null || room.isEmpty) {
      AppLogger.e('Accept call: room missing', name: 'callkit');
      await FlutterCallkitIncoming.endCall(callId);
      return;
    }

    try {
      final session = await ConnectorRepository.instance.join(room);
      await FlutterCallkitIncoming.endCall(callId);
      await openConnectorSession(session);
    } catch (e) {
      AppLogger.e('Accept call: join failed', name: 'callkit', error: e);
      await FlutterCallkitIncoming.endCall(callId);
    }
  }

  Future<void> _onDecline(CallKitParams params) async {
    await _declineByCallId(params.id);
  }

  Future<void> _declineByCallId(String callId) async {
    if (callId.isEmpty) return;

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
    for (var i = 0; i < 10; i++) {
      try {
        final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (token != null && token.isNotEmpty) {
          await _registerVoipToken(token);
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
  }

  Future<void> _registerVoipToken(String token) async {
    if (token == _lastVoipToken) return;
    if (!AuthService.instance.isAuthenticated) return;

    try {
      await DeviceTokenRepository.instance.registerVoipToken(token: token);
      _lastVoipToken = token;
      AppLogger.d('VoIP token registered', name: 'callkit');
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
