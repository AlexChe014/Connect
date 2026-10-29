import '../models/chat/chat_call_status.dart';
import '../models/connector/connector_session.dart';
import '../services/chat_call_service.dart';
import '../services/jitsi_meeting_service.dart';

/// Открывает конференцию через Jitsi Meet SDK (Android/iOS).
/// На прочих платформах — браузер с JWT.
///
/// [title]/[avatarUrl] — собеседник 1:1 для экрана звонка.
/// [peerAnswered] — см. [JitsiMeetingService.joinSession].
Future<void> openConnectorSession(
  ConnectorSession session, {
  String? callId,
  bool endWhenLeave = false,
  bool peerAnswered = false,
  String? title,
  String? avatarUrl,
}) {
  return JitsiMeetingService.instance.joinSession(
    session,
    callId: callId,
    endWhenLeave: endWhenLeave,
    peerAnswered: peerAnswered,
    title: title,
    avatarUrl: avatarUrl,
    onLeave: endWhenLeave
        ? (id, {failed = false}) => ChatCallService.instance.onLocalCallLeft(
            id,
            reason: failed
                ? ChatCallEndReason.failed
                : ChatCallEndReason.hangup,
          )
        : null,
  );
}
