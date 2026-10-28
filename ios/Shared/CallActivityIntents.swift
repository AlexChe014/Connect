import AppIntents
import Foundation

/// Кнопки Live Activity звонка. LiveActivityIntent выполняется в процессе
/// приложения (звонок идёт — приложение живо), а AppDelegate передаёт
/// действие в Dart (LiveActivityService → JitsiMeetingService).
extension Notification.Name {
  static let connectCallAction = Notification.Name("ConnectCallAction")
}

struct EndCallIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Завершить звонок"

  func perform() async throws -> some IntentResult {
    await MainActor.run {
      NotificationCenter.default.post(name: .connectCallAction, object: "end")
    }
    return .result()
  }
}

struct ToggleMuteIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Микрофон"

  func perform() async throws -> some IntentResult {
    await MainActor.run {
      NotificationCenter.default.post(name: .connectCallAction, object: "toggleMute")
    }
    return .result()
  }
}
