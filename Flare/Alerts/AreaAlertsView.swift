import SwiftUI

extension AlertSeverity {
    var tint: Color {
        switch self {
        case .extreme: return FlareColor.failure
        case .severe: return FlareColor.flareStart
        case .moderate: return FlareColor.warning
        case .minor, .unknown: return FlareColor.police
        }
    }
}

/// Home: the most serious current alert, or a quiet "no alerts" line. Opens the full list.
struct AreaAlertBanner: View {
    @ObservedObject private var alerts = AreaAlertStore.shared
    @State private var showList = false

    var body: some View {
        Button {
            showList = true
        } label: {
            if let top = alerts.alerts.first {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(top.severity.tint)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(top.event)
                            .font(.flareBodyLarge)
                            .foregroundStyle(FlareColor.text)
                            .multilineTextAlignment(.leading)
                        Text(subtitle(for: top))
                            .font(.flareCaption)
                            .foregroundStyle(FlareColor.secondaryText)
                            .multilineTextAlignment(.leading)
                        if alerts.alerts.count > 1 {
                            Text("+\(alerts.alerts.count - 1) more")
                                .font(.flareCaption)
                                .foregroundStyle(FlareColor.link)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FlareColor.secondaryText)
                        .padding(.top, 4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(top.severity.tint.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(top.severity.tint.opacity(0.7), lineWidth: 1.5))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(FlareColor.ready)
                    Text(quietText)
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FlareColor.secondaryText)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .cardSurface(cornerRadius: 16)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showList) { AreaAlertsView() }
        .accessibilityHint("Shows area alerts and Background protection")
    }

    private var quietText: String {
        guard let checked = alerts.checkedAt else { return "Area alerts: not checked yet" }
        let ago = checked.formatted(.relative(presentation: .named))
        return "No area alerts \u{00B7} checked \(ago)"
    }

    private func subtitle(for alert: AreaAlert) -> String {
        var parts = [alert.sender]
        if let expires = alert.expires {
            parts.append("until \(expires.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// Emergency Mode: one compact line, only when there is an alert.
struct AreaAlertPill: View {
    @ObservedObject private var alerts = AreaAlertStore.shared
    let action: () -> Void

    var body: some View {
        if let top = alerts.alerts.first {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(top.severity.tint)
                    Text(alerts.alerts.count > 1 ? "\(top.event) +\(alerts.alerts.count - 1)" : top.event)
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FlareColor.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().stroke(top.severity.tint, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Area alert: \(top.event)")
        }
    }
}

/// Every current alert, as issued, plus how they are checked and the Background protection switch.
struct AreaAlertsView: View {
    @ObservedObject private var store = AreaAlertStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        status
                        freshness
                        if store.alerts.isEmpty {
                            NoticeCard(systemImage: "checkmark.shield",
                                       message: "No alerts for your area right now from the sources Flare checks.",
                                       tint: FlareColor.ready) { EmptyView() }
                        } else {
                            ForEach(store.alerts) { alert in
                                AlertCard(alert: alert)
                            }
                        }
                        coverage
                        BackgroundProtectionCard()
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Area alerts")
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

    private var status: some View {
        HStack(spacing: 10) {
            if store.isChecking {
                ProgressView().tint(FlareColor.link)
                Text("Checking\u{2026}")
            } else if let checked = store.checkedAt {
                Circle().fill(store.checkFailed ? FlareColor.warning : FlareColor.offlineDot)
                    .frame(width: 8, height: 8)
                Text(store.checkFailed
                     ? "Couldn't check just now. Last checked \(checked.formatted(.relative(presentation: .named)))."
                     : "Checked \(checked.formatted(.relative(presentation: .named)))")
            } else {
                Text("Not checked yet. Flare needs your location and a connection.")
            }
            Spacer()
            Button("Check now") { Task { await store.checkNow() } }
                .font(.flareBody)
                .foregroundStyle(FlareColor.link)
                .disabled(store.isChecking)
        }
        .font(.flareSecondary)
        .foregroundStyle(FlareColor.secondaryText)
    }

    /// When each source last answered, so one working source can't make the other look current.
    private var freshness: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.coversWeather {
                Text("Weather warnings (NWS): \(updatedText(store.weatherCheckedAt))")
            }
            Text("Major disasters (GDACS): \(updatedText(store.gdacsCheckedAt))")
            if store.gdacsMayBeStale {
                Text("The disaster list hasn't been updated for a while. GDACS events have no end time, so some shown here may already be over.")
                    .foregroundStyle(FlareColor.warning)
            }
        }
        .font(.flareCaption)
        .foregroundStyle(FlareColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func updatedText(_ date: Date?) -> String {
        guard let date else { return "not updated yet" }
        return "updated \(date.formatted(.relative(presentation: .named)))"
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where these come from")
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            Text(store.coversWeather
                 ? "Weather and flood warnings: US National Weather Service. Flare sends your position, rounded to about 100 m, to look them up."
                 : "Weather and flood warnings are only available in the US for now, so Flare shows major disasters only here.")
            Text("Major disasters worldwide (earthquakes, cyclones, floods, volcanoes): GDACS, the Global Disaster Alert and Coordination System. Only orange and red alerts near you are shown, and no location is sent.")
            Text("Checked every 5 minutes, or every 15 minutes in Emergency Mode to save battery. The worldwide disaster list is downloaded every 30 minutes, or sooner if you move far. Alert text is shown exactly as issued.")
            Text("These are extra. Your phone's own government alerts are the reliable channel: keep Emergency Alerts on in Settings \u{203A} Notifications.")
                .foregroundStyle(FlareColor.warning)
        }
        .font(.flareSecondary)
        .foregroundStyle(FlareColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct AlertCard: View {
    let alert: AreaAlert
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(alert.severity.tint)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.event)
                        .font(.flareBodyLarge)
                        .foregroundStyle(FlareColor.text)
                    Text("\(alert.severity.label) \u{00B7} \(alert.sender)")
                        .font(.flareCaption)
                        .foregroundStyle(alert.severity.tint)
                }
            }
            if let headline = alert.headline {
                Text(headline)
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.text)
            }
            if let area = alert.area {
                Text(area)
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
                    .lineLimit(expanded ? nil : 2)
            }
            timing
            if let instruction = alert.instruction {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What to do")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                    Text(instruction)
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.text)
                        .lineLimit(expanded ? nil : 4)
                }
            }
            if expanded, let details = alert.details {
                Text(details)
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.secondaryText)
            }
            HStack(spacing: 20) {
                if alert.details != nil || alert.instruction != nil {
                    LinkButton(title: expanded ? "Show less" : "Full text") { expanded.toggle() }
                }
                if let link = alert.link {
                    Link("Report", destination: link)
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.link)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(alert.severity.tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(alert.severity.tint.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder
    private var timing: some View {
        let parts = [
            alert.effective.map { "From \($0.formatted(date: .abbreviated, time: .shortened))" },
            alert.expires.map { "until \($0.formatted(date: .abbreviated, time: .shortened))" }
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " "))
                .font(.flareCaption)
                .foregroundStyle(FlareColor.secondaryText)
        }
    }
}
