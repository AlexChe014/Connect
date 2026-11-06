/// Тело запроса `POST /booking/update/{id}` (form-data).
class UpdateBookingRequest {
  final DateTime? datetimeStart;
  final DateTime? datetimeEnd;
  final String? theme;
  final String? description;
  final String? link;
  final List<int>? userIds;
  final bool? isPrivate;

  /// Новый объект брони. Занятость на этот интервал проверяет бэкенд.
  final int? modelType;
  final int? modelId;

  /// Обновить всю серию повторяющихся броней (`update_all=1`).
  final bool? updateAll;

  /// Доп. услуги: ключ — id услуги, значение — количество (`add[id]`).
  /// См. [additionsPayload].
  final Map<int, int>? additions;

  const UpdateBookingRequest({
    this.datetimeStart,
    this.datetimeEnd,
    this.theme,
    this.description,
    this.link,
    this.userIds,
    this.isPrivate,
    this.modelType,
    this.modelId,
    this.updateAll,
    this.additions,
  });

  /// Что отправить в [additions]: `null`, если заказ не менялся. Бэкенд
  /// заменяет заказ присланным списком, а пустой список в form-data не
  /// передать — поэтому снятые разом услуги уходят с количеством 0.
  static Map<int, int>? additionsPayload(
    Map<int, int> original,
    Map<int, int> current,
  ) {
    final selected = {
      for (final entry in current.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    final unchanged =
        selected.length == original.length &&
        selected.entries.every((e) => original[e.key] == e.value);
    if (unchanged) return null;
    return selected.isNotEmpty
        ? selected
        : {for (final id in original.keys) id: 0};
  }

  List<MapEntry<String, String>> toFormEntries() {
    final entries = <MapEntry<String, String>>[];

    // Бэкенд ждёт unix-секунды (`date_format:U`). Для серии с `update_all`
    // он сам переносит остальные встречи на то же время суток.
    if (datetimeStart case final start?) {
      entries.add(
        MapEntry('datetime_start', '${start.millisecondsSinceEpoch ~/ 1000}'),
      );
    }
    if (datetimeEnd case final end?) {
      entries.add(
        MapEntry('datetime_end', '${end.millisecondsSinceEpoch ~/ 1000}'),
      );
    }

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

    if (isPrivate case final private?) {
      entries.add(MapEntry('is_private', private ? '1' : '0'));
    }

    if (modelType != null && modelId != null) {
      entries.add(MapEntry('model_type', '$modelType'));
      entries.add(MapEntry('model_id', '$modelId'));
    }

    if (updateAll == true) {
      entries.add(const MapEntry('update_all', '1'));
    }

    final adds = additions;
    if (adds != null) {
      for (final entry in adds.entries) {
        entries.add(MapEntry('add[${entry.key}]', entry.value.toString()));
      }
    }

    return entries;
  }
}
