import 'package:flutter/foundation.dart';

/// Payload входящего звонка из push (FCM data / APNs VoIP).
@immutable
class IncomingCallPayload {
  const IncomingCallPayload({
    required this.callId,
    required this.chatId,
    required this.room,
    required this.callerName,
    this.callerAvatar,
    this.topic,
    this.isVideo = true,
  });

  /// UUID звонка — совпадает с id в CallKit.
  final String callId;

  final String chatId;
  final String room;
  final String callerName;
  final String? callerAvatar;
  final String? topic;
  final bool isVideo;

  factory IncomingCallPayload.fromData(Map<String, dynamic> data) {
    final callId = _str(data['call_id']) ?? _str(data['callId']);
    final chatId = _str(data['chat_id']);
    final room = _str(data['room']);
    final callerName =
        _str(data['caller_name']) ?? _str(data['callerName']) ?? 'Connect';

    if (callId == null || callId.isEmpty) {
      throw FormatException('chat_call: missing call_id');
    }
    if (chatId == null || chatId.isEmpty) {
      throw FormatException('chat_call: missing chat_id');
    }
    if (room == null || room.isEmpty) {
      throw FormatException('chat_call: missing room');
    }

    final isVideoRaw = data['is_video'] ?? data['isVideo'] ?? '1';
    final isVideo = isVideoRaw == true ||
        isVideoRaw == 1 ||
        isVideoRaw == '1' ||
        isVideoRaw == 'true';

    return IncomingCallPayload(
      callId: callId,
      chatId: chatId,
      room: room,
      callerName: callerName,
      callerAvatar: _str(data['caller_avatar']) ?? _str(data['callerAvatar']),
      topic: _str(data['topic']),
      isVideo: isVideo,
    );
  }

  Map<String, dynamic> toExtra() {
    return {
      'call_id': callId,
      'chat_id': chatId,
      'room': room,
      'caller_name': callerName,
      if (callerAvatar != null) 'caller_avatar': callerAvatar,
      if (topic != null) 'topic': topic,
      'is_video': isVideo ? '1' : '0',
    };
  }

  static String? _str(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool isChatCall(Map<String, dynamic> data) {
    return _str(data['type']) == 'chat_call';
  }
}
