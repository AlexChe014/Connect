import ActivityKit
import Foundation

/// Live Activity идущего звонка: Dynamic Island и экран блокировки.
/// Файл входит и в Runner (запуск/обновление), и в ConnectWidgets (вид).
struct CallActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// `connecting` / `waiting` / `active` / `reconnecting` — как CallPhase в Dart.
    var phase: String
    /// Начало разговора для таймера; до входа собеседника — nil.
    var startedAt: Date?
    var muted: Bool
  }

  /// Имя собеседника или тема встречи.
  var title: String
  var isVideo: Bool
}

/// Общие ключи App Group: приложение пишет, виджет читает.
enum ConnectAppGroup {
  static let id = "group.com.ikson.connect"
  static let todayKey = "today_widget"
}
