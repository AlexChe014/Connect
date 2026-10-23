import Flutter
import UIKit
import JitsiMeetSDK

/// Connect fork: creates the embedded conference for
/// `JitsiMeetConferenceView` on the Dart side.
class JitsiMeetConferenceViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: JitsiMeetPlugin?

    init(plugin: JitsiMeetPlugin) {
        self.plugin = plugin
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let view = JitsiMeetConferencePlatformView(
            frame: frame,
            arguments: args as? [String: Any] ?? [:],
            plugin: plugin
        )
        plugin?.embeddedView = view
        return view
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Joins on creation, leaves when Flutter disposes the view.
class JitsiMeetConferencePlatformView: NSObject, FlutterPlatformView {
    private let container: UIView
    private(set) var jitsiMeetView: JitsiMeetView?
    private weak var plugin: JitsiMeetPlugin?

    init(frame: CGRect, arguments: [String: Any], plugin: JitsiMeetPlugin?) {
        self.plugin = plugin
        container = UIView(frame: frame)
        container.backgroundColor = .clear
        super.init()

        let jitsiMeetView = JitsiMeetView(frame: container.bounds)
        jitsiMeetView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        jitsiMeetView.delegate = self
        container.addSubview(jitsiMeetView)
        self.jitsiMeetView = jitsiMeetView

        jitsiMeetView.join(JitsiMeetPlugin.buildOptions(arguments))
        UIApplication.shared.isIdleTimerDisabled = true
        plugin?.audioRoutes.start()
    }

    deinit {
        tearDown()
    }

    func view() -> UIView {
        container
    }

    private func tearDown() {
        guard let view = jitsiMeetView else { return }
        jitsiMeetView = nil
        view.delegate = nil
        view.leave()
        view.removeFromSuperview()
        UIApplication.shared.isIdleTimerDisabled = false
        plugin?.audioRoutes.stop()
    }

    private func emit(_ name: String, _ data: [AnyHashable: Any]? = nil) {
        var event: [String: Any] = ["event": name]
        if let data = data { event["data"] = data }
        plugin?.emit(event)
    }
}

extension JitsiMeetConferencePlatformView: JitsiMeetViewDelegate {
    func conferenceJoined(_ data: [AnyHashable: Any]) {
        emit("conferenceJoined", data)
        plugin?.audioRoutes.notify()
    }

    func conferenceTerminated(_ data: [AnyHashable: Any]) {
        emit("conferenceTerminated", data)
    }

    func conferenceWillJoin(_ data: [AnyHashable: Any]) {
        emit("conferenceWillJoin", data)
    }

    func participantJoined(_ data: [AnyHashable: Any]) {
        emit("participantJoined", data)
    }

    func participantLeft(_ data: [AnyHashable: Any]) {
        emit("participantLeft", data)
    }

    func audioMutedChanged(_ data: [AnyHashable: Any]) {
        emit("audioMutedChanged", data)
    }

    func videoMutedChanged(_ data: [AnyHashable: Any]) {
        emit("videoMutedChanged", data)
        // Jitsi switches the session between voice and video chat modes,
        // which moves audio between the earpiece and the speaker.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.plugin?.audioRoutes.notify()
        }
    }

    func endpointTextMessageReceived(_ data: [AnyHashable: Any]) {
        emit("endpointTextMessageReceived", data)
    }

    func screenShareToggled(_ data: [AnyHashable: Any]) {
        emit("screenShareToggled", data)
    }

    func chatMessageReceived(_ data: [AnyHashable: Any]) {
        emit("chatMessageReceived", data)
    }

    func chatToggled(_ data: [AnyHashable: Any]) {
        emit("chatToggled", data)
    }

    func participantsInfoRetrieved(_ data: [AnyHashable: Any]) {
        emit("participantsInfoRetrieved", data)
    }

    func customButtonPressed(_ data: [AnyHashable: Any]) {
        emit("customButtonPressed", data)
    }

    func ready(toClose data: [AnyHashable: Any]) {
        emit("readyToClose")
    }
}
