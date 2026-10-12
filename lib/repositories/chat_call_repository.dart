import 'package:connect/config/routes/chat_call_routes.dart';
import 'package:connect/models/chat/chat_call_status.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/services/device_identity.dart';
import 'package:connect/utils/app_logger.dart';

/// Результат `POST /chat/{chatId}/call/ring`.
class RingResult {
  const RingResult({this.callId, this.status, this.message});

  /// `null` — бэкенд не создал звонок (ошибка сети/эндпоинта или отказ).
  final String? callId;

  /// `busy` — собеседник уже разговаривает; `failed` — дозвон невозможен.
  final ChatCallStatus? status;
  final String? message;
}

/// Результат `POST /chat/call/{callId}/accept`.
class AcceptResult {
  const AcceptResult.ok() : ok = true, status = null;
  const AcceptResult.gone(this.status) : ok = false;

  /// Звонок ещё ждал ответа и закреплён за этим устройством.
  final bool ok;

  /// Почему принять не получилось: уже отменён, принят в другом месте и т.п.
  final ChatCallStatus? status;
}

class ChatCallRepository {
  ChatCallRepository._();
  static final ChatCallRepository instance = ChatCallRepository._();

  static const _log = 'chat.call';

  /// `GET`, `/ringing`, `/heartbeat` есть не на всех версиях бэкенда.
  /// 404 = маршрута нет (несуществующий звонок бэкенд отдаёт как 410),
  /// поэтому до перезапуска приложения такой эндпоинт больше не дёргаем.
  bool _statusUnsupported = false;
  bool _ringingUnsupported = false;
  bool _heartbeatUnsupported = false;

  /// Коды, которыми бэкенд отвечает на действие над звонком, который уже
  /// не в нужном состоянии (принят на другом устройстве, отменён, истёк).
  static bool _isStateConflict(ApiException e) =>
      e.statusCode == 409 || e.statusCode == 410 || e.statusCode == 422;

  Future<Map<String, dynamic>> _deviceBody([Map<String, dynamic>? extra]) async {
    return {
      'device_id': await DeviceIdentity.instance.id(),
      'platform': DeviceIdentity.instance.platform,
      ...?extra,
    };
  }

  /// Просит бэкенд разослать входящий звонок собеседнику (VoIP/FCM + Reverb для веба).
  Future<RingResult> ringDirectCall({
    required String chatId,
    required String room,
    String? topic,
  }) async {
    try {
      final decoded = await ApiClient.instance.post(
        ChatCallRoutes.ringUrl(chatId),
        body: await _deviceBody({
          'room': room,
          if (topic != null && topic.isNotEmpty) 'topic': topic,
          'is_video': true,
        }),
      );
      final data = ApiEnvelope.unwrapDataMap(decoded);
      final callId = data['call_id']?.toString();
      final status = ChatCallStatus.tryParse(data['status']);
      return RingResult(
        callId: callId != null && callId.isNotEmpty ? callId : null,
        status: status,
      );
    } on ApiException catch (e) {
      AppLogger.d('ringDirectCall failed: $e', name: _log, error: e);
      if (e.statusCode == 409) {
        return RingResult(status: ChatCallStatus.busy, message: e.message);
      }
      return RingResult(status: ChatCallStatus.failed, message: e.message);
    } catch (e, st) {
      AppLogger.d(
        'ringDirectCall failed',
        name: _log,
        error: e,
        stackTrace: st,
      );
      return const RingResult(status: ChatCallStatus.failed);
    }
  }

  /// `GET /chat/call/{callId}` — статус звонка. `null`, если узнать не удалось.
  Future<ChatCallStatus?> fetchStatus(String callId) async {
    if (_statusUnsupported) return null;
    try {
      final decoded = await ApiClient.instance.get(
        ChatCallRoutes.statusUrl(callId),
      );
      final data = ApiEnvelope.unwrapDataMap(decoded);
      return ChatCallStatus.tryParse(data['status']);
    } on ApiException catch (e) {
      if (e.statusCode == 404) _statusUnsupported = true;
      // Звонок не найден — для клиента это «завершён».
      if (e.statusCode == 410) return ChatCallStatus.ended;
      AppLogger.d('fetchStatus($callId) failed: $e', name: _log);
      return null;
    } catch (e) {
      AppLogger.d('fetchStatus($callId) failed: $e', name: _log);
      return null;
    }
  }

