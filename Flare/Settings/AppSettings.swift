import Foundation
import Combine

/// The choices a person can make in Settings, saved on the phone.
///
/// Fall detection, Background protection and the saved Nearby places keep their own switches
/// (they were there before Settings existed); this holds the rest. Every switch here defaults
/// to ON, so Flare works fully the first time it opens and a person can turn things off.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// US National Weather Service warnings. Sends the position, rounded to about 100 m, to
    /// api.weather.gov, so people who don't want that can turn it off. On by default.
    @Published var weatherAlerts: Bool { didSet { save(weatherAlerts, for: Key.weatherAlerts) } }
    /// GDACS major-disaster alerts. The whole worldwide list is downloaded and filtered on the
    /// phone, so no location is sent.
    @Published var disasterAlerts: Bool { didSet { save(disasterAlerts, for: Key.disasterAlerts) } }
    /// Notify about severe and extreme alerts while Flare isn't on screen.
    @Published var alertNotifications: Bool { didSet { save(alertNotifications, for: Key.alertNotifications) } }
    /// Keep searching Apple Maps for nearby places as the person moves, so the saved copy for
    /// offline use stays fresh. Off: search only when the Nearby tab opens or "Search again" is tapped.
    @Published var nearbyAutoUpdate: Bool { didSet { save(nearbyAutoUpdate, for: Key.nearbyAutoUpdate) } }

    private enum Key {
        static let weatherAlerts = "flare.settings.weatherAlerts"
        static let disasterAlerts = "flare.settings.disasterAlerts"
        static let alertNotifications = "flare.settings.alertNotifications"
        static let nearbyAutoUpdate = "flare.settings.nearbyAutoUpdate"
    }

    private init() {
        let defaults = UserDefaults.standard
        // A switch that was never touched has no saved value: that means on.
        weatherAlerts = defaults.object(forKey: Key.weatherAlerts) as? Bool ?? true
        disasterAlerts = defaults.object(forKey: Key.disasterAlerts) as? Bool ?? true
        alertNotifications = defaults.object(forKey: Key.alertNotifications) as? Bool ?? true
        nearbyAutoUpdate = defaults.object(forKey: Key.nearbyAutoUpdate) as? Bool ?? true
    }

    private func save(_ value: Bool, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
