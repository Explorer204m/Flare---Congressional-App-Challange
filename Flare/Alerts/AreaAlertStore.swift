import Foundation
import Combine
import CoreLocation
import UIKit

/// Official warnings for where the person is, checked regularly.
///
/// - Weather and flood warnings: US National Weather Service, for US locations only
///   (sends the position, rounded to about 100 m, to api.weather.gov).
/// - Major disasters worldwide: GDACS. Flare downloads the whole current list and picks the
///   nearby events on the phone, so no location is sent.
///
/// Checked every 5 minutes (every 15 in Emergency Mode, to save battery) while Flare is open,
/// and in the background too when Background protection is on. The GDACS list itself is only
/// downloaded every 30 minutes (or after moving far). The last result is saved so it can be
/// shown offline, with the time each source was last updated. These are extra: the phone's own
/// government alerts (Wireless Emergency Alerts and similar) are the reliable channel.
@MainActor
final class AreaAlertStore: ObservableObject {
    static let shared = AreaAlertStore()

    static let normalInterval: TimeInterval = 5 * 60
    static let emergencyInterval: TimeInterval = 15 * 60
    /// Major disasters change slowly, and the GDACS list is the larger download.
    static let gdacsInterval: TimeInterval = 30 * 60
    /// Countries and territories the National Weather Service covers.
    static let nwsCountries: Set<String> = ["US", "PR", "GU", "VI", "AS", "MP", "UM"]

    /// Current alerts, most serious first.
    @Published private(set) var alerts: [AreaAlert] = []
    @Published private(set) var checkedAt: Date?
    @Published private(set) var checkFailed = false
    @Published private(set) var isChecking = false
    /// The last check included local weather warnings (only in the US).
    @Published private(set) var coversWeather = false
    /// When each source last answered successfully. `checkedAt` is the latest of the two, so
    /// these are what the alerts screen shows to say how fresh each list really is.
    @Published private(set) var weatherCheckedAt: Date?
    @Published private(set) var gdacsCheckedAt: Date?

    /// GDACS events carry no end time, so a list older than this is flagged as possibly out of date.
    static let gdacsStaleAfter: TimeInterval = 2 * 60 * 60
    /// Shortest pause of the check loop, so a check that is overdue but can't run right now
    /// (one is already in progress) never becomes a busy loop.
    private static let minimumPause: TimeInterval = 30

    var interval: TimeInterval {
        EmergencyModeController.shared.isActive ? Self.emergencyInterval : Self.normalInterval
    }

    private var location: CLLocation?
    private var foreground = false
    private var loop: Task<Void, Never>?
    private var lastAttempt: Date?
    private var nwsAlerts: [AreaAlert] = []
    private var gdacsAlerts: [AreaAlert] = []
    private var gdacsCenter: CLLocation?
    private var notifiedKeys: Set<String> = []
    private let fileURL: URL
    private var cancellables = Set<AnyCancellable>()

    private struct Saved: Codable {
        var nws: [AreaAlert]
        var gdacs: [AreaAlert]
        var checkedAt: Date?
        var coversWeather: Bool
        var notifiedKeys: [String]
        // Added later; missing in older saved files.
        var weatherCheckedAt: Date?
        var gdacsCheckedAt: Date?
    }

