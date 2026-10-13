import SwiftUI
import UIKit
import MessageUI
import CoreLocation

/// Emergency Mode: the few things that matter in an emergency on one dark, low-power screen.
/// It saves battery by itself (dimmer screen, less GPS, fewer items as the battery drops)
/// but, like any iPhone app, it cannot pause other apps or change system power settings.
struct EmergencyModeView: View {
    @EnvironmentObject private var store: EmergencyStore
    @EnvironmentObject private var medical: MedicalIDStore
    @EnvironmentObject private var controller: EmergencyModeController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @StateObject private var battery = BatteryMonitor()
    @StateObject private var position = EmergencyPositionService()
    @StateObject private var power = ScreenPowerSession()

    @State private var keepAwake = false
    @State private var showMessage = false
    @State private var showGuide = false
    @State private var copied = false

    private var tier: PowerTier { battery.tier }

    /// Best position we have: live GPS here, else the last fix Home used.
    private var here: CLLocation? { position.location ?? store.location.latestFix }

    private var contacts: [EmergencyContactPerson] {
        medical.medicalID.contacts.filter { !$0.isBlank }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    if tier != .normal { tierBanner }
                    callBlock
                    positionCard
                    textLocationButton
                    contactsBlock
                    if tier != .critical { medicalCard }
                    batteryCard
                    noSignalCard
                    LinkButton(title: "Make Emergency Mode one tap") { showGuide = true }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            battery.start()
            power.apply(tier: tier)
            position.start(tier: tier)
        }
        .onDisappear { shutDown() }
        .onChange(of: battery.tier) { _, newTier in
            power.apply(tier: newTier)
            position.apply(tier: newTier)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                power.apply(tier: tier)
                power.setKeepAwake(keepAwake)
                position.start(tier: tier)
            default:
                // Leave brightness the way the person had it when Flare isn't on screen.
                power.restore()
                position.stop()
            }
        }
        .onChange(of: keepAwake) { _, value in power.setKeepAwake(value) }
        .sheet(isPresented: $showMessage) { messageSheet }
        .sheet(isPresented: $showGuide) { EmergencyModeGuideView() }
    }

    private func shutDown() {
        position.stop()
        battery.stop()
        power.restore()
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FlareColor.link)
            Text("Emergency Mode")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.50")
                Text(battery.percentText)
                    .font(.flareBody)
            }
            .foregroundStyle(FlareColor.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery \(battery.percentText)")

            Button {
                controller.isActive = false
            } label: {
                Text("Exit")
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private var tierBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tier == .critical ? "exclamationmark.triangle.fill" : "leaf.fill")
                .foregroundStyle(tier == .critical ? FlareColor.failure : FlareColor.ready)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.title)
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
                Text(tier.detail)
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 14)
    }

    // MARK: Call

    @ViewBuilder
    private var callBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Call for help")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)

            if store.databaseState != .ready || store.lookupFailed {
                note("Emergency numbers could not be read. Use your phone's built-in emergency call. Flare will not guess a number.")
            } else if store.selection == nil {
                note("Flare doesn't know your country yet. Choose it on Home, or use your phone's built-in emergency call.")
            } else if store.plan.isEmpty {
                note("This dataset has no verified emergency number for \(store.selection?.title ?? "this area"). Use your phone's built-in emergency call. Flare will not guess one.")
            } else {
                if let title = store.selection?.title {
                    Text("Numbers for \(title)")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                ForEach(store.plan.visibleGroups) { group in
                    if group.dialURL != nil {
                        ServiceCallButton(group: group) {
                            if let url = group.dialURL { openURL(url) }
                        }
                    } else {
                        note("\(group.title): \(group.displayNumber). This number can't be dialed automatically. Dial it by hand.")
                    }
                }
                if !store.plan.overflowGroups.isEmpty {
                    note("\(store.plan.overflowGroups.count) more numbers are on the Numbers tab.")
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.flareSecondary)
            .foregroundStyle(FlareColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 14)
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
                Text("Accuracy about \(Int(max(here.horizontalAccuracy, 1).rounded())) m \u{00B7} updated \(here.timestamp, style: .relative) ago")
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
                if let place = store.selection?.title {
                    Text("Near \(place)")
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
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        position.refreshNow()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.text)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
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

    // MARK: Text my location

    @ViewBuilder
    private var textLocationButton: some View {
        if let here {
            let message = LocationMessage.body(for: here, placeName: store.selection?.title)
            VStack(alignment: .leading, spacing: 8) {
                if MFMessageComposeViewController.canSendText() {
                    Button {
                        showMessage = true
                    } label: {
                        Label(contacts.isEmpty ? "Text my location" : "Text my location to my contacts",
                              systemImage: "message.fill")
                            .font(.flareBodyLarge)
                            .foregroundStyle(FlareColor.text)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    ShareLink(item: message) {
                        Label("Share my location", systemImage: "square.and.arrow.up")
                            .font(.flareBodyLarge)
                            .foregroundStyle(FlareColor.text)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            )
                    }
                }
                Text(contacts.isEmpty
                     ? "Opens a message with your position. You choose who gets it and tap Send. Add emergency contacts in the Medical ID tab to fill this in automatically."
                     : "Opens a message to your emergency contacts with your position. Flare can't send it for you: check it and tap Send.")
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var messageSheet: some View {
        if let here {
            MessageComposer(
                recipients: contacts.compactMap { Dialer.normalized($0.phone) },
                body: LocationMessage.body(for: here, placeName: store.selection?.title),
                onFinish: { showMessage = false })
                .ignoresSafeArea()
        }
    }

    // MARK: Contacts and medical

    @ViewBuilder
    private var contactsBlock: some View {
        if !contacts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Emergency contacts")
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)
                ForEach(contacts.prefix(3)) { contact in
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
    }

    @ViewBuilder
    private var medicalCard: some View {
        let info = medical.medicalID
        let lines: [(String, String)] = [
            ("Blood type", info.bloodType?.rawValue ?? ""),
            ("Allergies", info.allergies),
            ("Conditions", info.conditions),
            ("Medications", info.medications)
        ].filter { !$0.1.isEmpty }

        if !info.fullName.isEmpty || !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Medical ID")
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)
                if !info.fullName.isEmpty {
                    Text(info.fullName)
                        .font(.flareBodyLarge)
                        .foregroundStyle(FlareColor.text)
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
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
                checklistRow(done: tier != .normal,
                             text: "Flare dims the screen and slows GPS as the battery drops.")
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
                bullet("If calls fail, use \u{201C}Text my location\u{201D} above. A text can get through on a weak signal, and may be held and sent when the signal returns.")
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
