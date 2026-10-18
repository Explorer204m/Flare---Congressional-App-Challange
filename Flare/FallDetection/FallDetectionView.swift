import SwiftUI

/// Turn fall detection on or off, set how sensitive it is, and try the alert.
struct FallDetectionView: View {
    @ObservedObject private var fall = FallDetectionController.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        FallToggleCard()
                        sensitivityCard
                        testCard
                        howItWorks
                        limits
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Fall detection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.flareBody)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sensitivity")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            Picker("Sensitivity", selection: Binding(
                get: { fall.sensitivity },
                set: { fall.setSensitivity($0) })) {
                ForEach(FallSensitivity.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            Text(fall.sensitivity.detail)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .opacity(fall.isEnabled ? 1 : 0.5)
        .disabled(!fall.isEnabled)
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try the alert")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            Text("See and hear what happens when a fall is detected. Nothing is called or sent.")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
            Button {
                dismiss()
                // Let the sheet close first so the alert is not hidden behind it.
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    fall.startTest()
                }
            } label: {
                Text("Start a practice alert")
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.link)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(Capsule().stroke(FlareColor.link.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            bullet("Flare reads the phone's motion sensor and looks for a hard impact followed by no movement.")
            bullet("If it sees that, it sounds an alarm and gives you 30 seconds to tap I'm OK.")
            bullet("If you don't answer, the alert stays on screen with a large Call button and a way to send your location.")
            bullet("Motion readings are never saved or sent anywhere.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(FlareColor.warning)
                Text("Limits")
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)
            }
            bullet("Experimental. It can miss a fall, and it can raise a false alarm, for example when the phone is dropped and lies still.")
            bullet("It only works while Flare is open and the screen is on. iPhones pause apps in the background, so it can't watch while the phone is locked or in your pocket with Flare closed. Emergency Mode's \u{201C}Keep the screen on\u{201D} switch helps for longer watches.")
            bullet("Flare can't call or text for you. iPhones need a tap for both, so someone who can't move won't have help sent automatically.")
            bullet("Flare also can't play a recorded message into a phone call: iPhones don't let apps do that. Apple's own Crash Detection and Apple Watch fall detection can place the call and speak for you, and Flare can't. Instead, if you don't answer, the alert shows a card telling anyone nearby what happened, where you are and how to reach your contacts, and the location text says you may not be able to talk.")
            bullet("The alarm sound follows the ringer switch. Vibration plays either way.")
            bullet("Apple Watch has its own fall detection that works in the background. Flare's is separate and doesn't replace it.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}").foregroundStyle(FlareColor.secondaryText)
            Text(text)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The on/off switch with its status line. Used here and in Emergency Mode's Details sheet.
struct FallToggleCard: View {
    @ObservedObject private var fall = FallDetectionController.shared

    private var status: (text: String, color: Color) {
        if !fall.motionAvailable {
            return ("This device has no motion sensor, so fall detection can't run. (The Simulator has none.)",
                    FlareColor.warning)
        }
        if !fall.isEnabled { return ("Off. Nothing is being watched.", FlareColor.secondaryText) }
        if fall.isMonitoring { return ("On and watching. Keep Flare open with the screen on.", FlareColor.ready) }
        return ("On. It starts watching when Flare is open.", FlareColor.secondaryText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { fall.isEnabled }, set: { fall.setEnabled($0) })) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.fall")
                        .foregroundStyle(FlareColor.fire)
                    Text("Fall detection")
                        .font(.flareSection)
                        .foregroundStyle(FlareColor.text)
                    Text("Experimental")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.warning)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .overlay(Capsule().stroke(FlareColor.warning.opacity(0.7), lineWidth: 1))
                }
            }
            .tint(FlareColor.accent)
            .disabled(!fall.motionAvailable)

            Text(status.text)
                .font(.flareSecondary)
                .foregroundStyle(status.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
