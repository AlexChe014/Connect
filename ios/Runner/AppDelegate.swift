import Flutter
import UIKit
import UserNotifications
import PushKit
import CallKit
import AVFoundation
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    let mainQueue = DispatchQueue.main
    let registry = PKPushRegistry(queue: mainQueue)
    registry.delegate = self
    registry.desiredPushTypes = [PKPushType.voIP]
    voipRegistry = registry

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - PushKit

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let dict = payload.dictionaryPayload
    var info: [String: Any?] = [:]

    let callId = stringValue(dict["call_id"]) ?? UUID().uuidString
    let callerName = stringValue(dict["caller_name"]) ?? "Connect"
    let room = stringValue(dict["room"]) ?? ""
    let chatId = stringValue(dict["chat_id"]) ?? ""
    let topic = stringValue(dict["topic"])
    let avatar = stringValue(dict["caller_avatar"])
    let isVideo = stringValue(dict["is_video"]) != "0"

    info["id"] = callId
    info["nameCaller"] = callerName
    info["handle"] = topic ?? callerName
    info["type"] = isVideo ? 1 : 0
    info["avatar"] = avatar
    info["duration"] = 45000
    info["textAccept"] = "Принять"
    info["textDecline"] = "Отклонить"
    info["extra"] = [
      "call_id": callId,
      "chat_id": chatId,
      "room": room,
      "caller_name": callerName,
      "topic": topic as Any,
      "caller_avatar": avatar as Any,
      "is_video": isVideo ? "1" : "0",
    ]

    let data = flutter_callkit_incoming.Data(args: info)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      completion()
    }
  }

  private func stringValue(_ value: Any?) -> String? {
    if let s = value as? String {
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let n = value as? NSNumber {
      return n.stringValue
    }
    return nil
  }

  // MARK: - CallkitIncomingAppDelegate (fulfill actions immediately for Jitsi)

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    // Dart handler sends decline to backend.
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}

  func providerDidReset() {}
}
