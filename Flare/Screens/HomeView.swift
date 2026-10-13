import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var store: EmergencyStore
    @Environment(\.openURL) private var openURL
    let openMap: () -> Void
    let openNumbers: () -> Void
    @State private var sheet: HomeSheet?

    enum HomeSheet: String, Identifiable {
        case locationPicker, dataset
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
            case .dataset: DatasetInfoView()
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

    private var statusLabel: (text: String, dot: Color) {
        switch store.databaseState {
        case .ready: return ("Offline ready", FlareColor.offlineDot)
        case .loading: return ("Loading", FlareColor.secondaryText)
        case .failed: return ("Data error", FlareColor.failure)
        }
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
                    sheet = .dataset
                } label: {
                    StatusPill(label: statusLabel.text, dot: statusLabel.dot)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Data status: \(statusLabel.text). Show details")
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

// MARK: - Nearby (designed, not built yet)

struct NearbySection: View {
    let openMap: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Nearby", actionTitle: "Open map", action: openMap)
            LazyVGrid(columns: columns, spacing: 12) {
                FeatureTile(systemImage: "cross.case.fill", title: "Hospital",
                            subtitle: "Coming soon", tint: FlareColor.hospital)
                    .comingSoon()
                FeatureTile(systemImage: "shield.fill", title: "Police",
                            subtitle: "Coming soon", tint: FlareColor.police)
                    .comingSoon()
                FeatureTile(systemImage: "flame.fill", title: "Fire station",
                            subtitle: "Coming soon", tint: FlareColor.fire)
                    .comingSoon()
                FeatureTile(systemImage: "pills.fill", title: "Pharmacy",
                            subtitle: "Coming soon", tint: FlareColor.pharmacy)
                    .comingSoon()
            }
        }
    }
}

// MARK: - Tools (designed, not built yet)

struct ToolsSection: View {
    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Tools")
            HStack(spacing: 12) {
                ToolTile(systemImage: "battery.50percent", title: "Battery saver",
                         subtitle: "Coming soon", tint: FlareColor.ready)
                    .comingSoon()
                ToolTile(systemImage: "figure.fall", title: "Fall detection",
                         subtitle: "Coming soon", tint: FlareColor.fire)
                    .comingSoon()
                ToolTile(systemImage: "antenna.radiowaves.left.and.right", title: "SMS / Satellite",
                         subtitle: "Coming soon", tint: FlareColor.police)
                    .comingSoon()
            }
        }
    }
}
