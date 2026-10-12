import 'package:flutter/foundation.dart';

/// Состояние 1:1 звонка — общий словарь с бэкендом и веб-клиентом
/// (см. docs/BACKEND_CALLS.md).
enum ChatCallStatus {
  /// Звонок создан, пуш собеседнику отправлен.
  calling('calling'),

  /// Хотя бы одно устройство собеседника показало входящий звонок.
  ringing('ringing'),

  /// Собеседник ответил (на любом своём устройстве или в вебе).
  accepted('accepted'),

  /// Собеседник отклонил.
  declined('declined'),

  /// Звонящий отменил до ответа.
  cancelled('cancelled'),

  /// Никто не ответил за `ring_timeout`.
  missed('missed'),

  /// Собеседник уже в другом звонке.
  busy('busy'),

  /// Разговор завершён одной из сторон.
  ended('ended'),

  /// Технический сбой: не удалось войти в комнату, собеседник пропал и т.п.
  failed('failed'),

  /// Служебный статус для «других» устройств принимающего: звонок принят
  /// на другом устройстве/в вебе — здесь нужно молча убрать CallKit.
  answeredElsewhere('answered_elsewhere'),

  /// Служебный статус для «других» устройств принимающего: отклонён
  /// на другом устройстве/в вебе.
  declinedElsewhere('declined_elsewhere');

  const ChatCallStatus(this.wire);

  final String wire;

  bool get isFinal => switch (this) {
    calling || ringing || accepted => false,
    _ => true,
  };

  static ChatCallStatus? tryParse(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim().toLowerCase().replaceAll('-', '_');
    if (s.isEmpty) return null;
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return switch (s) {
      'canceled' => cancelled,
      'rejected' || 'decline' => declined,
      'timeout' || 'no_answer' || 'unanswered' => missed,
      'answered' || 'accept' || 'active' || 'connected' => accepted,
      'finished' || 'completed' || 'hangup' => ended,
      'error' => failed,
      'answered_on_other_device' => answeredElsewhere,
      _ => null,
    };
  }
}

/// Причина, которую клиент передаёт в `end` / `decline`.
enum ChatCallEndReason {
  /// Звонящий нажал «Отменить» до ответа.
  cancelled('cancelled'),

  /// Истёк локальный таймер дозвона.
  timeout('timeout'),

  /// Обычное завершение разговора.
  hangup('hangup'),

  /// Принимающий нажал «Отклонить».
  declined('declined'),

  /// Принимающий уже разговаривает (автоматический отказ).
  busy('busy'),

  /// Нет прав на камеру/микрофон, не удалось войти в комнату и т.п.
  failed('failed');

  const ChatCallEndReason(this.wire);

  final String wire;
}

/// Событие о статусе звонка из любого канала: FCM/APNs, VoIP, Reverb,
/// ответ `GET /chat/call/{id}` или heartbeat.
@immutable
class ChatCallSignal {
  const ChatCallSignal({
    required this.callId,
    required this.status,
    this.chatId,
    this.byUserId,
    this.deviceId,
  });

  final String callId;
  final ChatCallStatus status;
  final String? chatId;

  /// Кто изменил статус (`user_id` инициатора действия).
  final int? byUserId;

  /// Устройство, с которого пришло действие (`device_id`), если сервер его знает.
  final String? deviceId;

  /// Типы push/Reverb-событий о статусе звонка.
  static const pushTypes = {
    'chat_call_ended',
    'chat_call_accepted',
    'chat_call_ringing',
    'chat_call_status',
  };

  /// Разбирает data push-уведомления (`type: chat_call_*`) или payload
  /// Reverb-события `call.*`. Входящий вызов (`type: chat_call`) сюда не
  /// относится — это [IncomingCallPayload].
  static ChatCallSignal? tryParse(
    Map<String, dynamic> data, {
    String? eventName,
  }) {
    final payload = _unwrap(data);
    final callId = _str(payload['call_id']) ?? _str(payload['callId']);
    if (callId == null) return null;

    final type = _str(payload['type'])?.toLowerCase();
    final event = eventName?.toLowerCase().replaceAll('\\', '.');

    var status = ChatCallStatus.tryParse(payload['status']);
    status ??= switch (type) {
      'chat_call_accepted' => ChatCallStatus.accepted,
      'chat_call_ringing' => ChatCallStatus.ringing,
      'chat_call_ended' => ChatCallStatus.ended,
      _ => null,
    };
    if (status == null && event != null) {
      if (event.contains('accept')) {
        status = ChatCallStatus.accepted;
      } else if (event.contains('ringing')) {
        status = ChatCallStatus.ringing;
      } else if (event.contains('declin')) {
        status = ChatCallStatus.declined;
      } else if (event.contains('cancel')) {
        status = ChatCallStatus.cancelled;
      } else if (event.contains('end')) {
        status = ChatCallStatus.ended;
      }
    }
    if (status == null) return null;

    return ChatCallSignal(
      callId: callId,
      status: status,
      chatId: _str(payload['chat_id']),
      byUserId: int.tryParse(
        _str(payload['by_user_id']) ?? _str(payload['user_id']) ?? '',
      ),
      deviceId: _str(payload['device_id']),
    );
  }

  /// Является ли push/Reverb-событие сигналом о статусе звонка.
  static bool isCallSignal(Map<String, dynamic> data, {String? eventName}) {
    final type = _str(data['type']);
    if (type != null && pushTypes.contains(type)) return true;
    if (eventName == null) return false;
    // `call.status`, `chat.call.ended`, `App\Events\Chat\CallAccepted`…
    return eventName.toLowerCase().contains('call') &&
        _unwrap(data)['call_id'] != null;
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> data) {
    for (final key in const ['call', 'data']) {
      final nested = data[key];
      if (nested is Map && nested['call_id'] != null) {
        return {...data, ...Map<String, dynamic>.from(nested)};
      }
    }
    return data;
  }

  static String? _str(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  String toString() =>
      'ChatCallSignal($callId, ${status.wire}, chat=$chatId, by=$byUserId)';
}
