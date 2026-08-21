import 'package:connect/config/jitsi_config.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Аналог Next `generateJWT` для ConnectHub / Jitsi (HS256).
String generateJitsiJwt({
  required String name,
  required String surname,
  required String roomName,
  bool isInitiator = false,
}) {
  final secret = JitsiConfig.secret;
  if (secret.isEmpty) {
    throw StateError(
      'JitsiConfig.secret пуст — задайте JITSI_SECRET в конфигурации',
    );
  }
  final appId = JitsiConfig.appId;
  if (appId.isEmpty) {
    throw StateError(
      'JitsiConfig.appId пуст — задайте JWT_APP_ID в конфигурации',
    );
  }

  final displayName = '${surname.trim()} ${name.trim()}'.trim();
  final exp = DateTime.now()
      .toUtc()
      .add(Duration(minutes: JitsiConfig.tokenLifetimeMinutes))
      .millisecondsSinceEpoch ~/
      1000;

  final jwt = JWT(
    {
      'context': {
        'user': {
          'name': displayName,
        },
        'features': {
          'livestreaming': true,
          'recording': true,
        },
      },
      'aud': appId,
      'iss': appId,
      'sub': JitsiConfig.serverAddress,
      'room': roomName,
      'exp': exp,
      'moderator': isInitiator,
    },
  );

  return jwt.sign(SecretKey(secret), algorithm: JWTAlgorithm.HS256);
}
