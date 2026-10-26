import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var store: EmergencyStore
    @Environment(\.openURL) private var openURL
    let openMap: () -> Void
    let openNumbers: () -> Void
    @State private var sheet: HomeSheet?

    enum HomeSheet: String, Identifiable {
        case locationPicker, settings
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                notices
                CallArea(
                    onShowNumbers: openNumbers,
                    onChooseLocation: { sheet = .locationPicker })
                AreaAlertBanner()
                NearbySection(openMap: openMap)
                ToolsSection()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $sheet) { current in
            switch current {
            case .locationPicker: AreaPickerView()
            case .settings: SettingsView()
            }
        }
    }

    // MARK: Header

    private var headerTitle: String {
        if let selection = store.selection { return selection.title }
        if let place = store.unsupportedPlace { return place }
        return "Choose location"
    }

    private var headerSubtitle: String? {
        if let selection = store.selection { return selection.subtitle }
        if store.unsupportedPlace != nil { return "No verified numbers yet" }
        return nil
    }

    private var hasDataProblem: Bool {
        if case .failed = store.databaseState { return true }
        return false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    sheet = .locationPicker
                } label: {
                    LocationPill(title: headerTitle, subtitle: headerSubtitle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Location: \(headerTitle). Change location")

                Spacer(minLength: 6)

                Button {
                    sheet = .settings
                } label: {
                    SettingsPill(dataProblem: hasDataProblem)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasDataProblem ? "Settings. The emergency data has a problem" : "Settings")
            }
            if let selection = store.selection, isStale(selection) {
                Text("Last known location \u{00B7} confirmed \(selection.resolvedAt, style: .relative) ago")
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
                    .padding(.leading, 4)
            }
        }
    }

    /// A location-based area that hasn't been re-confirmed for a while (usually offline).
    private func isStale(_ selection: AreaSelection) -> Bool {
        selection.source == .location && Date().timeIntervalSince(selection.resolvedAt) > 30 * 60
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        if store.databaseState == .ready {
            VStack(spacing: 10) {
                if store.location.isDenied && store.selection?.source != .manual {
                    NoticeCard(
                        systemImage: "location.slash.fill",
                        message: "Location is off, so Flare can't tell where you are. Choose your country or state, or turn location on in Settings.") {
                        HStack(spacing: 20) {
                            LinkButton(title: "Choose location") { sheet = .locationPicker }
                            LinkButton(title: "Open Settings") { openSettings() }
                        }
                    }
                }
                if store.needsConfirmation {
                    NoticeCard(
                        systemImage: "exclamationmark.triangle.fill",
                        message: confirmationMessage) {
                        LinkButton(title: "Check or change location") { sheet = .locationPicker }
                    }
                }
            }
        }
    }

    private var confirmationMessage: String {
        if let selection = store.selection {
            return "Flare can't confirm where you are right now (it may need a connection). Showing numbers for \(selection.title). Make sure that is right."
        }
        return "Flare can't confirm where you are right now (it may need a connection). Choose your country or state to see its numbers."
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

// MARK: - Nearby

struct NearbySection: View {
    @EnvironmentObject private var nearby: NearbyStore
    let openMap: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private func subtitle(for kind: NearbyKind) -> String {
        if let meters = nearby.nearestDistance(for: kind) {
            return "\(Geo.distanceText(meters)) away"
        }
        return "Find nearby"
    }

    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Nearby", actionTitle: "Open map", action: openMap)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(NearbyKind.peopleKinds) { kind in
                    Button {
                        nearby.selectedScope = .kind(kind)
                        openMap()
                    } label: {
                        FeatureTile(systemImage: kind.systemImage, title: kind.title,
                                    subtitle: subtitle(for: kind), tint: kind.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.title), \(subtitle(for: kind)). Opens the Nearby map")
                }
            }
        }
    }
}

// MARK: - Tools

struct ToolsSection: View {
    @EnvironmentObject private var emergency: EmergencyModeController
    @EnvironmentObject private var store: EmergencyStore
    @ObservedObject private var fall = FallDetectionController.shared
    @State private var showFall = false
    @State private var showSatellite = false

    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Tools")
            HStack(spacing: 12) {
                Button {
                    emergency.isActive = true
                } label: {
                    ToolTile(systemImage: "bolt.circle.fill", title: "Emergency Mode",
                             subtitle: "Saves battery", tint: FlareColor.ready)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Emergency Mode. Saves battery, shows your coordinates and numbers")

                Button {
                    showFall = true
                } label: {
                    ToolTile(systemImage: "figure.fall", title: "Fall detection",
                             subtitle: fall.isEnabled ? "On" : "Off",
                             tint: fall.isEnabled ? FlareColor.ready : FlareColor.fire)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fall detection. Currently \(fall.isEnabled ? "on" : "off")")
                Button {
                    showSatellite = true
                } label: {
                    ToolTile(systemImage: "antenna.radiowaves.left.and.right", title: "SMS / Satellite",
                             subtitle: "Text for help", tint: FlareColor.police)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("SMS and satellite. Text emergency services, by satellite where your iPhone offers it")
            }
        }
        .sheet(isPresented: $showFall) { FallDetectionView() }
        .sheet(isPresented: $showSatellite) {
            SatelliteHelpView(openEmergencyMode: {
                // Let the sheet close before Emergency Mode covers the screen.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    emergency.isActive = true
                }
            })
            .environmentObject(store)
        }
    }
}
