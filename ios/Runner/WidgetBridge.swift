import ActivityKit
import CallKit
import Flutter
import Foundation
import WidgetKit

/// Мост Dart ↔ Live Activity звонка и виджет «Сегодня».
///
/// `connect/live_activity`: start / update / end (LiveActivityService в Dart);
/// обратно — `action` с "end" / "toggleMute" от кнопок Live Activity.
/// `connect/home_widget`: setToday(json) (HomeWidgetService в Dart).
final class WidgetBridge {
  private var callActivity: Activity<CallActivityAttributes>?
  private var liveActivityChannel: FlutterMethodChannel?
  private var actionObserver: NSObjectProtocol?
  private let callObserver = CXCallObserver()

  func register(with registry: FlutterPluginRegistry) {
    if let registrar = registry.registrar(forPlugin: "ConnectLiveActivity") {
      let channel = FlutterMethodChannel(name: "connect/live_activity", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleLiveActivity(call, result: result)
      }
      liveActivityChannel = channel
    }
    if let registrar = registry.registrar(forPlugin: "ConnectHomeWidget") {
      let channel = FlutterMethodChannel(name: "connect/home_widget", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "setToday" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let defaults = UserDefaults(suiteName: ConnectAppGroup.id)
        if let json = call.arguments as? String {
          defaults?.set(Data(json.utf8), forKey: ConnectAppGroup.todayKey)
        } else {
          defaults?.removeObject(forKey: ConnectAppGroup.todayKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      }
    }

    actionObserver = NotificationCenter.default.addObserver(
      forName: .connectCallAction, object: nil, queue: .main
    ) { [weak self] note in
      guard let action = note.object as? String else { return }
      self?.liveActivityChannel?.invokeMethod("action", arguments: action)
    }

    // Активность, пережившая перезапуск приложения, без звонка не нужна.
    endAllCallActivities()
  }

  private func handleLiveActivity(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      start(args)
      result(nil)
    case "update":
      update(args)
      result(nil)
    case "end":
      endAllCallActivities()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func state(from args: [String: Any]) -> CallActivityAttributes.ContentState {
    var startedAt: Date?
    if let ms = args["startedAt"] as? NSNumber {
      startedAt = Date(timeIntervalSince1970: ms.doubleValue / 1000)
    }
    return CallActivityAttributes.ContentState(
      phase: args["phase"] as? String ?? "connecting",
      startedAt: startedAt,
      muted: args["muted"] as? Bool ?? false
    )
  }

  private func start(_ args: [String: Any]) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    endAllCallActivities()
    // Звонок, принятый через CallKit, iOS уже показывает своим индикатором
    // в Dynamic Island — вторая активность рядом только мешает.
    if callObserver.calls.contains(where: { !$0.hasEnded }) {
      NSLog("[live-activity] CallKit call in progress — skipping")
      return
    }
    let attributes = CallActivityAttributes(
      title: args["title"] as? String ?? "Звонок",
      isVideo: args["isVideo"] as? Bool ?? false
    )
    do {
      callActivity = try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state(from: args), staleDate: nil),
        pushType: nil
      )
    } catch {
      NSLog("[live-activity] start failed: %@", error.localizedDescription)
    }
  }

  private func update(_ args: [String: Any]) {
    guard let activity = callActivity else { return }
    let content = ActivityContent(state: state(from: args), staleDate: nil)
    Task { await activity.update(content) }
  }

  private func endAllCallActivities() {
    callActivity = nil
    for activity in Activity<CallActivityAttributes>.activities {
      Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
  }
}
