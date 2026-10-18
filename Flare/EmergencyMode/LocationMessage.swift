import Foundation
import SwiftUI
import MessageUI
import CoreLocation

/// The text Emergency Mode prepares for emergency contacts. Flare cannot send it by itself:
/// iOS opens the message and the person taps Send.
enum LocationMessage {
    static func coordinateText(_ location: CLLocation) -> String {
        String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
    }

    enum Reason {
        case help
        /// Sent from the fall alert: the person may not be able to talk.
        case fall
    }

    static func body(for location: CLLocation, placeName: String?,
                     reason: Reason = .help, now: Date = Date()) -> String {
        let lat = String(format: "%.5f", location.coordinate.latitude)
        let lon = String(format: "%.5f", location.coordinate.longitude)
        var lines: [String]
        switch reason {
        case .help:
            lines = ["I need help. This is my location:"]
        case .fall:
            lines = ["Flare detected that I may have fallen. I may not be able to talk or answer. Please call emergency services or come to this location:"]
        }
        lines.append("\(lat), \(lon) (accuracy about \(Int(max(location.horizontalAccuracy, 1).rounded())) m)")
        let minutes = Int(now.timeIntervalSince(location.timestamp) / 60)
        if minutes >= 2 { lines.append("This position is from \(minutes) minutes ago.") }
        lines.append("https://maps.apple.com/?ll=\(lat),\(lon)&q=My%20location")
        if let code = PlusCode.encode(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude) {
            lines.append("Plus Code: \(code)")
        }
        if let placeName, !placeName.isEmpty { lines.append("Near: \(placeName)") }
        lines.append("Sent from Flare.")
        return lines.joined(separator: "\n")
    }
}

/// The system Messages composer. The person reviews the text and taps Send.
struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish()
        }
    }
}
