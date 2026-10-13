import SwiftUI

/// How to open Emergency Mode in one step, and what iOS does and doesn't allow.
struct EmergencyModeGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        card("What Flare can and can't do",
                             "Flare can save power by itself: it dims the screen, slows GPS and shows less as the battery drops. Like every iPhone app, it can't pause other apps or turn on Low Power Mode, Airplane Mode or Wi-Fi settings for you. The steps below let you do that quickly yourself.")

                        card("1. One tap that also turns on Low Power Mode",
                             "Open the Shortcuts app and make a new shortcut. Add \u{201C}Set Low Power Mode\u{201D} (turn it on), then add Flare's \u{201C}Start Emergency Mode\u{201D} action. Name it Emergency. You can then run it from the Home Screen, a widget or Siri.")

                        card("2. Put it on a button",
                             "Action Button (iPhone 15 Pro and later): Settings > Action Button > Shortcut, then pick your Emergency shortcut. Other iPhones: Settings > Accessibility > Touch > Back Tap, then pick the shortcut for a double or triple tap. If your iPhone doesn't show these options, use the Home Screen or Siri.")

                        card("3. Come back to Flare after the screen locks",
                             "If Flare is the app on screen when the phone locks, iOS brings you back to Flare when you unlock. Open Emergency Mode, then lock the phone to save power. Apps can't make the phone open Flare on its own.")

                        card("4. Optional: lock the phone to Flare",
                             "Guided Access keeps the phone in one app. Turn it on in Settings > Accessibility > Guided Access, open Flare, and triple-click the side button. Test it first: it can also stop you from using other apps until you enter your passcode.")

                        Text("These steps depend on your iPhone model and iOS version. Try them once now, before you need them.")
                            .font(.flareCaption)
                            .foregroundStyle(FlareColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("One-tap setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.flareBody)
                }
            }
        }
    }

    private func card(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.flareBodyLarge)
                .foregroundStyle(FlareColor.text)
            Text(text)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
