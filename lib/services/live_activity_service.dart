import 'dart:async';
import 'dart:io';

import 'package:connect/models/call_conference.dart';
import 'package:connect/services/jitsi_meeting_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/services.dart';

/// Live Activity идущего звонка (iOS): Dynamic Island и экран блокировки
/// с таймером и кнопками «Микрофон» / «Завершить».
///
/// Следит за [JitsiMeetingService.conference] и шлёт в нативную часть
/// (ios/Runner/WidgetBridge.swift) только реальные изменения.
class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  static const _channel = MethodChannel('connect/live_activity');

  bool _started = false;
  String? _room;
  Map<String, Object?>? _lastState;

  void init() {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler(_onNativeCall);
    JitsiMeetingService.instance.addListener(_sync);
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'action') return;
    final meeting = JitsiMeetingService.instance;
    switch (call.arguments) {
      case 'end':
        await meeting.hangUp();
      case 'toggleMute':
        await meeting.toggleMicrophone();
    }
  }

  void _sync() {
    final conference = JitsiMeetingService.instance.conference;
    if (conference == null || conference.phase == CallPhase.ending) {
      if (_started) _invoke('end');
      _started = false;
      _room = null;
      _lastState = null;
      return;
    }

    final state = <String, Object?>{
      'phase': conference.phase.name,
      'startedAt': conference.startedAt?.millisecondsSinceEpoch,
      'muted': conference.audioMuted,
    };

    if (!_started || _room != conference.room) {
      _started = true;
      _room = conference.room;
      _lastState = state;
      _invoke('start', {
        ...state,
        'title': conference.title,
        'isVideo': !conference.videoMuted,
      });
      return;
    }

    if (!_sameState(state)) {
      _lastState = state;
      _invoke('update', state);
    }
  }

  bool _sameState(Map<String, Object?> state) {
    final last = _lastState;
    if (last == null) return false;
    for (final key in state.keys) {
      if (last[key] != state[key]) return false;
    }
    return true;
  }

  void _invoke(String method, [Map<String, Object?>? args]) {
    unawaited(
      _channel.invokeMethod<void>(method, args).catchError((Object e) {
        AppLogger.e('Live Activity $method failed', name: 'call', error: e);
      }),
    );
  }
}
