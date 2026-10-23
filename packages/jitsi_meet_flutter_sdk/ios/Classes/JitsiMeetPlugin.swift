import Flutter
import UIKit
import JitsiMeetSDK

public class JitsiMeetPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, FlutterSceneLifeCycleDelegate {
    weak var registrar: FlutterPluginRegistrar?
    var jitsiMeetViewController: JitsiMeetViewController?
    var eventSink: FlutterEventSink?

    /// Connect fork: conference embedded into the Flutter tree.
    weak var embeddedView: JitsiMeetConferencePlatformView?
    let audioRoutes = JitsiAudioRouteController()

    /// The view the control methods act on: embedded first, then the
    /// legacy full-screen controller.
    private var activeJitsiView: JitsiMeetView? {
        embeddedView?.jitsiMeetView ?? jitsiMeetViewController?.jitsiMeetView
    }

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
        audioRoutes.onChange = { [weak self] state in
            self?.emit(["event": "audioRouteChanged", "data": state])
        }
    }

    private var flutterViewController: UIViewController? {
        registrar?.viewController
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "jitsi_meet_flutter_sdk", binaryMessenger: registrar.messenger())
        let instance = JitsiMeetPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addSceneDelegate(instance)

        let eventChannel = FlutterEventChannel(name: "jitsi_meet_flutter_sdk_events", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)

        registrar.register(
            JitsiMeetConferenceViewFactory(plugin: instance),
            withId: "jitsi_meet_flutter_sdk/conference_view",
            gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyEager
        )
    }

    func emit(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            return
        case "join":
            join(call, result: result)
            return
        case "hangUp":
            hangUp(call, result: result)
            return
        case "setAudioMuted":
            setAudioMuted(call, result: result)
            return
        case "setVideoMuted":
            setVideoMuted(call, result: result)
            return
        case "sendEndpointTextMessage":
            sendEndpointTextMessage(call, result: result)
            return
        case "toggleScreenShare":
            toggleScreenShare(call, result: result)
            return
        case "openChat":
            openChat(call, result: result)
            return
        case "sendChatMessage":
            sendChatMessage(call, result: result)
            return
        case "closeChat":
            closeChat(call, result: result)
            return
        case "retrieveParticipantsInfo":
            retrieveParticipantsInfo(call, result: result)
            return
        case "enterPiP":
            enterPiP(call, result: result)
            return
        case "toggleCamera":
            activeJitsiView?.toggleCamera()
            result("Successfully toggled camera")
            return
        case "setAudioRoute":
            let arguments = call.arguments as? [String: Any]
            audioRoutes.select(arguments?["route"] as? String ?? "", from: embeddedView?.view())
            result("Successfully set audio route")
            return
        case "refreshAudioRoute":
            audioRoutes.notify()
            result("Successfully refreshed audio route")
            return
        default:
          result(FlutterMethodNotImplemented)
        }
    }

    static func buildOptions(_ arguments: [String: Any]) -> JitsiMeetConferenceOptions {
        let serverURL = arguments["serverURL"] as? String
        let room = arguments["room"] as? String
        let token = arguments["token"] as? String
        let configOverrides = arguments["configOverrides"] as? Dictionary<String, Any>
        let featureFlags = arguments["featureFlags"] as? Dictionary<String, Any>
        let rawUserInfo = arguments["userInfo"] as? [String: Any] ?? [:]
        let displayName = rawUserInfo["displayName"] as? String
        let email = rawUserInfo["email"] as? String
        var avatar: URL? = nil
        if let rawAvatar = rawUserInfo["avatar"] as? String {
            avatar = URL(string: rawAvatar)
        }
        var userInfo: JitsiMeetUserInfo? = nil
        if (displayName != nil || email != nil || avatar != nil) {
            userInfo = JitsiMeetUserInfo(displayName: displayName, andEmail: email, andAvatar: avatar)
        }

        return JitsiMeetConferenceOptions.fromBuilder { (builder) in
            if let serverURL = serverURL {
                builder.serverURL = URL(string: serverURL)
            }
            if (room != nil) {
                builder.room = room;
            }
            if (token != nil) {
                builder.token = token;
            }
            configOverrides?.forEach { key, value in
                builder.setConfigOverride(key, withValue: value);
            }
            featureFlags?.forEach { key, value in
                builder.setFeatureFlag(key, withValue: value);
            }
            if (userInfo != nil) {
                builder.userInfo = userInfo
            }
        }
    }

    private func join(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any]
        let room = arguments["room"] as? String
        let options = JitsiMeetPlugin.buildOptions(arguments)

        guard let viewController = flutterViewController else {
            result(FlutterError(
                code: "UNAVAILABLE",
                message: "Flutter view controller is not available (UIScene lifecycle).",
                details: nil
            ))
            return
        }
        guard let sink = eventSink else {
            result(FlutterError(
                code: "NO_EVENT_SINK",
                message: "Event stream not listened to. Call JitsiMeetEventListener first.",
                details: nil
            ))
            return
        }
        jitsiMeetViewController = JitsiMeetViewController.init(options: options, eventSink: sink)
        jitsiMeetViewController!.modalPresentationStyle = .overFullScreen
        viewController.present(jitsiMeetViewController!, animated: true)
        result("Successfully joined meeting \(room ?? "")")
    }

    private func hangUp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        activeJitsiView?.hangUp()
        result("Successfully hung up")
    }

    private func setAudioMuted(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any]
        let muted = arguments["muted"] as! Bool
        activeJitsiView?.setAudioMuted(muted)
        result("Successfully set audio \(muted)")
    }

    private func setVideoMuted(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any]
        let muted = arguments["muted"] as! Bool
        activeJitsiView?.setVideoMuted(muted)
        result("Successfully set video \(muted)")
    }

    private func sendEndpointTextMessage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any]
        let to = arguments["to"] as? String
        let message: String = arguments["message"] as! String
        activeJitsiView?.sendEndpointTextMessage(message, to)
        result("Successfully send endpoint text message \(to ?? "")")
    }

    private func toggleScreenShare(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any]
        let enabled = arguments["enabled"] as! Bool
        activeJitsiView?.toggleScreenShare(enabled)
        result("Successfully toggled screen share \(enabled)")
    }

    private func openChat(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any]
        let to = arguments["to"] as? String
        activeJitsiView?.openChat(to)
        result("Successfully opened chat \(to ?? "")")
    }

    private func sendChatMessage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any]
        let to = arguments["to"] as? String
        let message: String = arguments["message"] as! String
        activeJitsiView?.sendChatMessage(message, to)
        result("Successfully sent chat message \(to ?? "")")
    }

    private func closeChat(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        activeJitsiView?.closeChat()
        result("Successfully closed chat")
    }

    private func retrieveParticipantsInfo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        activeJitsiView?.retrieveParticipantsInfo({ [weak self] (data: [Any]?) in
            self?.emit(["event": "participantsInfoRetrieved", "data": data ?? []])
        })
        result("Successfully retrieved participants info")
    }

    private func enterPiP(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        jitsiMeetViewController?.enterPicture(inPicture: [:])
        result("Successfully entered Picture in Picture")
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}
