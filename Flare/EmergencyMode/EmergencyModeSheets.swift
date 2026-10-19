import SwiftUI
import UIKit
import CoreLocation

// MARK: - Medical ID and contacts

/// What a helper needs to know about the person, and one-tap calls to their emergency contacts.
struct EmergencyMedicalView: View {
    let contacts: [EmergencyContactPerson]
    @EnvironmentObject private var medical: MedicalIDStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if medical.medicalID.isEmpty {
                            card {
                                Text("No Medical ID has been set up yet. Leave Emergency Mode and open the Medical ID tab to add your details and emergency contacts.")
                                    .font(.flareSecondary)
                                    .foregroundStyle(FlareColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            summary
                            if !contacts.isEmpty { contactList }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Medical ID")
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

    private var summary: some View {
        let info = medical.medicalID
        let lines: [(String, String)] = [
            ("Blood type", info.bloodType?.rawValue ?? ""),
            ("Allergies", info.allergies),
            ("Conditions", info.conditions),
            ("Medications", info.medications),
            ("Organ donor", info.organDonation == .unspecified ? "" : info.organDonation.label),
            ("Notes", info.notes)
        ].filter { !$0.1.isEmpty }

        return card {
            VStack(alignment: .leading, spacing: 10) {
                if !info.fullName.isEmpty {
                    Text(info.fullName)
                        .font(.flareSection)
                        .foregroundStyle(FlareColor.text)
                }
                if let dob = info.dateOfBirth {
                    Text(info.age.map { "Age \($0) \u{00B7} born \(dob.formatted(date: .long, time: .omitted))" }
                         ?? "Born \(dob.formatted(date: .long, time: .omitted))")
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                ForEach(lines, id: \.0) { line in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.0)
                            .font(.flareCaption)
                            .foregroundStyle(FlareColor.secondaryText)
                        Text(line.1)
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var contactList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Emergency contacts")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            ForEach(contacts.prefix(5)) { contact in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                        if !contact.relationship.isEmpty {
                            Text(contact.relationship)
                                .font(.flareCaption)
                                .foregroundStyle(FlareColor.secondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    if let url = Dialer.telURL(for: contact.phone) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Call", systemImage: "phone.fill")
                                .font(.flareBody)
                                .foregroundStyle(FlareColor.onFlare)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(FlareGradient.flare))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Call \(contact.displayName)")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(cornerRadius: 14)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

// MARK: - Coordinates, battery guard, no signal

struct EmergencyDetailsView: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var position: EmergencyPositionService
    @Binding var keepAwake: Bool
    let here: CLLocation?
    let placeName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showGuide = false

    private var tier: PowerTier { battery.tier }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        positionCard
                        batteryCard
                        noSignalCard
                        FallToggleCard()
                        LinkButton(title: "Make Emergency Mode one tap") { showGuide = true }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.flareBody)
                }
            }
            .sheet(isPresented: $showGuide) { EmergencyModeGuideView() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Position

    @ViewBuilder
    private var positionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where you are")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)

            if let here {
                let code = PlusCode.encode(latitude: here.coordinate.latitude,
                                           longitude: here.coordinate.longitude)
                Text(LocationMessage.coordinateText(here))
                    .font(.archivo(.extraBold, size: 26, relativeTo: .title2))
                    .foregroundStyle(FlareColor.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let code {
                    Text("Plus Code  \(code)")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                }
                let accuracy = Int(max(here.horizontalAccuracy, 1).rounded())
                let clock = FixAge.clockTime(here.timestamp)
                FixAgeText(timestamp: here.timestamp) { age in
                    "Accuracy about \(accuracy) m \u{00B7} saved \(age) (\(clock))"
                }
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
                if let placeName {
                    Text("Near \(placeName)")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                }

                HStack(spacing: 10) {
                    Button {
                        let text = LocationMessage.coordinateText(here) + (code.map { "  \($0)" } ?? "")
                        UIPasteboard.general.string = text
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        pill(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)

                    Button {
                        position.refreshNow()
                    } label: {
                        pill(position.isRefining ? "Updating\u{2026}" : "Update now",
                             systemImage: position.isRefining ? "location.magnifyingglass" : "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(position.isRefining)
                }
                .padding(.top, 4)

                if here.horizontalAccuracy > 100 {
                    Text("The position is approximate right now. Move to open sky for a better fix.")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.warning)
                }
            } else if position.isDenied {
                Text("Location is off for Flare. Turn it on in Settings to see your coordinates.")
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.warning)
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(FlareColor.link)
                    Text("Finding your position\u{2026}")
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func pill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.flareBody)
            .foregroundStyle(FlareColor.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.12)))
    }

    // MARK: Battery guard

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battery guard")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)

            HStack(alignment: .firstTextBaseline) {
                Text(battery.percentText)
                    .font(.archivo(.extraBold, size: 34, relativeTo: .largeTitle))
                    .foregroundStyle(FlareColor.text)
                Text(battery.isCharging ? "Charging" : tier.title)
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.secondaryText)
            }

            Text(tier.detail)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)

            Text(estimateText)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)

            if battery.thermalState == .serious || battery.thermalState == .critical {
                Text("The phone is hot. Keep it out of the sun and avoid using it more than you need to.")
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.warning)
            }

            VStack(alignment: .leading, spacing: 8) {
                checklistRow(
                    done: battery.lowPowerMode,
                    text: battery.lowPowerMode
                        ? "Low Power Mode is on."
                        : "Turn on Low Power Mode (Control Center, or Settings > Battery). Flare can't do this for you.")
                checklistRow(done: true,
                             text: "Flare dims the screen and checks GPS only every few minutes. Before you send your location it asks for a precise fix for up to 10 seconds.")
                checklistRow(done: false,
                             text: "Close apps you don't need, and lower the brightness more if you can still read the screen.")
            }

            Toggle(isOn: $keepAwake) {
                Text("Keep the screen on")
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
            }
            .tint(FlareColor.accent)

            Text("Flare can only change its own power use. iPhone apps can't pause other apps or change system settings.")
                .font(.flareCaption)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var estimateText: String {
        if battery.isCharging { return "Charging, so no time estimate." }
        if let hours = battery.hoursRemaining {
            let totalMinutes = Int((hours * 60).rounded())
            let h = totalMinutes / 60, m = totalMinutes % 60
            let span = h > 0 ? "\(h) h \(m) min" : "\(m) min"
            return "About \(span) left at the current rate. This is a rough estimate that changes with use."
        }
        return "Estimating time left\u{2026} this needs about 5 minutes and a 1% drop."
    }

    private func checklistRow(done: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? FlareColor.ready : FlareColor.secondaryText)
                .padding(.top, 1)
            Text(text)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: No signal

    private var noSignalCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                bullet("Move to open ground, higher up and away from buildings. Signal is usually better outdoors.")
                bullet("Try the call anyway. In many countries an emergency call can connect through another carrier's network even when your own shows no bars.")
                bullet("If calls fail, use \u{201C}Send my location by SMS\u{201D}. A text can get through on a weak signal, and may be held and sent when the signal returns.")
                bullet("Some iPhones (iPhone 14 and later, where it is offered) can contact emergency services by satellite when there is no cell or Wi-Fi coverage. Check Settings > Emergency SOS to see what your iPhone and country support. Flare can't use satellite itself, so it can only point you to this.")
                bullet("Airplane Mode saves battery, but it blocks calls and texts. Turn it off before you try to call.")
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(FlareColor.police)
                Text("No signal?")
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
            }
        }
        .tint(FlareColor.secondaryText)
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
