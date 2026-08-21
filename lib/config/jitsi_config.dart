/// Параметры JWT для ConnectHub / Jitsi.
///
/// Значения заполняются позже (из окружения / remote config).
/// Секрет нельзя хранить в прод-сборке клиента — предпочтительно
/// выдавать JWT с бэкенда.
class JitsiConfig {
  JitsiConfig._();

  /// `JWT_APP_ID` — aud / iss токена.
  static const String appId = '';

  /// `JITSI_SERVER_ADDRESS` — sub (обычно URL сервера, напр. https://connecthub.xondev.ru).
  static const String serverAddress = 'https://connecthub.xondev.ru';

  /// `JITSI_SECRET` — ключ подписи HS256.
  static const String secret = '';

  /// `JWT_TOKEN_LIFETIME` — время жизни токена в минутах (по умолчанию 8 часов).
  static const int tokenLifetimeMinutes = 480;
}
