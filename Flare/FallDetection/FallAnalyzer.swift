import Foundation

/// How easily a hard impact counts as a possible fall.
enum FallSensitivity: String, CaseIterable, Identifiable {
    case high, standard, low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "High"
        case .standard: return "Standard"
        case .low: return "Low"
        }
    }

    var detail: String {
        switch self {
        case .high: return "Reacts to softer impacts. More false alarms."
        case .standard: return "Balanced. A good starting point."
        case .low: return "Needs a hard impact. Fewer false alarms, may miss gentler falls."
        }
    }

    /// Total acceleration (in g) an impact must reach. Resting is 1 g.
    var impactThreshold: Double {
        switch self {
        case .high: return 2.5
        case .standard: return 3.0
        case .low: return 3.8
        }
    }
}

/// Decides from raw accelerometer readings whether a fall may have happened.
///
/// A fall is reported when all of these happen in order:
/// 1. a hard impact (a short drop in weight first makes a smaller impact count),
/// 2. one second of settling,
/// 3. three seconds of the phone staying almost still (the person is not moving about).
///
/// Anything that moves the phone during step 3 cancels it, so walking away, picking the
/// phone up or running do not count. A phone dropped and left lying still *will* count;
/// that is a false alarm the person dismisses with "I'm OK".
///
/// Pure value logic with no iOS dependencies, so it can be tested on any machine.
struct FallAnalyzer {
    static let freeFallLimit = 0.55          // g, below this the phone is nearly weightless
    static let freeFallMinimum = 0.06        // s of weightlessness that counts
    static let freeFallWindow = 0.7          // s between weightlessness and impact
    static let freeFallBonus = 0.8           // g lower impact threshold after weightlessness
    static let settleTime = 1.0              // s after impact before checking stillness
    static let stillTime = 4.0               // s after impact when stillness is confirmed
    static let stillTolerance = 0.25         // g away from 1 g still counted as "still"
    static let gapReset = 0.5                // s without samples resets everything
    static let afterFallPause = 10.0         // s of silence after reporting a fall
    static let afterCancelPause = 2.0        // s of silence after movement cancels a candidate

    var impactThreshold: Double

    private var freeFallStart: TimeInterval?
    private var lastFreeFall: TimeInterval = -.infinity
    private var impactTime: TimeInterval?
    private var lastSample: TimeInterval?
    private var quietUntil: TimeInterval = -.infinity

    init(impactThreshold: Double) {
        self.impactThreshold = impactThreshold
    }

    /// Feed one reading: total acceleration in g and its timestamp in seconds.
    /// Returns true once, when a fall is confirmed.
    mutating func ingest(magnitude m: Double, at t: TimeInterval) -> Bool {
        defer { lastSample = t }

        if let last = lastSample, t - last > Self.gapReset || t < last {
            reset()
        }
        if t < quietUntil { return false }

        if let hit = impactTime {
            let since = t - hit
            if since >= Self.settleTime && abs(m - 1) > Self.stillTolerance {
                impactTime = nil
                quietUntil = t + Self.afterCancelPause
                return false
            }
            if since >= Self.stillTime {
                impactTime = nil
                quietUntil = t + Self.afterFallPause
                return true
            }
            return false
        }

        if m < Self.freeFallLimit {
            if freeFallStart == nil { freeFallStart = t }
            if let start = freeFallStart, t - start >= Self.freeFallMinimum {
                lastFreeFall = t
            }
        } else {
            freeFallStart = nil
        }

        let needed = (t - lastFreeFall <= Self.freeFallWindow)
            ? impactThreshold - Self.freeFallBonus
            : impactThreshold
        if m >= needed {
            impactTime = t
            freeFallStart = nil
        }
        return false
    }

    mutating func reset() {
        freeFallStart = nil
        lastFreeFall = -.infinity
        impactTime = nil
    }
}
