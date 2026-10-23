/// Состояние текущей видеоконференции для собственного экрана звонка
/// (см. JitsiMeetingService и CallOverlayHost).
library;

import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

enum CallPhase {
  /// Вход в комнату Jitsi.
  connecting,

  /// В комнате, собеседника ещё нет (1:1) — «Ожидание собеседника…».
  waiting,

  /// Идёт разговор.
  active,

  /// 1:1: собеседник пропал из комнаты, ждём возвращения (смена сети).
  reconnecting,

  /// Выходим: «Звонок завершён», экран вот-вот закроется.
  ending,
}

/// Куда сейчас идёт звук (названия совпадают с нативной частью плагина).
enum CallAudioRoute {
  speaker,
  earpiece,
  headphones,
  bluetooth,
  unknown;

  static CallAudioRoute parse(String value) => CallAudioRoute.values.firstWhere(
    (r) => r.name == value,
    orElse: () => CallAudioRoute.unknown,
  );
}

class CallParticipant {
  CallParticipant({required this.id, required this.name});

  final String id;
  String name;

  /// Камера/микрофон собеседника. `null` — неизвестно: о своём состоянии
  /// сообщают только наши приложения (см. JitsiMeetingService._stateMessage),
  /// участник из веб-портала его не присылает.
  bool? videoOn;
  bool? audioOn;
}

class CallConference {
  CallConference({
    required this.options,
    required this.room,
    required this.title,
    required this.isDirect,
    this.avatarUrl,
  });

  final JitsiMeetConferenceOptions options;
  final String room;

  /// Имя собеседника (1:1) или тема встречи.
  String title;
  final String? avatarUrl;

  /// Личный звонок из чата: выход любой стороны завершает разговор.
  final bool isDirect;

  CallPhase phase = CallPhase.connecting;

  /// Начало разговора для таймера: вход собеседника (1:1) или вход в
  /// комнату (встреча).
  DateTime? startedAt;

  bool audioMuted = true;
  bool videoMuted = true;
  bool screenSharing = false;
  bool chatOpen = false;
  int unreadChat = 0;
  bool minimized = false;

  CallAudioRoute audioRoute = CallAudioRoute.unknown;
  List<CallAudioRoute> availableRoutes = const [];

  final Map<String, CallParticipant> participants = {};

  CallParticipant? get peer =>
      participants.isEmpty ? null : participants.values.first;

  /// 1:1 без видео с обеих сторон — вместо пустого кадра Jitsi показываем
  /// свой экран с аватаром. Пока собеседник не вошёл — тоже он.
  bool get showsAudioStage {
    if (!isDirect || !videoMuted || screenSharing) return false;
    final peer = this.peer;
    if (peer == null) return true;
    return peer.videoOn == false;
  }

  /// Есть куда переключать кроме «динамик ↔ телефон» — нужен выбор
  /// устройства, а не простой переключатель.
  bool get hasExternalAudio =>
      availableRoutes.contains(CallAudioRoute.bluetooth) ||
      availableRoutes.contains(CallAudioRoute.headphones);
}
