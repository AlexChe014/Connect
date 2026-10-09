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
///
/// `GET /booking/get/{id}` отдаёт её как `recurrence_pattern.pattern`;
/// дни недели там в нумерации Carbon: 0 = воскресенье, 1–6 = пн–сб.
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

  /// Берёт `recurring`, а если его нет — `recurrence_pattern.pattern`.
  factory BookingRecurringInfo.fromBookingJson(Map<String, dynamic> json) {
    if (json['recurring'] is Map) {
      return BookingRecurringInfo.fromJson(json['recurring']);
    }
    final pattern = json['recurrence_pattern'];
    return BookingRecurringInfo.fromJson(
      pattern is Map ? pattern['pattern'] : null,
    );
  }

  static const _weekdayShort = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];

  /// Дни недели по порядку с понедельника: «Пн, Ср, Пт».
  String get daysOfWeekLabel {
    final days = daysOfWeek.map((d) => d % 7).toSet().toList()
      ..sort((a, b) => ((a + 6) % 7).compareTo((b + 6) % 7));
    return days.map((d) => _weekdayShort[d]).join(', ');
  }

  /// Подпись для поля «Повторение»; [start] — начало брони,
  /// по нему определяется день для еженедельного повтора.
  String label(DateTime start) {
    if (daysOfWeek.isNotEmpty) return daysOfWeekLabel;
    return switch (type) {
      'daily' => 'Каждый день',
      'weekly' => 'Каждую неделю, ${_weekdayShort[start.weekday % 7]}',
      'monthly' => 'Каждый месяц, ${start.day} числа',
      _ => 'Да',
    };
  }

  /// Дата окончания серии в виде `ДД.ММ.ГГГГ` (или исходная строка).
  String? get endDateLabel {
    final raw = endDate;
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(parsed.day)}.${two(parsed.month)}.${parsed.year}';
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
