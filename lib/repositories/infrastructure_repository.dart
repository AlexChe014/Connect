import 'package:connect/config/routes/infrastructure_routes.dart';
import 'package:connect/models/infrastructure/building.dart';
import 'package:connect/models/infrastructure/equipment.dart';
import 'package:connect/models/infrastructure/space.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/services/paginated.dart';
import 'package:connect/config/api_config.dart';

class SpacesAndTypes {
  final List<Space> spaces;

  const SpacesAndTypes({
    required this.spaces,
  });
}

class InfrastructureRepository {
  InfrastructureRepository._();
  static final InfrastructureRepository instance = InfrastructureRepository._();

  Future<List<Building>> getActiveBuildings() async {
    final decoded = await ApiClient.instance.get(InfrastructureRoutes.buildingsUrl);

    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить список офисов',
    );
    return list
        .whereType<Map>()
        .map((e) => Building.fromJson(e.cast<String, dynamic>()))
        .where((b) => b.isActive)
        .toList();
  }

  Future<SpacesAndTypes> getActiveSpacesAndTypes(int buildingId) async {
    final decoded =
        await ApiClient.instance.get(InfrastructureRoutes.spacesByBuildingUrl(buildingId));

    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось получить список этажей',
    );

    List spacesRaw = const [];

    if (data is List) {
      spacesRaw = data;
    } else if (data is Map<String, dynamic>) {
      final candidateSpaces =
          data['spaces'] ?? data['floors'] ?? data['items'] ?? data['data'];
      if (candidateSpaces is List) spacesRaw = candidateSpaces;
    }

    final spaces = spacesRaw
        .whereType<Map>()
        .map((e) => Space.fromJson(e.cast<String, dynamic>()))
        .where((s) => s.isActive)
        .toList();

    return SpacesAndTypes(spaces: spaces);
  }

  Future<List<Equipment>> getActiveEquipment(int buildingId) async {
    String? nextUrl = InfrastructureRoutes.equipmentByBuildingUrl(buildingId);
    final all = <Equipment>[];

    while (nextUrl != null) {
      final decoded = await ApiClient.instance.get(nextUrl);
      final page = ApiPaginatedEnvelope.unwrapPaginated<Equipment>(
        decoded,
        defaultErrorMessage: 'Не удалось получить список оборудования',
        mapItem: (json) => Equipment.fromJson(json),
      );
      all.addAll(page.data.where((e) => e.isActive));
      nextUrl = _normalizeNextPageUrl(page.nextPageUrl);
    }

    return all;
  }

  String? _normalizeNextPageUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final nextUri = Uri.tryParse(trimmed);
    if (nextUri == null) return null;

    final baseUri = Uri.parse(ApiConfig.baseUrl);
    return nextUri
        .replace(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.hasPort ? baseUri.port : null,
        )
        .toString();
  }
}

