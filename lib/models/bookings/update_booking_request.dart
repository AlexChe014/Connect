/// Тело запроса `POST /booking/update/{id}` (form-data).
class UpdateBookingRequest {
  final String? theme;
  final String? description;
  final String? link;
  final List<int>? userIds;

  /// Обновить всю серию повторяющихся броней (`update_all=1`).
  final bool? updateAll;

  /// Доп. услуги: ключ — id услуги, значение — количество (`add[id]`).
  final Map<int, int>? additions;

  const UpdateBookingRequest({
    this.theme,
    this.description,
    this.link,
    this.userIds,
    this.updateAll,
    this.additions,
  });

  List<MapEntry<String, String>> toFormEntries() {
    final entries = <MapEntry<String, String>>[];

    final themeValue = theme?.trim();
    if (themeValue != null) {
      entries.add(MapEntry('theme', themeValue));
    }

    if (description != null) {
      entries.add(MapEntry('description', description!.trim()));
    }

    if (link != null) {
      entries.add(MapEntry('link', link!.trim()));
    }

    if (userIds != null) {
      for (final userId in userIds!) {
        entries.add(MapEntry('users[]', userId.toString()));
      }
    }

    if (updateAll == true) {
      entries.add(const MapEntry('update_all', '1'));
    }

    final adds = additions;
    if (adds != null) {
      for (final entry in adds.entries) {
        if (entry.value > 0) {
          entries.add(MapEntry('add[${entry.key}]', entry.value.toString()));
        }
      }
    }

    return entries;
  }
}
