import '../models/connector/connector_session.dart';
import '../services/jitsi_meeting_service.dart';

/// Открывает конференцию через Jitsi Meet SDK (Android/iOS).
/// На прочих платформах — браузер с JWT.
Future<void> openConnectorSession(ConnectorSession session) {
  return JitsiMeetingService.instance.joinSession(session);
}
