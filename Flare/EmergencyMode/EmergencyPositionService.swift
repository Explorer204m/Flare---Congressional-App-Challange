import Foundation
import CoreLocation

/// GPS position for Emergency Mode. Runs only while the screen is open, and asks for less
/// as the battery drops. Nothing here leaves the phone.
@MainActor
final class EmergencyPositionService: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isDenied = false

    private let manager = CLLocationManager()
    private var running = false
    private var tier: PowerTier = .normal

    override init() {
        super.init()
        manager.delegate = self
        isDenied = Self.denied(manager.authorizationStatus)
    }

    private static func denied(_ status: CLAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }

    func start(tier: PowerTier) {
        self.tier = tier
        configure()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            running = true
        default:
            break
        }
    }

    func apply(tier: PowerTier) {
        self.tier = tier
        configure()
    }

    func stop() {
        manager.stopUpdatingLocation()
        running = false
    }

    /// Ask for a fresh position right now.
    func refreshNow() {
        if running { manager.requestLocation() }
    }

    private func configure() {
        switch tier {
        case .normal:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 10
        case .saver:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 50
        case .critical:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 100
        }
    }
}

extension EmergencyPositionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isDenied = Self.denied(status)
            if status == .authorizedWhenInUse || status == .authorizedAlways, !self.running {
                self.manager.startUpdatingLocation()
                self.running = true
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in self.location = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last position; the screen shows how old it is.
    }
}
