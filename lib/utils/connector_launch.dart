import '../models/connector/connector_session.dart';
import '../services/chat_call_service.dart';
import '../services/jitsi_meeting_service.dart';

/// Открывает конференцию через Jitsi Meet SDK (Android/iOS).
/// На прочих платформах — браузер с JWT.
Future<void> openConnectorSession(
  ConnectorSession session, {
  String? callId,
  bool endWhenLeave = false,
}) {
  return JitsiMeetingService.instance.joinSession(
    session,
    callId: callId,
    endWhenLeave: endWhenLeave,
    onLeave: endWhenLeave
        ? (id) => ChatCallService.instance.onLocalCallLeft(id)
        : null,
  );
}
