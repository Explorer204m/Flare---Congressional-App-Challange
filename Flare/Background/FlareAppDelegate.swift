import UIKit

/// Restarts Background protection when iOS launches Flare in the background
/// (for example after a significant location change), before any screen exists.
final class FlareAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundProtection.shared.resumeIfNeeded()
        return true
    }
}
