/// Параметры повторяющегося бронирования (form: `recurring[...]`).
class BookingRecurring {
  /// Тип повторения, например `custom`, `daily`, `weekly`.
  final String type;

  /// Дата окончания серии в формате `YYYY-MM-DD`.
  final String endDate;

  /// Дни недели (1 = понедельник … 7 = воскресенье), для `custom` / `weekly`.
  final List<int> daysOfWeek;

  const BookingRecurring({
    required this.type,
    required this.endDate,
    this.daysOfWeek = const [],
  });

  List<MapEntry<String, String>> toFormEntries() {
    final entries = <MapEntry<String, String>>[
      MapEntry('recurring[type]', type),
      MapEntry('recurring[end_date]', endDate),
    ];
    for (final day in daysOfWeek) {
      entries.add(MapEntry('recurring[days_of_week][]', day.toString()));
    }
    return entries;
  }
}

/// Информация о повторении из ответа API.
class BookingRecurringInfo {
  final String? type;
  final String? endDate;
  final List<int> daysOfWeek;

  const BookingRecurringInfo({
    this.type,
    this.endDate,
    this.daysOfWeek = const [],
  });

  factory BookingRecurringInfo.fromJson(dynamic json) {
    if (json is! Map) {
      return const BookingRecurringInfo();
    }
    final map = json.cast<String, dynamic>();
    return BookingRecurringInfo(
      type: map['type'] as String?,
      endDate: (map['end_date'] as String?)?.trim(),
      daysOfWeek: _parseDays(map['days_of_week']),
    );
  }

  static List<int> _parseDays(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) {
          if (e is int) return e;
          if (e is num) return e.toInt();
          if (e is String) return int.tryParse(e.trim());
          return null;
        })
        .whereType<int>()
        .toList();
  }
}
