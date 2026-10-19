import Foundation
import CoreLocation
import UserNotifications

/// Local notifications: posted by Flare on the phone itself, no server involved.
/// Used when something happens while Flare is in the background (a possible fall, a new area alert).
///
/// They follow the person's notification settings. On iPhones with Face ID, notification text is
/// hidden on the lock screen by default ("Show Previews: When Unlocked"); the app explains this.
enum FlareNotifications {
    private static let fallIDs = (0..<16).map { "flare.fall.\($0)" }

    /// A possible fall while Flare is in the background: a reminder every 10 seconds until the
    /// countdown ends, then a "no response" notice for anyone nearby every minute for 10 minutes.
    /// Removed as soon as the person answers.
    static func scheduleFallCountdown(deadline: Date, location: CLLocation?) {
        cancelFall()
        let center = UNUserNotificationCenter.current()
        let remaining = max(deadline.timeIntervalSinceNow, 1)
        var index = 0

        var offset: TimeInterval = 0
        while offset < remaining && index < 3 {
            let content = UNMutableNotificationContent()
            content.title = "Did you fall?"
            content.body = "Flare felt a hard impact and then no movement. Open Flare and tap I'm OK if you're fine. \(Int((remaining - offset).rounded())) seconds left."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "flare.fall"
            add(center, id: fallIDs[index], content: content, after: offset)
            index += 1
            offset += 10
        }

        var helper = "This person may have fallen and may not be able to talk. If you are helping, call the local emergency number and stay with them."
        if let location {
            helper += " Location: \(LocationMessage.coordinateText(location))."
            if let code = PlusCode.encode(latitude: location.coordinate.latitude,
                                          longitude: location.coordinate.longitude) {
                helper += " Plus Code \(code)."
            }
        }
        for minute in 0..<10 where index < fallIDs.count {
            let content = UNMutableNotificationContent()
            content.title = "No response after a possible fall"
            content.body = helper
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "flare.fall"
            add(center, id: fallIDs[index], content: content, after: remaining + TimeInterval(minute * 60))
            index += 1
        }
    }

    static func cancelFall() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: fallIDs)
        center.removeDeliveredNotifications(withIdentifiers: fallIDs)
    }

    /// A new area alert while Flare is not on screen.
    static func postAreaAlert(_ alert: AreaAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.event
        var body = alert.headline ?? alert.sender
        if let expires = alert.expires {
            body += " Until \(expires.formatted(date: .abbreviated, time: .shortened))."
        }
        content.body = body
        content.subtitle = alert.sender
        content.sound = .default
        content.interruptionLevel = alert.severity >= .severe ? .timeSensitive : .active
        content.threadIdentifier = "flare.area-alert"
        add(UNUserNotificationCenter.current(), id: "flare.area.\(alert.id)", content: content, after: 0)
    }

    private static func add(_ center: UNUserNotificationCenter, id: String,
                            content: UNNotificationContent, after seconds: TimeInterval) {
        let trigger = seconds < 1 ? nil : UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
