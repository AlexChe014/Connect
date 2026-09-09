/// Разбор Laravel Echo / Reverb payload для чатов — без зависимости от сокета.
enum ChatRealtimeKind { created, updated, deleted, read, members, unknown }

class ChatRealtimePayload {
  ChatRealtimePayload._();

  static ChatRealtimeKind classifyEvent(String eventName) {
    final n = eventName
        .toLowerCase()
        .replaceAll('\\', '.')
        .replaceAll('_', '.')
        .replaceAll('-', '.');
    if (n.contains('delet')) return ChatRealtimeKind.deleted;
    if (n.contains('read') || n.contains('seen')) return ChatRealtimeKind.read;
    if (n.contains('member') || n.contains('participant')) {
      return ChatRealtimeKind.members;
    }
    if (n.contains('edit') || n.contains('updat')) {
      return ChatRealtimeKind.updated;
    }
    if (n.contains('message') ||
        n.contains('sent') ||
        n.contains('created') ||
        n.contains('new')) {
      return ChatRealtimeKind.created;
    }
    return ChatRealtimeKind.unknown;
  }

  static bool isProtocolEvent(String eventName) {
    return eventName.startsWith('pusher:') || eventName.startsWith('client-');
  }

  static Map<String, dynamic>? asJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int? parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static Map<String, dynamic>? extractMessage(Object? data) {
    final map = asJsonMap(data);
    if (map == null) return null;

    for (final key in const ['message', 'chat_message', 'data']) {
      final nested = asJsonMap(map[key]);
      if (nested != null && looksLikeMessage(nested)) return nested;
    }
    if (looksLikeMessage(map)) return map;
    return null;
  }

  static bool looksLikeMessage(Map<String, dynamic> map) {
    if (parseInt(map['sender_id']) != null) return true;
    if (parseInt(map['id']) == null) return false;
    return map.containsKey('message') ||
        map.containsKey('chat_id') ||
        map.containsKey('type') ||
        map.containsKey('text');
  }

  static String? extractChatId(Object? data, {String? channelName}) {
    final map = asJsonMap(data);
    if (map != null) {
      final direct = parseInt(map['chat_id'] ?? map['chatId']);
      if (direct != null) return direct.toString();
      final nestedChat = asJsonMap(map['chat']);
      final fromChat = parseInt(nestedChat?['id']);
      if (fromChat != null) return fromChat.toString();
      final message = extractMessage(map);
      final fromMessage = parseInt(message?['chat_id'] ?? message?['chatId']);
      if (fromMessage != null) return fromMessage.toString();
    }

    if (channelName == null || channelName.isEmpty) return null;
    final match = RegExp(
      r'(?:private-|presence-)?(?:chats?|App\.Models\.Chat)\.(\d+)',
      caseSensitive: false,
    ).firstMatch(channelName);
    return match?.group(1);
  }

  static String? extractMessageId(Object? data) {
    final map = asJsonMap(data);
    if (map == null) return null;
    final direct = parseInt(map['message_id'] ?? map['id']);
    if (map.containsKey('message_id') && direct != null) {
      return direct.toString();
    }
    final message = extractMessage(map);
    final fromMessage = parseInt(message?['id']);
    if (fromMessage != null) return fromMessage.toString();
    if (direct != null && looksLikeMessage(map)) return direct.toString();
    return null;
  }

  static int? extractUserId(Object? data) {
    final map = asJsonMap(data);
    if (map == null) return null;
    return parseInt(
      map['user_id'] ??
          map['reader_id'] ??
          map['readerId'] ??
          asJsonMap(map['user'])?['id'],
    );
  }
}
