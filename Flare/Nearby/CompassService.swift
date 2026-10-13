import Foundation
import CoreLocation

/// Continuous heading and position, used only while the compass screen is open.
/// It stops as soon as the screen goes away, so it doesn't drain the battery.
@MainActor
final class CompassService: NSObject, ObservableObject {
    /// Degrees clockwise from true north (magnetic north if true north isn't known yet).
    @Published private(set) var heading: Double?
    @Published private(set) var location: CLLocation?

    let headingAvailable = CLLocationManager.headingAvailable()
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        manager.headingFilter = 3
    }

    func start() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if headingAvailable { manager.startUpdatingHeading() }
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        heading = nil
    }
}

extension CompassService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.location = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last known values; the screen says when the data is old or missing.
    }
}
