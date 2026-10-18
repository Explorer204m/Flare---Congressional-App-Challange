import Foundation
import CoreLocation

/// GPS position for Emergency Mode. To save battery it asks for one fix now and then one
/// every few minutes (the interval grows as the battery drops) instead of keeping GPS
/// running. It runs only while the screen is open, and nothing here leaves the phone.
@MainActor
final class EmergencyPositionService: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isDenied = false

    private let manager = CLLocationManager()
    private var loop: Task<Void, Never>?
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
            beginLoop()
        default:
            break
        }
    }

    func apply(tier: PowerTier) {
        self.tier = tier
        configure()
        if loop != nil { beginLoop() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Ask for a fresh position right now (for example just before sending a location).
    func refreshNow() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    /// One fix now, then one every `tier.locationInterval`.
    private func beginLoop() {
        loop?.cancel()
        manager.requestLocation()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = self?.tier.locationInterval ?? 600
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                self?.manager.requestLocation()
            }
        }
    }

    private func configure() {
        manager.desiredAccuracy = tier == .critical
            ? kCLLocationAccuracyHundredMeters
            : kCLLocationAccuracyNearestTenMeters
    }
}

extension EmergencyPositionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isDenied = Self.denied(status)
            if (status == .authorizedWhenInUse || status == .authorizedAlways), self.loop == nil {
                self.beginLoop()
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
