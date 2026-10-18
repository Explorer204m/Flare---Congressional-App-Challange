import Foundation
import CoreMotion
import UIKit
import AudioToolbox

/// A fall that may have happened, waiting for the person to answer.
struct FallAlert: Equatable {
    var secondsLeft: Int
    var timedOut: Bool
    /// A practice run started from the Fall detection screen: nothing is ever called or sent.
    var isTest: Bool
}

/// Owns fall detection: the on/off setting, the motion sensor, and the "Are you OK?" countdown.
///
/// Limits (also shown in the app): the motion sensor only runs while Flare is open on screen,
/// because iOS suspends apps in the background. Flare never calls or texts by itself: iOS needs
/// a tap for both, so the alert makes those buttons as large and fast to reach as it can.
@MainActor
final class FallDetectionController: ObservableObject {
    static let shared = FallDetectionController()
    static let countdownSeconds = 30

    @Published private(set) var isEnabled: Bool
    @Published private(set) var sensitivity: FallSensitivity
    @Published private(set) var isMonitoring = false
    @Published private(set) var alert: FallAlert?

    /// False on the Simulator and on devices without an accelerometer.
    var motionAvailable: Bool { motion.isAccelerometerAvailable }

    private static let enabledKey = "flare.fallDetection.enabled"
    private static let sensitivityKey = "flare.fallDetection.sensitivity"

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "flare.fall-detection"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private var inForeground = false
    private var countdownTask: Task<Void, Never>?
    private var deadline = Date.distantPast
    private var idleTimerBefore = false
    private var ignoreUntil = Date.distantPast

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        sensitivity = defaults.string(forKey: Self.sensitivityKey).flatMap(FallSensitivity.init(rawValue:)) ?? .standard
    }

    // MARK: Settings

    /// Off by default. Turning it on starts watching at once if Flare is open.
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            startMonitoring()
        } else {
            stopMonitoring()
            if alert != nil { dismissAlert() }
        }
    }

    func setSensitivity(_ value: FallSensitivity) {
        guard value != sensitivity else { return }
        sensitivity = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.sensitivityKey)
        if isMonitoring {
            stopMonitoring()
            startMonitoring()
        }
    }

    // MARK: App lifecycle

    func appBecameActive() {
        inForeground = true
        startMonitoring()
    }

    func appLeft() {
        inForeground = false
        stopMonitoring()
    }

    // MARK: Motion

    private func startMonitoring() {
        guard isEnabled, inForeground, motionAvailable, !isMonitoring else { return }
        isMonitoring = true
        motion.accelerometerUpdateInterval = 1.0 / 50.0
        let box = AnalyzerBox(FallAnalyzer(impactThreshold: sensitivity.impactThreshold))
        let handler = Self.makeHandler(box: box) { [weak self] in
            Task { @MainActor in self?.fallDetected() }
        }
        motion.startAccelerometerUpdates(to: queue, withHandler: handler)
    }

    private func stopMonitoring() {
        guard isMonitoring else { return }
        motion.stopAccelerometerUpdates()
        isMonitoring = false
    }

    /// Built outside the main actor on purpose: Core Motion calls it on a background queue.
    nonisolated private static func makeHandler(
        box: AnalyzerBox,
        onFall: @escaping @Sendable () -> Void
    ) -> CMAccelerometerHandler {
        return { data, _ in
            guard let data else { return }
            let a = data.acceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            if box.ingest(magnitude: magnitude, at: data.timestamp) { onFall() }
        }
    }

    // MARK: Alert

    private func fallDetected() {
        guard isEnabled, alert == nil, Date() >= ignoreUntil else { return }
        beginAlert(isTest: false)
    }

    /// Shows the alert as a practice run. Never calls or sends anything.
    func startTest() {
        guard alert == nil else { return }
        beginAlert(isTest: true)
    }

    private func beginAlert(isTest: Bool) {
        deadline = Date().addingTimeInterval(TimeInterval(Self.countdownSeconds))
        alert = FallAlert(secondsLeft: Self.countdownSeconds, timedOut: false, isTest: isTest)
        idleTimerBefore = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        UIAccessibility.post(notification: .announcement,
                             argument: isTest ? "Test of the fall alert." : "Fall detected. Are you OK?")

        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.alert != nil else { return }
                self.alarm()
                self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        guard var current = alert else { return }
        let remaining = Int(deadline.timeIntervalSinceNow.rounded(.up))
        current.secondsLeft = max(remaining, 0)
        current.timedOut = remaining <= 0
        if current != alert { alert = current }
    }

    /// Haptic and system alert sound once a second. The sound follows the ringer switch;
    /// the vibration does not.
    private func alarm() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    /// "I'm OK", "End test", or after the person has called for help.
    func dismissAlert() {
        countdownTask?.cancel()
        countdownTask = nil
        guard alert != nil else { return }
        alert = nil
        UIApplication.shared.isIdleTimerDisabled = idleTimerBefore
        ignoreUntil = Date().addingTimeInterval(15)
    }
}

/// Holds the analyzer for the motion queue. Only ever touched from that one serial queue.
private final class AnalyzerBox: @unchecked Sendable {
    private var analyzer: FallAnalyzer

    init(_ analyzer: FallAnalyzer) { self.analyzer = analyzer }

    func ingest(magnitude: Double, at time: TimeInterval) -> Bool {
        analyzer.ingest(magnitude: magnitude, at: time)
    }
}
