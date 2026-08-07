import '../api_config.dart';

class InfrastructureRoutes {
  InfrastructureRoutes._();

  static const String getBuildings = '/infrastructure/building/get';
  static const String getSpacesByBuilding = '/infrastructure/space/get';
  static const String getEquipmentByBuilding = '/infrastructure/equipment/get';

  static String get buildingsUrl => '${ApiConfig.baseUrl}$getBuildings';

  static String spacesByBuildingUrl(int buildingId) =>
      '${ApiConfig.baseUrl}$getSpacesByBuilding/$buildingId/building';

  static String equipmentByBuildingUrl(int buildingId) =>
      '${ApiConfig.baseUrl}$getEquipmentByBuilding/$buildingId/building';
}

