import SwiftUI
import UIKit
import MessageUI
import CoreLocation

/// Emergency Mode: a pure-black, low-power screen with only what matters: the number to call,
/// a way to send your location, and your Medical ID. Everything else (coordinates, battery
/// guard, no-signal help) is one tap away under the location line.
///
/// It saves battery by itself (dimmer screen, one GPS fix every few minutes, shorter
/// screen-on use) but, like any iPhone app, cannot pause other apps or change system settings.
struct EmergencyModeView: View {
    @EnvironmentObject private var store: EmergencyStore
    @EnvironmentObject private var medical: MedicalIDStore
    @EnvironmentObject private var controller: EmergencyModeController
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var battery = BatteryMonitor()
    @StateObject private var position = EmergencyPositionService()
    @StateObject private var power = ScreenPowerSession()

    @State private var keepAwake = false
    @State private var sheet: EmergencySheet?
    @State private var preparingMessage = false

    enum EmergencySheet: String, Identifiable {
        case message, medical, details, chooseLocation, numbers, alerts
        var id: String { rawValue }
    }

    private var tier: PowerTier { battery.tier }

    /// Best position we have: the latest GPS fix here, else the last fix Home used.
    private var here: CLLocation? { position.location ?? store.location.latestFix }

    private var contacts: [EmergencyContactPerson] {
        medical.medicalID.contacts.filter { !$0.isBlank }
    }

    private var accent: Color { tier == .critical ? FlareColor.failure : FlareColor.link }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        topBar
                        AreaAlertPill { sheet = .alerts }
                        CallArea(
                            onShowNumbers: { sheet = .numbers },
                            onChooseLocation: { sheet = .chooseLocation },
                            showsAllNumbersLink: false)
                        VStack(spacing: 14) {
                            locationButton
                            EmergencyPillButton(title: "Medical ID", systemImage: "person") {
                                sheet = .medical
                            }
                        }
                        footer
                        Spacer(minLength: 24)
                        EmergencyPillButton(title: "Turn off battery saver", systemImage: nil) {
                            controller.isActive = false
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .fallAlertOverlay()
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
        .sheet(item: $sheet) { current in
            switch current {
            case .message:
                messageSheet
            case .medical:
                EmergencyMedicalView(contacts: contacts)
                    .environmentObject(medical)
            case .details:
                EmergencyDetailsView(
                    battery: battery, position: position,
                    keepAwake: $keepAwake, here: here,
                    placeName: store.selection?.title)
                    .environmentObject(store)
            case .chooseLocation:
                AreaPickerView().environmentObject(store)
            case .alerts:
                AreaAlertsView()
            case .numbers:
                NavigationStack {
                    ZStack {
                        FlareBackground()
                        NumbersView()
                    }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { sheet = nil }.font(.flareBody)
                            }
                        }
                }
                .environmentObject(store)
            }
        }
    }

    private func shutDown() {
        position.stop()
        battery.stop()
        power.restore()
    }

    // MARK: Top bar

    private var batterySymbol: String {
        guard let level = battery.level else { return "battery.50percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch level {
        case 0.875...: return "battery.100percent"
        case 0.625...: return "battery.75percent"
        case 0.375...: return "battery.50percent"
        case 0.125...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 22, weight: .regular))
                Text(battery.percentText)
                    .font(.archivo(.extraBold, size: 26, relativeTo: .title2))
            }
            .foregroundStyle(accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery \(battery.percentText)")

            Spacer(minLength: 8)

            Text(tier == .critical ? "Critical battery" : "Battery saver on")
                .font(.archivo(.bold, size: 17, relativeTo: .body))
                .foregroundStyle(accent)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .overlay(Capsule().stroke(accent, lineWidth: 2))
        }
    }

    // MARK: Send location

    private var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    @ViewBuilder
    private var locationButton: some View {
        if let here {
            if canSendText {
                EmergencyPillButton(
                    title: preparingMessage ? "Getting your position\u{2026}" : "Send my location by SMS",
                    systemImage: preparingMessage ? nil : "bubble.left",
                    action: sendLocation)
                    .disabled(preparingMessage)
            } else {
                // No Messages here (for example the simulator): offer the share sheet instead.
                ShareLink(item: LocationMessage.body(for: here, placeName: store.selection?.title)) {
                    EmergencyPillLabel(title: "Share my location", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        } else {
            EmergencyPillButton(
                title: position.isDenied ? "Location is off" : "Waiting for GPS\u{2026}",
                systemImage: "bubble.left",
                action: {})
                .disabled(true)
                .opacity(0.5)
        }
    }

    private func sendLocation() {
        guard let here else { return }
        // A position older than 2 minutes: ask for a fresh one first, but never wait long.
        if Date().timeIntervalSince(here.timestamp) > 120 {
            position.refreshNow()
            preparingMessage = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                preparingMessage = false
                sheet = .message
            }
        } else {
            sheet = .message
        }
    }

    @ViewBuilder
    private var messageSheet: some View {
        if let here {
            MessageComposer(
                recipients: contacts.compactMap { Dialer.normalized($0.phone) },
                body: LocationMessage.body(for: here, placeName: store.selection?.title),
                onFinish: { sheet = nil })
                .ignoresSafeArea()
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        Button {
            sheet = .details
        } label: {
            VStack(spacing: 4) {
                if let here {
                    Group {
                        if let place = store.selection?.title {
                            Text("Last location: \(place), saved \(here.timestamp, style: .relative) ago")
                        } else {
                            Text("Last location: \(LocationMessage.coordinateText(here)), saved \(here.timestamp, style: .relative) ago")
                        }
                    }
                } else if position.isDenied {
                    Text("Location is off for Flare. Turn it on in Settings.")
                } else {
                    Text("Finding your position\u{2026}")
                }
                Text("Screen dimmed \u{00B7} location checked every \(Int(tier.locationInterval / 60)) min")
                Text("Coordinates, battery and no-signal help \u{203A}")
                    .foregroundStyle(accent)
                    .padding(.top, 2)
            }
            .font(.flareSecondary)
            .foregroundStyle(FlareColor.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows coordinates, battery details and help for no signal")
    }
}

// MARK: - Pill buttons (dark, outlined, from the design)

struct EmergencyPillLabel: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(FlareColor.link)
            }
            Text(title)
                .font(.archivo(.extraBold, size: 21, relativeTo: .title3))
                .foregroundStyle(FlareColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Capsule().fill(Color(hex: 0x0B0D12)))
        .overlay(Capsule().stroke(Color(hex: 0x2B3350), lineWidth: 2))
        .contentShape(Capsule())
    }
}

struct EmergencyPillButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EmergencyPillLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}
