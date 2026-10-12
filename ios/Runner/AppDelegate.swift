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
  private var voipChannel: FlutterMethodChannel?
  /// Отдельный provider только для «пустых» звонков: VoIP-пуш после выхода
  /// из аккаунта или служебный VoIP-пуш (отмена/ответ на другом устройстве).
  /// iOS требует сообщить о звонке на каждый VoIP-пуш.
  private lazy var placeholderCallProvider: CXProvider = {
    let config = CXProviderConfiguration()
    config.includesCallsInRecents = false
    return CXProvider(configuration: config)
  }()

  /// Должен совпадать с CallConfig.incomingRingTimeout в Dart.
  private static let incomingRingTimeoutMs = 35000

  /// Тот же ключ, что IncomingCallService._dismissedPrefsKey: callId, погашенные
  /// по событию с сервера, — Dart не отправит на них `decline`.
  private static let dismissedCallsDefaultsKey = "flutter.callkit_remote_dismissed"

  /// shared_preferences хранит ключи в UserDefaults с префиксом `flutter.`.
  private static let authTokenDefaultsKey = "flutter.auth_bearer_token"

  private var isLoggedIn: Bool {
    let token = UserDefaults.standard.string(forKey: AppDelegate.authTokenDefaultsKey)
    return !(token ?? "").isEmpty
  }

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
    // Разлогиненное устройство не подписываем на звонки.
    registry.desiredPushTypes = isLoggedIn ? [PKPushType.voIP] : []
    voipRegistry = registry

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ConnectVoipPush") else {
      return
    }
    let channel = FlutterMethodChannel(name: "connect/voip_push", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setEnabled":
        let enabled = (call.arguments as? Bool) ?? false
        self?.setVoipPushEnabled(enabled)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    voipChannel = channel
  }

  /// Вкл/выкл доставку VoIP-пушей: выключаем при выходе из аккаунта,
  /// включаем после входа.
  private func setVoipPushEnabled(_ enabled: Bool) {
    guard let registry = voipRegistry else { return }
    let desired: Set<PKPushType> = enabled ? [.voIP] : []
    // Повторная установка того же значения может снова дёрнуть didUpdate.
    if registry.desiredPushTypes == desired { return }
    NSLog("[callkit] VoIP push %@", enabled ? "enabled" : "disabled")
    registry.desiredPushTypes = desired
  }

  // MARK: - PushKit

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
    NSLog("[callkit] PushKit VoIP token updated, length=%d", deviceToken.count)
    // Плагин шлёт событие в Dart (DidUpdateDevicePushTokenVoip).
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
    UserDefaults.standard.set(deviceToken, forKey: "connect_voip_token")
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    NSLog("[callkit] PushKit VoIP token invalidated")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
    UserDefaults.standard.removeObject(forKey: "connect_voip_token")
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

    // Пуш пришёл уже после выхода (сервер ещё не отвязал токен): iOS всё
    // равно требует сообщить о звонке, поэтому сразу его завершаем.
    if !isLoggedIn {
      NSLog("[callkit] VoIP push while logged out, ending immediately")
      reportPlaceholderCall(completion: completion)
      return
    }

    // APNs может класть поля в корень или во вложенный data / custom.
    let raw = payload.dictionaryPayload
    let dict = flattenVoipPayload(raw)

    // Служебный VoIP-пуш: звонок отменён / принят или отклонён на другом
    // устройстве. FCM не будит убитое приложение на iOS, поэтому бэкенд
    // шлёт такие события через VoIP — гасим звонящий CallKit здесь же.
    let pushType = stringValue(dict["type"]) ?? "chat_call"
    if pushType != "chat_call" {
      if let callId = stringValue(dict["call_id"]) {
        endRingingCall(callId: callId, status: stringValue(dict["status"]) ?? pushType)
      }
      reportPlaceholderCall(completion: completion)
      return
    }

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
    info["duration"] = AppDelegate.incomingRingTimeoutMs
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

    // Обязательно сразу показать CallKit — иначе iOS отзовёт VoIP entitlement.
    let data = flutter_callkit_incoming.Data(args: info)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      completion()
    }
  }

  /// Сообщить о «пустом» звонке и сразу завершить его — выполняет требование
  /// iOS 13+ к каждому VoIP-пушу, не показывая пользователю звонок.
  private func reportPlaceholderCall(completion: @escaping () -> Void) {
    let uuid = UUID()
    placeholderCallProvider.reportNewIncomingCall(with: uuid, update: CXCallUpdate()) { [weak self] _ in
      self?.placeholderCallProvider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
      completion()
    }
  }

  /// Погасить звонящий (ещё не принятый) CallKit-звонок с этим callId.
  private func endRingingCall(callId: String, status: String) {
    guard let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance else { return }
    let target = plugin.activeCalls().first { call in
      (call["id"] as? String)?.lowercased() == callId.lowercased()
    }
    guard let call = target else {
      NSLog("[callkit] VoIP %@ for unknown call, nothing to end", status)
      return
    }
    if (call["accepted"] as? Bool) == true || (call["isAccepted"] as? Bool) == true {
      NSLog("[callkit] VoIP %@ for accepted call — ignored", status)
      return
    }
    NSLog("[callkit] VoIP %@ — ending ringing call", status)
    markDismissed(callId)
    plugin.endCall(flutter_callkit_incoming.Data(args: ["id": callId]))
  }

  private func markDismissed(_ callId: String) {
    let defaults = UserDefaults.standard
    var list = defaults.stringArray(forKey: AppDelegate.dismissedCallsDefaultsKey) ?? []
    if list.contains(callId) { return }
    list.append(callId)
    if list.count > 20 { list.removeFirst(list.count - 20) }
    defaults.set(list, forKey: AppDelegate.dismissedCallsDefaultsKey)
  }

  /// Разворачивает вложенные словари (data / custom), чтобы call_id/room
  /// находились и при FCM-style обёртке, и при «плоском» APNs VoIP.
  private func flattenVoipPayload(_ raw: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in raw {
      let k = String(describing: key)
      if k == "aps" { continue }
      if let nested = value as? [AnyHashable: Any] {
        for (nk, nv) in nested {
          out[String(describing: nk)] = nv
        }
      } else {
        out[k] = value
      }
    }
    return out
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

  // MARK: - CallkitIncomingAppDelegate

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    // На UIScene-based Flutter (SceneDelegate) ОС не всегда сама поднимает сцену
    // при ответе на звонок из фона — без этого экран CallKit закрывается,
    // а показать Jitsi/экран звонка не на чем, пока пользователь не откроет
    // приложение вручную. Форсируем активацию сцены явно.
    //
    // Важно: если приложение просто свёрнуто (не убито), сцена уже существует,
    // но неактивна — запрос на создание НОВОЙ сцены (nil) в этом случае не
    // подходит, т.к. UIApplicationSupportsMultipleScenes = false. Нужно
    // активировать именно существующую сессию, если она есть.
    if #available(iOS 13.0, *) {
      DispatchQueue.main.async {
        let existingSession = UIApplication.shared.connectedScenes
          .first(where: { $0 is UIWindowScene })?.session
        NSLog("[callkit] onAccept: activating scene, existingSession=%@", existingSession == nil ? "nil (new)" : "existing")
        UIApplication.shared.requestSceneSessionActivation(existingSession, userActivity: nil, options: nil) { error in
          NSLog("[callkit] requestSceneSessionActivation failed: %@", error.localizedDescription)
        }
      }
    }
    // Dart подхватит Accept через onEvent или recoverPendingAcceptedCalls при cold start.
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {}

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}

  func providerDidReset() {}
}
