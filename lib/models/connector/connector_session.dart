/// Ответ API Коннектора: данные для входа в Jitsi / ссылки на встречу.
class ConnectorSession {
  const ConnectorSession({
    required this.room,
    required this.publicUrl,
    required this.jitsiServerUrl,
    this.jwt,
    this.topic,
    this.bookingId,
    this.id,
    this.moderator = false,
    this.displayName,
    this.canJoin,
  });

  /// Имя комнаты Jitsi (UUID), напр. `ffdc584e-b2f5-4e5d-a0ee-ee6eba4a24f1`.
  final String room;

  /// Публичная ссылка портала: `https://connect.xondev.ru/connector/{room}`.
  final String publicUrl;

  /// URL Jitsi-сервера: `https://connecthub.xondev.ru`.
  final String jitsiServerUrl;

  /// JWT для SDK / iframe (выдаёт только бэкенд).
  final String? jwt;

  final String? topic;
  final int? bookingId;
  final int? id;
  final bool moderator;
  final String? displayName;

  /// Из `GET /connector/{room}` — можно ли войти.
  final bool? canJoin;

  factory ConnectorSession.fromJson(Map<String, dynamic> json) {
    return ConnectorSession(
      room: (json['room'] as String?)?.trim() ?? '',
      publicUrl: (json['public_url'] as String?)?.trim() ??
          (json['url'] as String?)?.trim() ??
          '',
      jitsiServerUrl: (json['jitsi_server_url'] as String?)?.trim() ?? '',
      jwt: (json['jwt'] as String?)?.trim(),
      topic: (json['topic'] as String?)?.trim(),
      bookingId: _parseInt(json['booking_id']),
      id: _parseInt(json['id']),
      moderator: json['moderator'] == true || json['moderator'] == 1,
      displayName: (json['display_name'] as String?)?.trim(),
      canJoin: json['can_join'] is bool
          ? json['can_join'] as bool
          : (json['can_join'] == 1
                ? true
                : (json['can_join'] == 0 ? false : null)),
    );
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
