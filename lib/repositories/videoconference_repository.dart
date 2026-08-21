import 'package:connect/config/routes/videoconference_routes.dart';
import 'package:connect/models/videoconference/videoconference.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';

class VideoconferenceRepository {
  VideoconferenceRepository._();
  static final VideoconferenceRepository instance =
      VideoconferenceRepository._();

  /// Создать конференцию (`POST /videoconference/create`).
  Future<Videoconference> create({String? topic, int? startSeconds}) async {
    final body = <String, dynamic>{};
    final topicValue = topic?.trim();
    if (topicValue != null && topicValue.isNotEmpty) {
      body['topic'] = topicValue;
    }
    if (startSeconds != null) {
      body['start'] = startSeconds;
    }

    final decoded = await ApiClient.instance.post(
      VideoconferenceRoutes.createUrl,
      body: body.isEmpty ? null : body,
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось создать видеоконференцию',
    );
    final meeting = Videoconference.fromJson(data);
    if (meeting.url.isEmpty) {
      throw ApiException(500, 'Сервер не вернул ссылку на конференцию');
    }
    return meeting;
  }

  /// Получить данные конференции (`GET /videoconference/get`).
  Future<Videoconference> getCurrent() async {
    final decoded = await ApiClient.instance.get(VideoconferenceRoutes.getUrl);
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить данные конференции',
    );
    return Videoconference.fromJson(data);
  }
}
