import SwiftUI
import UIKit

/// The Background protection switch with what it does, what it costs, and what is missing.
/// Shown on the Fall detection screen and the Area alerts screen.
struct BackgroundProtectionCard: View {
    @ObservedObject private var protection = BackgroundProtection.shared
    @ObservedObject private var fall = FallDetectionController.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { protection.isEnabled }, set: { protection.setEnabled($0) })) {
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(FlareColor.link)
                    Text("Background protection")
                        .font(.flareSection)
                        .foregroundStyle(FlareColor.text)
                }
            }
            .tint(FlareColor.accent)

            Text("Keeps Flare running when it isn't on screen, so fall detection keeps watching with the phone in your pocket, and area alerts are checked every 5 minutes (15 in Emergency Mode) and sent as notifications.")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)

            if protection.isEnabled { statusLines }

            Text("Costs: more battery, because location stays on (at low accuracy), and the location indicator shows. Swiping Flare away in the app switcher, or restarting the phone, stops it until you open Flare again.")
                .font(.flareCaption)
                .foregroundStyle(FlareColor.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onAppear { protection.refreshNotificationStatus() }
    }

    @ViewBuilder
    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            if protection.locationDenied {
                line(ok: false, "Location is off for Flare, so it can't run in the background.")
                settingsButton
            } else if protection.hasAlways {
                line(ok: true, protection.isRunning ? "Running. Location: Always." : "Location: Always.")
            } else {
                line(ok: protection.isRunning,
                     "Location is set to While Using. Flare keeps running after you leave it, but iOS can't restart it if it stops. Choose Always in Settings for the most reliable protection.")
                settingsButton
            }

            if protection.notificationsAllowed == false {
                line(ok: false, "Notifications are off for Flare, so background fall alerts and area alerts can't reach you.")
                settingsButton
            } else if protection.notificationsAllowed == true {
                line(ok: true, "Notifications on. To read them on the lock screen, set Show Previews to Always for Flare in Settings \u{203A} Notifications.")
            }

            if fall.isEnabled {
                line(ok: fall.isWatchingInBackground || !protection.isRunning,
                     fall.isWatchingInBackground ? "Fall detection is watching in the background." : "Fall detection will watch in the background while this runs.")
            } else {
                line(ok: false, "Fall detection is off, so only area alerts run in the background.")
            }
        }
    }

    private var settingsButton: some View {
        LinkButton(title: "Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }

    private func line(ok: Bool, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? FlareColor.ready : FlareColor.warning)
                .padding(.top, 1)
            Text(text)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.text)
        }
    }
}
