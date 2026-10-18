import Foundation
import UIKit
import Combine

/// How much Emergency Mode should save, based on the battery.
enum PowerTier: Int, Comparable {
    case normal, saver, critical

    static func < (lhs: PowerTier, rhs: PowerTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .saver: return "Saving power"
        case .critical: return "Critical"
        }
    }

    var detail: String {
        switch self {
        case .normal: return "Screen dimmed a little, GPS checked every 5 minutes."
        case .saver: return "Dimmer screen, GPS checked every 10 minutes."
        case .critical: return "Dimmest screen, GPS checked every 20 minutes."
        }
    }

    /// Highest screen brightness Flare allows in this step.
    /// Flare only ever lowers brightness; it never raises it.
    var brightnessCap: Double? {
        switch self {
        case .normal: return 0.6
        case .saver: return 0.5
        case .critical: return 0.3
        }
    }

    /// How often Emergency Mode asks GPS for a new position. A single fix every few minutes
    /// uses far less battery than keeping GPS running.
    var locationInterval: TimeInterval {
        switch self {
        case .normal: return 5 * 60
        case .saver: return 10 * 60
        case .critical: return 20 * 60
        }
    }

    static func forBattery(level: Double?, isCharging: Bool, lowPowerMode: Bool) -> PowerTier {
        if let level, level >= 0 {
            if level <= 0.10 && !isCharging { return .critical }
            if level <= 0.30 && !isCharging { return .saver }
        }
        return lowPowerMode ? .saver : .normal
    }
}

struct BatterySample: Equatable {
    let date: Date
    let level: Double
}

/// A rough time-left figure from how fast the battery has dropped since Emergency Mode
/// opened. iOS does not provide one, so this is an estimate and the screen says so.
enum DrainEstimator {
    static let minimumSpan: TimeInterval = 300      // watch for at least 5 minutes
    static let minimumDrop = 0.01                   // and at least a 1% drop

    static func hoursRemaining(samples: [BatterySample]) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        let drop = first.level - last.level
        guard span >= minimumSpan, drop >= minimumDrop, last.level > 0 else { return nil }
        let ratePerSecond = drop / span
        let hours = last.level / ratePerSecond / 3600
        return min(hours, 72)
    }
}

/// Reads battery level, charging state, Low Power Mode and heat. Reading is all iOS allows:
/// apps cannot see other apps' use or change system power settings.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Double?            // 0...1, nil if unknown
    @Published private(set) var isCharging = false
    @Published private(set) var lowPowerMode = false
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var hoursRemaining: Double?

    private var samples: [BatterySample] = []
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    var tier: PowerTier {
        PowerTier.forBattery(level: level, isCharging: isCharging, lowPowerMode: lowPowerMode)
    }

    var percentText: String {
        guard let level else { return "--" }
        return "\(Int((level * 100).rounded()))%"
    }

    func start() {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()

        let center = NotificationCenter.default
        center.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: center.publisher(for: UIDevice.batteryStateDidChangeNotification),
                   center.publisher(for: .NSProcessInfoPowerStateDidChange),
                   center.publisher(for: ProcessInfo.thermalStateDidChangeNotification))
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func stop() {
        guard started else { return }
        started = false
        cancellables.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func refresh() {
        let device = UIDevice.current
        let raw = Double(device.batteryLevel)
        level = raw >= 0 ? raw : nil
        isCharging = device.batteryState == .charging || device.batteryState == .full
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState

        guard let level, !isCharging else {
            samples.removeAll()
            hoursRemaining = nil
            return
        }
        if samples.last?.level != level {
            samples.append(BatterySample(date: Date(), level: level))
            if samples.count > 60 { samples.removeFirst(samples.count - 60) }
        }
        hoursRemaining = DrainEstimator.hoursRemaining(samples: samples)
    }
}