    private init() {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent("Flare", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("area-alerts.json")
        load()

        // Turning Emergency Mode on or off changes the interval, so work out the next check
        // again. Delivered after the change, so `interval` already reads the new value.
        EmergencyModeController.shared.$isActive
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func appBecameActive() {
        foreground = true
        reschedule()
        // Opening Flare checks again if the last attempt is more than 2 minutes old.
        if location != nil, (lastAttempt.map { Date().timeIntervalSince($0) > 120 } ?? true) {
            Task { await checkNow() }
        }
    }

    func appLeft() {
        foreground = false
        reschedule()
    }

    func backgroundStateChanged() { reschedule() }

    func update(location newLocation: CLLocation) {
        let first = location == nil
        location = newLocation
        guard first else { return }
        // The loop doesn't run without a location; start it now that there is one.
        reschedule()
        if foreground || BackgroundProtection.shared.isRunning {
            Task { await checkNow() }
        }
    }

    /// Runs while Flare is open, or in the background while Background protection keeps it awake.
    /// Sleeps until the next check is due (5 or 15 minutes after the last attempt) instead of
    /// waking every minute. Called again whenever the due time can change: Emergency Mode on or
    /// off, any check finishing (automatic or "Check now"), the first location, and app or
    /// Background protection changes.
    private func reschedule() {
        loop?.cancel()
        loop = nil
        guard foreground || BackgroundProtection.shared.isRunning else { return }
        // Nothing to check without a location; update(location:) calls this again.
        guard location != nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = max(Self.minimumPause, self.nextDue.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
                // Recomputed after waking: the due time may have moved while asleep.
                if self.nextDue <= Date() {
                    // A separate task, so rescheduling (which cancels this loop) never cancels
                    // a download half way and turns it into a reported failure.
                    await Task { await self.checkNow() }.value
                }
            }
        }
    }

    private var nextDue: Date {
        (lastAttempt ?? .distantPast).addingTimeInterval(interval)
    }

    // MARK: Checking

    func checkNow() async {
        guard let location, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let now = Date()
        lastAttempt = now

        var succeeded = false
        var failed = false

        let country = EmergencyStore.savedSelection()?.countryCode
        let wantsWeather = country.map { Self.nwsCountries.contains($0) } ?? false
        if wantsWeather {
            do {
                nwsAlerts = try await Self.fetchNWS(near: location)
                weatherCheckedAt = now
                succeeded = true
            } catch {
                failed = true
            }
        } else {
            nwsAlerts = []
        }

        let movedFar = gdacsCenter.map { $0.distance(from: location) > 50_000 } ?? true
        let gdacsDue = gdacsCheckedAt.map { now.timeIntervalSince($0) >= Self.gdacsInterval } ?? true
        if gdacsDue || movedFar {
            do {
                gdacsAlerts = try await Self.fetchGDACS(near: location)
                gdacsCheckedAt = now
                gdacsCenter = location
                succeeded = true
            } catch {
                failed = true
            }
        } else {
            succeeded = true
        }

        coversWeather = wantsWeather
        checkFailed = failed
        if succeeded { checkedAt = now }
        publish(now: now)
        notifyNewAlerts()
        save()
        // The next check is due one interval after this attempt. This also cancels the loop
        // task that may have called this; reschedule() starts a fresh one.
        reschedule()
    }

    /// The GDACS list hasn't been updated for a while. Its events have no end time, so some
    /// may already be over.
    var gdacsMayBeStale: Bool {
        guard !gdacsAlerts.isEmpty else { return false }
        guard let gdacsCheckedAt else { return true }
        return Date().timeIntervalSince(gdacsCheckedAt) > Self.gdacsStaleAfter
    }

    private func publish(now: Date) {
        alerts = (nwsAlerts + gdacsAlerts)
            .filter { !$0.isExpired(at: now) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return (lhs.effective ?? .distantPast) > (rhs.effective ?? .distantPast)
            }
    }

    /// Severe and extreme alerts become a notification when Flare isn't on screen, once per warning.
    /// While Flare is open the banner on Home shows them instead.
    private func notifyNewAlerts() {
        let onScreen = UIApplication.shared.applicationState == .active
        let currentKeys = Set(alerts.map { $0.notifyKey })
        for alert in alerts where !notifiedKeys.contains(alert.notifyKey) {
            if !onScreen && alert.severity >= .severe {
                FlareNotifications.postAreaAlert(alert)
            }
        }
        // Forget warnings that ended, so a new one with the same name notifies again.
        notifiedKeys = currentKeys
    }

    // MARK: Network

    nonisolated private static func fetchNWS(near location: CLLocation) async throws -> [AreaAlert] {
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
        let point = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
        components.queryItems = [URLQueryItem(name: "point", value: point)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        // The NWS asks every app to identify itself; it has no API key.
        request.setValue("Flare emergency app (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try AreaAlertParser.nws(data)
    }

    nonisolated private static func fetchGDACS(near location: CLLocation) async throws -> [AreaAlert] {
        let url = URL(string: "https://www.gdacs.org/gdacsapi/api/events/geteventlist/events4app")!
        let request = URLRequest(url: url, timeoutInterval: 30)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try AreaAlertParser.gdacs(data, near: location)
    }

    // MARK: Saving

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        nwsAlerts = saved.nws
        gdacsAlerts = saved.gdacs
        checkedAt = saved.checkedAt
        coversWeather = saved.coversWeather
        notifiedKeys = Set(saved.notifiedKeys)
        weatherCheckedAt = saved.weatherCheckedAt
        // For display only: gdacsCenter isn't saved, so the first check after launch still
        // downloads the GDACS list.
        gdacsCheckedAt = saved.gdacsCheckedAt
        publish(now: Date())
    }

    private func save() {
        let saved = Saved(nws: nwsAlerts, gdacs: gdacsAlerts, checkedAt: checkedAt,
                          coversWeather: coversWeather, notifiedKeys: Array(notifiedKeys),
                          weatherCheckedAt: weatherCheckedAt, gdacsCheckedAt: gdacsCheckedAt)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        // Reveals roughly where the person is: protected until first unlock (so background
        // checks can still write it), and excluded from backups.
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
