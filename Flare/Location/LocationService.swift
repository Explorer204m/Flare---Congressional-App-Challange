import Foundation
import CoreLocation
import Combine

/// Thin wrapper around Core Location.
///
/// Battery-conscious by design: it asks for a single approximate fix
/// (`requestLocation`) when the app starts and when it returns to the
/// foreground, rather than running continuous updates. Country-level
/// lookup does not need a precise position.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latestFix: CLLocation?
    @Published private(set) var isLocating = false
    @Published private(set) var lastErrorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Asks for permission the first time, otherwise requests one fix.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestFix()
        default:
            break
        }
    }

    func requestFix() {
        guard isAuthorized else { return }
        isLocating = true
        manager.requestLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.requestFix() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.isLocating = false
            self.lastErrorMessage = nil
            self.latestFix = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.isLocating = false
            self.lastErrorMessage = message
        }
    }
}
