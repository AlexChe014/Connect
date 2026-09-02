import 'package:connect/config/routes/favorites_routes.dart';
import 'package:connect/models/bookings/bookable_object.dart';
import 'package:connect/models/staff_user.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';

class FavoritesRepository {
  FavoritesRepository._();

  static final FavoritesRepository instance = FavoritesRepository._();

  /// `favoritable_type` для полиморфного избранного. `GET
  /// /user/favorites/types` документирован как `{id, name}[]`, но реально
  /// отдаёт голые id без названий (`[1, 7, 2]`) — сопоставить их с типом
  /// сущности через API невозможно. Значения ниже подтверждены по факту
  /// (сверено с `BookingObjectType.typeId`, используемым для тех же сущностей
  /// в `/booking/get-free`): `7` — сотрудник, `1` — переговорка, `2` —
  /// рабочее место. Объекты бронирования не имеют единого типа — у каждого
  /// свой `favoriteTypeId` (см. `BookableObject`), эта константа — только
  /// запасной вариант, если он почему-то не проставлен.
  static const int _userFavoritableType = 7;
  static const int _fallbackObjectFavoritableType = 1;

  /// `data` в ответе `/favorites/toggle` имеет разную форму для добавления
  /// и удаления (не всегда логическое значение, как в документации) —
  /// смотрим только на `success`, содержимое `data` не разбираем.
  Future<void> _toggle(int favoritableType, int favoritableId) async {
    final decoded = await ApiClient.instance.post(
      FavoritesRoutes.toggleUrl,
      body: {
        'favoritable_type': favoritableType,
        'favoritable_id': favoritableId,
      },
    );
    ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось изменить избранное',
    );
  }

  Future<void> toggleUser(int userId) => _toggle(_userFavoritableType, userId);

  Future<void> toggleObject(int objectId, {int? favoriteTypeId}) =>
      _toggle(favoriteTypeId ?? _fallbackObjectFavoritableType, objectId);

  /// `/user/favorites/*` возвращает не сами сущности, а записи `Favorite`
  /// (`{id, favoritable_type, favoritable_id, favoritable: {...}}`) —
  /// нужная сущность лежит во вложенном `favoritable`, а `favoritable_type`
  /// нужно перенести внутрь неё, иначе `BookableObject` не будет знать свой
  /// собственный тип (нужен, чтобы потом верно убрать объект из избранного).
  static Map<String, dynamic>? _unwrapFavoritable(Object? e) {
    if (e is! Map) return null;
    final map = e.cast<String, dynamic>();
    final nested = map['favoritable'];
    if (nested is! Map) return map;
    final result = nested.cast<String, dynamic>();
    final favoritableType = map['favoritable_type'];
    if (favoritableType != null) {
      result['favoritable_type'] = favoritableType;
    }
    return result;
  }

  Future<List<StaffUser>> getFavoriteUsers() async {
    final decoded = await ApiClient.instance.get(FavoritesRoutes.usersUrl);
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить избранных сотрудников',
    );
    return list
        .map(_unwrapFavoritable)
        .whereType<Map<String, dynamic>>()
        .map(StaffUser.fromJson)
        .toList();
  }

  Future<List<BookableObject>> getFavoriteObjects() async {
    final decoded = await ApiClient.instance.get(FavoritesRoutes.objectsUrl);
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить избранные объекты',
    );
    return list
        .map(_unwrapFavoritable)
        .whereType<Map<String, dynamic>>()
        .map(BookableObject.fromJson)
        .toList();
  }

  Future<Set<String>> getFavoriteUserIds() async {
    final users = await getFavoriteUsers();
    return users.map((u) => u.id).toSet();
  }
}
