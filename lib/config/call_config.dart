/// Тайминги 1:1 звонков. Источник правды по таймауту дозвона — бэкенд
/// (`ring_timeout`, по умолчанию 30 с, см. docs/BACKEND_CALLS.md): он сам
/// переводит звонок в `missed` и рассылает событие всем устройствам и вебу.
/// Клиентские таймеры чуть длиннее и нужны только как страховка, если
/// событие от сервера потерялось.
class CallConfig {
  CallConfig._();

  /// Звонящий: сколько ждём ответа на экране «Звоним…».
  static const outgoingRingTimeout = Duration(seconds: 32);

  /// Принимающий: сколько показывается CallKit/ConnectionService.
  /// Синхронизировать с `info["duration"]` в ios/Runner/AppDelegate.swift.
  static const incomingRingTimeout = Duration(seconds: 35);

  /// Опрос статуса на экране «Звоним…» на случай потерянного push/сокета.
  static const outgoingStatusPollInterval = Duration(seconds: 3);

  /// Heartbeat во время разговора: сервер узнаёт, что клиент жив,
  /// клиент — что звонок не завершили с другой стороны (веб, другое устройство).
  static const heartbeatInterval = Duration(seconds: 15);

  /// После ответа собеседник должен войти в комнату за это время,
  /// иначе звонок завершается с причиной `failed`.
  static const peerJoinTimeout = Duration(seconds: 40);

  /// Собеседник пропал из комнаты без сигнала о завершении: ждём столько,
  /// прежде чем завершить 1:1 (реконнект при смене сети). Совпадает с
  /// задержкой `CheckRoomOccupantsJob` на бэкенде (docs/BACKEND_CALLS.md, 5.2).
  static const peerRejoinGrace = Duration(seconds: 15);
}
