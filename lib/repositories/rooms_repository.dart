import 'package:connect/config/routes/rooms_routes.dart';
import 'package:connect/models/meeting_room.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';

class RoomsRepository {
  RoomsRepository._();
  static final RoomsRepository instance = RoomsRepository._();

  Future<List<MeetingRoom>> getAll() async {
    final decoded = await ApiClient.instance.get(RoomsRoutes.allUrl);
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить переговорные',
    );
    return list
        .map((e) => MeetingRoom.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

