import Foundation
import UIKit

/// Lowers the screen brightness while Emergency Mode is open and puts everything back after.
/// iOS lets an app change brightness for itself only; Flare never raises it above what the
/// person had set.
@MainActor
final class ScreenPowerSession: ObservableObject {
    private var originalBrightness: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }

    /// Applies the brightness cap for a tier (does nothing for `.normal`).
    func apply(tier: PowerTier) {
        guard let screen else { return }
        if originalBrightness == nil { originalBrightness = screen.brightness }
        guard let original = originalBrightness else { return }
        if let cap = tier.brightnessCap {
            screen.brightness = min(original, CGFloat(cap))
        } else {
            screen.brightness = original
        }
    }

    func setKeepAwake(_ keepAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }

    /// Puts brightness and auto-lock back the way they were.
    func restore() {
        if let original = originalBrightness, let screen {
            screen.brightness = original
        }
        originalBrightness = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
