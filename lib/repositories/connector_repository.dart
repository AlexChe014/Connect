import 'package:connect/config/routes/connector_routes.dart';
import 'package:connect/models/connector/connector_session.dart';
import 'package:connect/models/connector/schedule_connector_request.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';

class ConnectorRepository {
  ConnectorRepository._();
  static final ConnectorRepository instance = ConnectorRepository._();

  /// Мгновенная видеовстреча (`POST /connector/instant`).
  Future<ConnectorSession> createInstant({
    String? topic,
    List<int> userIds = const [],
  }) async {
    final body = <String, dynamic>{};
    final topicValue = topic?.trim();
    if (topicValue != null && topicValue.isNotEmpty) {
      body['topic'] = topicValue;
    }
    if (userIds.isNotEmpty) {
      body['users'] = userIds;
    }

    final decoded = await ApiClient.instance.post(
      ConnectorRoutes.instantUrl,
      body: body.isEmpty ? null : body,
    );
    return _unwrapSession(
      decoded,
      defaultErrorMessage: 'Не удалось создать видеовстречу',
    );
  }

  /// Запланировать встречу (`POST /connector/schedule`).
  Future<ConnectorSession> schedule(ScheduleConnectorRequest request) async {
    final decoded = await ApiClient.instance.post(
      ConnectorRoutes.scheduleUrl,
      body: request.toJson(),
    );
    return _unwrapSession(
      decoded,
      defaultErrorMessage: 'Не удалось запланировать видеовстречу',
    );
  }

  /// Получить JWT для входа (`GET /connector/join/{room}`).
  Future<ConnectorSession> join(String room) async {
    final decoded = await ApiClient.instance.get(ConnectorRoutes.joinUrl(room));
    return _unwrapSession(
      decoded,
      defaultErrorMessage: 'Не удалось подключиться к видеовстрече',
    );
  }

  /// Метаданные встречи (`GET /connector/{room}`).
  Future<ConnectorSession> getRoom(String room) async {
    final decoded = await ApiClient.instance.get(ConnectorRoutes.roomUrl(room));
    return _unwrapSession(
      decoded,
      defaultErrorMessage: 'Не удалось получить данные встречи',
    );
  }

  ConnectorSession _unwrapSession(
    Map<String, dynamic> decoded, {
    required String defaultErrorMessage,
  }) {
    final data = ApiEnvelope.unwrapDataMap(decoded, defaultErrorMessage: defaultErrorMessage);
    final session = ConnectorSession.fromJson(data);
    if (session.room.isEmpty) {
      throw ApiException(500, 'Сервер не вернул идентификатор комнаты');
    }
    return session;
  }
}
