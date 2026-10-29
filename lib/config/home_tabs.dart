import 'dart:async';

/// Порядок вкладок нижнего меню — индексы для `initialIndex` маршрута `/home`.
abstract final class HomeTabs {
  static const int today = 0;
  static const int chats = 1;
  static const int calls = 2;
  static const int mail = 3;
  static const int more = 4;

  static final _reselected = StreamController<int>.broadcast();

  /// Тап по уже открытой вкладке — её индекс. Вкладка прокручивается
  /// в начало, как в iOS.
  static Stream<int> get reselected => _reselected.stream;

  static void notifyReselected(int index) => _reselected.add(index);
}
