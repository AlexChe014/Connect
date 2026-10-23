import AVFoundation
import AVKit
import UIKit

/// Connect fork: audio output for the app's own call controls (the Jitsi
/// toolbox with its route button is hidden in the embedded view).
///
/// Jitsi keeps managing the session category and mode; this only overrides
/// the output port and reports route changes.
class JitsiAudioRouteController: NSObject {
    var onChange: (([String: Any]) -> Void)?

    private var observing = false
    private var pickerView: AVRoutePickerView?

    func start() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    func stop() {
        guard observing else { return }
        observing = false
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        pickerView?.removeFromSuperview()
        pickerView = nil
    }

    @objc private func routeChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.notify() }
    }

    func notify() {
        onChange?(state())
    }

    func select(_ route: String, from anchor: UIView?) {
        let session = AVAudioSession.sharedInstance()
        switch route {
        case "speaker":
            try? session.overrideOutputAudioPort(.speaker)
        case "earpiece":
            try? session.overrideOutputAudioPort(.none)
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
        case "picker":
            showPicker(anchor: anchor)
        default:
            break
        }
        notify()
    }

    /// The system route sheet (AirPods, car, speaker…). There is no public
    /// API to open it, so a hidden picker's button is tapped instead.
    private func showPicker(anchor: UIView?) {
        guard let host = anchor ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return }
        let picker = pickerView ?? AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        picker.alpha = 0.01
        picker.prioritizesVideoDevices = false
        if picker.superview !== host {
            picker.removeFromSuperview()
            host.addSubview(picker)
        }
        pickerView = picker
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .touchUpInside)
            return
        }
    }

    private func state() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.first?.portType
        let current: String
        switch output {
        case .builtInSpeaker?:
            current = "speaker"
        case .builtInReceiver?:
            current = "earpiece"
        case .headphones?, .usbAudio?:
            current = "headphones"
        case .bluetoothA2DP?, .bluetoothHFP?, .bluetoothLE?, .airPlay?, .carAudio?:
            current = "bluetooth"
        default:
            current = "unknown"
        }

        var available = ["speaker"]
        if UIDevice.current.userInterfaceIdiom == .phone {
            available.append("earpiece")
        }
        let inputs = session.availableInputs ?? []
        if inputs.contains(where: { $0.portType == .headsetMic }) || current == "headphones" {
            available.append("headphones")
        }
        if inputs.contains(where: { $0.portType == .bluetoothHFP }) || current == "bluetooth" {
            available.append("bluetooth")
        }
        return ["route": current, "available": available]
    }
}
