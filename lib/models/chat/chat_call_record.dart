import 'package:connect/models/chat/chat_call_status.dart';
import 'package:flutter/foundation.dart';

/// Запись о 1:1 звонке в ленте чата — сообщение `type: "CALL"`, которое
/// бэкенд создаёт при начале звонка и обновляет при его завершении
/// (см. docs/BACKEND_CALLS.md). Автор сообщения (`sender_id`) — звонящий.
@immutable
class ChatCallRecord {
  const ChatCallRecord({
    required this.callId,
    this.status,
    this.durationSeconds,
  });

  /// Тип сообщения-звонка в чат-API.
  static const String messageType = 'CALL';

  final String callId;
  final ChatCallStatus? status;

  /// Длительность разговора; есть только у состоявшихся звонков.
  final int? durationSeconds;

  /// Разбирает объект `call` из сообщения (`{id|call_id, status, duration}`).
  static ChatCallRecord? tryParse(Object? raw, {Object? fallbackCallId}) {
    final map = raw is Map ? raw : const <String, dynamic>{};
    final callId = _str(map['call_id']) ?? _str(map['id']) ?? _str(fallbackCallId);
    if (callId == null) return null;
    return ChatCallRecord(
      callId: callId,
      status: ChatCallStatus.tryParse(map['status']),
      durationSeconds: _int(map['duration'] ?? map['duration_seconds']),
    );
  }

  bool get _wasAnswered =>
      status == ChatCallStatus.accepted ||
      (status == ChatCallStatus.ended && (durationSeconds ?? 0) > 0);

  /// Звонок, который не состоялся (для подсветки красным).
  bool get isUnsuccessful => switch (status) {
    ChatCallStatus.missed ||
    ChatCallStatus.declined ||
    ChatCallStatus.cancelled ||
    ChatCallStatus.busy ||
    ChatCallStatus.failed => true,
    ChatCallStatus.ended => !_wasAnswered,
    _ => false,
  };

  String title({required bool isOutgoing}) {
    if (!isUnsuccessful) {
      return isOutgoing ? 'Исходящий звонок' : 'Входящий звонок';
    }
    return switch (status) {
      ChatCallStatus.declined => 'Отклонённый звонок',
      ChatCallStatus.busy when isOutgoing => 'Абонент занят',
      ChatCallStatus.cancelled when isOutgoing => 'Отменённый звонок',
      ChatCallStatus.failed => 'Звонок не удался',
      _ when isOutgoing => 'Нет ответа',
      _ => 'Пропущенный звонок',
    };
  }

  /// Вторая строка пузыря: длительность или текущее состояние.
  String? get subtitle {
    final seconds = durationSeconds;
    if (seconds != null && seconds > 0) return formatDuration(seconds);
    return switch (status) {
      ChatCallStatus.calling || ChatCallStatus.ringing => 'Идёт вызов…',
      ChatCallStatus.accepted => 'Идёт разговор',
      _ => null,
    };
  }

  /// Текст для превью в списке чатов и цитат.
  String snippet({required bool isOutgoing}) {
    final duration = durationSeconds;
    final base = '📞 ${title(isOutgoing: isOutgoing)}';
    return duration != null && duration > 0
        ? '$base · ${formatDuration(duration)}'
        : base;
  }

  static String formatDuration(int totalSeconds) {
    final d = Duration(seconds: totalSeconds < 0 ? 0 : totalSeconds);
    final hours = d.inHours;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  static String? _str(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString().trim() ?? '');
  }
}
