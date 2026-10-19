import SwiftUI

/// How long ago a position was saved, at minute resolution.
///
/// `Text(date, style: .relative)` changes every second. This label only changes when the
/// minute count does, and refreshes at once when a new fix arrives or Flare returns to the
/// foreground, so an old position is never left labelled "just now".
struct FixAgeText: View {
    let timestamp: Date
    /// Builds the whole line from the age phrase ("just now", "4 min ago").
    let compose: (String) -> String

    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    init(timestamp: Date, compose: @escaping (String) -> String = { $0 }) {
        self.timestamp = timestamp
        self.compose = compose
    }

    var body: some View {
        Text(compose(FixAge.phrase(since: timestamp, now: now)))
            // Restarts for a new fix and on every return to the foreground; stops off screen.
            .task(id: Trigger(timestamp: timestamp, active: scenePhase == .active)) {
                now = Date()
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    let wait = FixAge.secondsUntilChange(since: timestamp, now: Date())
                    try? await Task.sleep(for: .seconds(wait))
                    if Task.isCancelled { return }
                    now = Date()
                }
            }
    }

    private struct Trigger: Equatable {
        let timestamp: Date
        let active: Bool
    }
}

enum FixAge {
    /// "just now", "1 min ago", "14 min ago", "2 h 5 min ago".
    static func phrase(since timestamp: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(timestamp) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h ago" : "\(hours) h \(rest) min ago"
    }

    /// Seconds until the minute count next changes (never less than 1).
    static func secondsUntilChange(since timestamp: Date, now: Date) -> Double {
        let age = max(0, now.timeIntervalSince(timestamp))
        let next = (age / 60).rounded(.down) * 60 + 60
        return max(1, next - age)
    }

    /// Clock time of the fix, for example "3:42 PM".
    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