  /// `POST /chat/call/{callId}/ringing` — устройство показало звонок.
  /// Ответ содержит актуальный статус: если звонок уже отменён, вернётся
  /// финальный статус и звонок нужно сразу убрать.
  Future<ChatCallStatus?> markRinging(String callId) async {
    if (_ringingUnsupported) return null;
    try {
      final decoded = await ApiClient.instance.post(
        ChatCallRoutes.ringingUrl(callId),
        body: await _deviceBody(),
      );
      final data = ApiEnvelope.unwrapDataMap(decoded);
      return ChatCallStatus.tryParse(data['status']);
    } on ApiException catch (e) {
      if (e.statusCode == 404) _ringingUnsupported = true;
      if (_isStateConflict(e)) return fetchStatus(callId);
      AppLogger.d('markRinging failed: $e', name: _log);
      return null;
    } catch (e) {
      AppLogger.d('markRinging failed: $e', name: _log);
      return null;
    }
  }

  /// `POST /chat/call/{callId}/accept` — сообщить, что звонок принят на этом
  /// устройстве. Если звонок уже не ждёт ответа — [AcceptResult.gone].
  Future<AcceptResult> acceptCall(String callId) async {
    try {
      final decoded = await ApiClient.instance.post(
        ChatCallRoutes.acceptUrl(callId),
        body: await _deviceBody(),
      );
      final data = ApiEnvelope.unwrapDataMap(decoded);
      final status = ChatCallStatus.tryParse(data['status']);
      if (status != null && status != ChatCallStatus.accepted) {
        return AcceptResult.gone(status);
      }
      return const AcceptResult.ok();
    } on ApiException catch (e) {
      if (_isStateConflict(e)) {
        return AcceptResult.gone(
          await fetchStatus(callId) ?? ChatCallStatus.ended,
        );
      }
      // Сеть/старый бэкенд — не мешаем разговору, комната всё равно общая.
      AppLogger.d('acceptCall failed: $e', name: _log);
      return const AcceptResult.ok();
    } catch (e, st) {
      AppLogger.d('acceptCall failed', name: _log, error: e, stackTrace: st);
      return const AcceptResult.ok();
    }
  }

  /// `POST /chat/call/{callId}/decline` — отклонить входящий звонок.
  Future<void> declineCall(
    String callId, {
    ChatCallEndReason reason = ChatCallEndReason.declined,
  }) async {
    try {
      await ApiClient.instance.post(
        ChatCallRoutes.declineUrl(callId),
        body: await _deviceBody({'reason': reason.wire}),
      );
    } catch (e, st) {
      AppLogger.d(
        'declineCall(${reason.wire}) failed',
        name: _log,
        error: e,
        stackTrace: st,
      );
    }
  }

  /// `POST /chat/call/{callId}/end` — отменить до ответа или завершить разговор.
  Future<void> endCall(
    String callId, {
    ChatCallEndReason reason = ChatCallEndReason.hangup,
  }) async {
    try {
      await ApiClient.instance.post(
        ChatCallRoutes.endUrl(callId),
        body: await _deviceBody({'reason': reason.wire}),
      );
    } catch (e, st) {
      AppLogger.d(
        'endCall(${reason.wire}) failed',
        name: _log,
        error: e,
        stackTrace: st,
      );
    }
  }

  /// `POST /chat/call/{callId}/heartbeat` — подтверждает, что клиент в
  /// разговоре, и возвращает статус звонка (финальный — пора отключаться).
  Future<ChatCallStatus?> heartbeat(String callId) async {
    if (_heartbeatUnsupported) return null;
    try {
      final decoded = await ApiClient.instance.post(
        ChatCallRoutes.heartbeatUrl(callId),
        body: await _deviceBody(),
      );
      final data = ApiEnvelope.unwrapDataMap(decoded);
      return ChatCallStatus.tryParse(data['status']);
    } on ApiException catch (e) {
      if (e.statusCode == 404) _heartbeatUnsupported = true;
      if (_isStateConflict(e)) return ChatCallStatus.ended;
      return null;
    } catch (_) {
      return null;
    }
  }
}
