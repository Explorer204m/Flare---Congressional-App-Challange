import Foundation
import CoreLocation
import UIKit
import UserNotifications

/// "Background protection": keeps Flare running while it is not on screen, so fall detection
/// keeps watching with the phone in a pocket and area alerts keep being checked.
///
/// iOS has no general "run in the background" permission. What it does allow is for an app to
/// keep running while it receives location updates, which this class does at low accuracy.
/// With "Always" location access it also restarts after iOS stops it, when the person moves a
/// significant distance. Costs (shown in the app): more battery, the location indicator stays
/// on, and iOS periodically asks whether Flare should keep "Always" access.
///
/// Off by default. Swiping Flare away in the app switcher stops it until Flare is opened again.
@MainActor
final class BackgroundProtection: NSObject, ObservableObject {
    static let shared = BackgroundProtection()

    /// The person's choice, saved on the phone.
    @Published private(set) var isEnabled: Bool
    /// Location updates are running, so Flare stays awake in the background.
    @Published private(set) var isRunning = false
    @Published private(set) var authorization: CLAuthorizationStatus
    /// nil until Flare has asked.
    @Published private(set) var notificationsAllowed: Bool?
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private static let enabledKey = "flare.backgroundProtection.enabled"
    private static let askedAlwaysKey = "flare.backgroundProtection.askedAlways"
    private var lowPower = false

    private override init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        authorization = .notDetermined
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    var hasAlways: Bool { authorization == .authorizedAlways }
    var locationDenied: Bool { authorization == .denied || authorization == .restricted }

    // MARK: Settings

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            requestPermissions()
            start()
        } else {
            stop()
        }
    }

    /// Location first ("While Using", then the upgrade to "Always"), plus notifications,
    /// which background fall alerts and area alerts need.
    func requestPermissions() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // the upgrade to Always follows when granted
        case .authorizedWhenInUse:
            askForAlwaysOnce()
        default:
            break
        }
        Task {
            let granted = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationsAllowed = granted ?? false
        }
    }

    /// iOS shows the "Change to Always Allow" prompt only once; after that it is in Settings.
    private func askForAlwaysOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.askedAlwaysKey) else { return }
        defaults.set(true, forKey: Self.askedAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    func refreshNotificationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: notificationsAllowed = true
            case .denied: notificationsAllowed = false
            default: notificationsAllowed = nil
            }
        }
    }

    // MARK: Running

    /// Called at launch (including a background relaunch by iOS) and when Flare comes to the front.
    func resumeIfNeeded() {
        refreshNotificationStatus()
        if isEnabled { start() }
    }

    /// Emergency Mode and a critical battery ask for the lowest-power location updates:
    /// the session only has to keep Flare awake and know roughly where it is.
    func setLowPower(_ value: Bool) {
        guard value != lowPower else { return }
        lowPower = value
        configure()
    }

    private func configure() {
        manager.desiredAccuracy = lowPower ? kCLLocationAccuracyThreeKilometers : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = lowPower ? 1_000 : 100
    }

    private func start() {
        guard isEnabled, !isRunning else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        // Without "Always", iOS only lets location updates start while Flare is on screen.
        // Started then, they keep running in the background (with the location indicator).
        guard status == .authorizedAlways || UIApplication.shared.applicationState == .active else { return }

        configure()
        // Requires "location" in UIBackgroundModes (Config/Info.plist), or iOS stops the app here.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .other
        manager.startUpdatingLocation()
        if status == .authorizedAlways {
            // Lets iOS relaunch Flare after it was stopped, when the person moves on.
            manager.startMonitoringSignificantLocationChanges()
        }
        isRunning = true
        dependentsChanged()
    }

    private func stop() {
        guard isRunning else { return }
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        isRunning = false
        dependentsChanged()
    }

    private func dependentsChanged() {
        FallDetectionController.shared.backgroundStateChanged()
        AreaAlertStore.shared.backgroundStateChanged()
    }

    private func handle(_ location: CLLocation) {
        lastLocation = location
        AreaAlertStore.shared.update(location: location)
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        authorization = status
        guard isEnabled else { return }
        switch status {
        case .authorizedWhenInUse:
            askForAlwaysOnce()
            start()
        case .authorizedAlways:
            if isRunning {
                manager.startMonitoringSignificantLocationChanges()
            } else {
                start()
            }
        case .denied, .restricted:
            stop()
        default:
            break
        }
    }
}

extension BackgroundProtection: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in self.handle(latest) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.handleAuthorization(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary failures (no signal indoors) are normal; updates resume by themselves.
    }
}
