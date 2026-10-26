import SwiftUI
import UIKit

/// The pill on Home that opens Settings. Turns red-tinted when the offline data has a problem.
struct SettingsPill: View {
    let dataProblem: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FlareColor.link)
            Text("Settings")
                .font(.flareCaption)
                .foregroundStyle(FlareColor.text)
                .lineLimit(1)
            if dataProblem {
                Circle().fill(FlareColor.failure).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .cardSurface(cornerRadius: 22)
    }
}

/// Everything a person can change, in one place, plus About this data.
struct SettingsView: View {
    @EnvironmentObject private var store: EmergencyStore
    @EnvironmentObject private var nearby: NearbyStore
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var protection = BackgroundProtection.shared
    @ObservedObject private var alerts = AreaAlertStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var sheet: SettingsSheet?
    @State private var confirmClear = false

    enum SettingsSheet: String, Identifiable {
        case location, data, fall, alerts
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        locationGroup
                        alertsGroup
                        safetyGroup
                        nearbyGroup
                        permissionsGroup
                        privacyGroup
                        aboutGroup
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.flareBody)
                }
            }
            .sheet(item: $sheet) { current in
                switch current {
                case .location: AreaPickerView()
                case .data: DatasetInfoView()
                case .fall: FallDetectionView()
                case .alerts: AreaAlertsView()
                }
            }
            .confirmationDialog("Delete the places saved on this phone?",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete saved places", role: .destructive) { nearby.clearSavedPlaces() }
            } message: {
                Text("Nearby and the compass can't show them without a connection until Flare searches again.")
            }
            .onAppear { protection.refreshNotificationStatus() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Location

    private var locationGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Location")
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.selection?.title ?? store.unsupportedPlace ?? "Not set")
                        .font(.flareBodyLarge)
                        .foregroundStyle(FlareColor.text)
                    Text(locationDetail)
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                HStack(spacing: 20) {
                    LinkButton(title: "Choose country or state") { sheet = .location }
                    if store.selection?.source == .manual {
                        LinkButton(title: "Use my location") { store.useMyLocation() }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private var locationDetail: String {
        guard let selection = store.selection else {
            if store.unsupportedPlace != nil { return "No verified numbers for this place yet" }
            return "Choose your country or state to see its numbers"
        }
        return selection.source == .manual ? "Chosen by you" : "From your phone's location"
    }

    // MARK: Alerts

    private var alertsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Area alerts")
            VStack(alignment: .leading, spacing: 16) {
                toggleRow(
                    "US weather warnings",
                    detail: "From the US National Weather Service, for US locations. To find warnings for where you are, Flare sends your position, rounded to about 100 m, to api.weather.gov. Turn this off and nothing is sent.",
                    isOn: $settings.weatherAlerts)
                Divider().overlay(FlareColor.cardBorder)
                toggleRow(
                    "Major disaster alerts",
                    detail: "Earthquakes, cyclones, floods and volcanoes worldwide, from GDACS. Flare downloads the public list and picks nearby events on your phone, so your location is never sent.",
                    isOn: $settings.disasterAlerts)
                Divider().overlay(FlareColor.cardBorder)
                toggleRow(
                    "Notify me about severe alerts",
                    detail: "A notification for severe and extreme alerts when Flare isn't open. Needs notifications allowed for Flare in iPhone Settings.",
                    isOn: $settings.alertNotifications)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            navRow("View current alerts", detail: alertsDetail, systemImage: "exclamationmark.triangle") {
                sheet = .alerts
            }
        }
    }

    private var alertsDetail: String? {
        if !settings.weatherAlerts && !settings.disasterAlerts { return "Both sources are turned off" }
        guard let checked = alerts.checkedAt else { return "Not checked yet" }
        return "Checked \(checked.formatted(.relative(presentation: .named)))"
    }

    // MARK: Safety

    private var safetyGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Safety tools")
            FallToggleCard()
            navRow("Fall detection options", detail: "Sensitivity, practice alert and limits",
                   systemImage: "figure.fall") { sheet = .fall }
            BackgroundProtectionCard()
        }
    }

    // MARK: Nearby

    private var nearbyGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Nearby places")
            VStack(alignment: .leading, spacing: 14) {
                toggleRow(
                    "Keep nearby places up to date",
                    detail: "While Flare is open it searches Apple Maps again as you move, so the places saved for offline use stay fresh. Your approximate location goes to Apple Maps. Off: Flare only searches when you open Nearby or tap Search again.",
                    isOn: $settings.nearbyAutoUpdate)
                Divider().overlay(FlareColor.cardBorder)
                VStack(alignment: .leading, spacing: 8) {
                    Text(nearby.savedCount == 0
                         ? "No places saved on this phone"
                         : "\(nearby.savedCount) places saved on this phone")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                    Text("These let Nearby and the compass work without a connection.")
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                    if nearby.savedCount > 0 {
                        LinkButton(title: "Delete saved places") { confirmClear = true }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: Permissions

    private var permissionsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Permissions")
            VStack(alignment: .leading, spacing: 12) {
                permissionLine("Location", status: locationStatus)
                permissionLine("Notifications", status: notificationStatus)
                LinkButton(title: "Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private var locationStatus: (text: String, ok: Bool?) {
        if store.location.isDenied { return ("Off", false) }
        if store.location.isAuthorized { return (protection.hasAlways ? "On (Always)" : "On (While Using)", true) }
        return ("Not asked yet", nil)
    }

    private var notificationStatus: (text: String, ok: Bool?) {
        switch protection.notificationsAllowed {
        case .some(true): return ("On", true)
        case .some(false): return ("Off", false)
        case .none: return ("Not asked yet", nil)
        }
    }

    private func permissionLine(_ title: String, status: (text: String, ok: Bool?)) -> some View {
        HStack {
            Text(title)
                .font(.flareBody)
                .foregroundStyle(FlareColor.text)
            Spacer(minLength: 12)
            Text(status.text)
                .font(.flareSecondary)
                .foregroundStyle(status.ok == false ? FlareColor.warning : FlareColor.secondaryText)
        }
    }

    // MARK: Privacy

    private var privacyGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Privacy")
            VStack(alignment: .leading, spacing: 10) {
                Text("What leaves your phone")
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
                bullet("Emergency numbers are stored on your phone. Looking them up sends nothing.")
                bullet("Working out your country or state, and searching for nearby places, use Apple's services, so your approximate location goes to Apple.")
                bullet(settings.weatherAlerts
                       ? "US weather warnings send your position, rounded to about 100 m, to the US National Weather Service."
                       : "US weather warnings are off, so nothing is sent to the National Weather Service.")
                bullet("Major disaster alerts download a public list. No location is sent.")
                bullet("Calls and texts only happen when you tap and confirm them. Flare has no account and no server of its own.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: About

    private var aboutGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About")
            navRow("About this data", detail: dataDetail, systemImage: "externaldrive.fill",
                   dot: store.databaseState == .ready ? FlareColor.offlineDot : FlareColor.failure) {
                sheet = .data
            }
            VStack(alignment: .leading, spacing: 10) {
                infoRow("App version", appVersion)
                if let info = store.datasetInfo { infoRow("Data version", info.version) }
                infoRow("Typeface", "Archivo, SIL Open Font License")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private var dataDetail: String {
        switch store.databaseState {
        case .ready: return "Offline ready"
        case .loading: return "Loading"
        case .failed: return "Data problem"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: Pieces

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
            }
            .tint(FlareColor.accent)
            Text(detail)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func navRow(_ title: String, detail: String? = nil, systemImage: String,
                        dot: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(FlareColor.link)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                    if let detail {
                        HStack(spacing: 6) {
                            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                            Text(detail)
                                .font(.flareCaption)
                                .foregroundStyle(FlareColor.secondaryText)
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FlareColor.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.flareBody)
                .foregroundStyle(FlareColor.text)
                .multilineTextAlignment(.trailing)
        }
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
