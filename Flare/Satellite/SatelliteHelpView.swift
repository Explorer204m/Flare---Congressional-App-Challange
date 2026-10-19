import SwiftUI

/// Apple's Emergency SOS via satellite.
///
/// Flare can't use the satellite itself and Apple offers no link that opens
/// it directly. What Apple does document is the way in through Messages:
/// text the local emergency number while there is no cell or Wi-Fi coverage,
/// and the iPhone (14 or later) offers "Emergency Services" by satellite.
/// So Flare opens Messages addressed to the area's emergency number, and the
/// iPhone takes it from there.
enum SatelliteSOS {
    /// Countries Apple lists for Emergency SOS via satellite
    /// (support.apple.com/en-us/101573). Apple adds countries over time,
    /// so the screen never says "not available", only "not listed".
    static let countries: Set<String> = [
        "AD", "AT", "AU", "BE", "CA", "CH", "DE", "ES", "FR", "GB", "IE",
        "IS", "IT", "JP", "LU", "MX", "NL", "NO", "NZ", "PT", "US"
    ]
    static let checked = "October 2026"

    static func isListed(_ countryCode: String?) -> Bool {
        guard let countryCode else { return false }
        return countries.contains(countryCode.uppercased())
    }

    /// The numbers to offer for a text: the all-emergencies number first, then the
    /// rest in the order the call screen uses. Only numbers that can be texted safely.
    static func textableGroups(in plan: CallPlan) -> [NumberGroup] {
        let usable = plan.groups.filter { $0.dialURL != nil && Dialer.smsURL(for: $0.displayNumber) != nil }
        let general = usable.filter(\.coversEverything)
        let others = usable.filter { !$0.coversEverything }
        return Array((general + others).prefix(3))
    }
}

// MARK: - Text card (Home sheet and Emergency Mode)

/// "Text emergency services" buttons that hand over to Messages.
struct SatelliteTextCard: View {
    @EnvironmentObject private var store: EmergencyStore
    @Environment(\.openURL) private var openURL

    private var countryCode: String? { store.selection?.countryCode }
    private var placeName: String { store.selection?.subtitle ?? "this area" }
    private var groups: [NumberGroup] { SatelliteSOS.textableGroups(in: store.plan) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(FlareColor.police)
                Text("Text emergency services")
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)
            }

            if store.selection == nil {
                message("Choose your location first, so Flare knows which emergency number to text.")
            } else if !SatelliteSOS.isListed(countryCode) {
                message("Apple doesn't list \(placeName) for Emergency SOS via satellite (checked \(SatelliteSOS.checked)). A text to the emergency number may not reach anyone here, so call instead. Apple adds countries over time: check Settings > Emergency SOS on your iPhone.")
            } else if groups.isEmpty {
                message("Flare has no emergency number it can text for \(placeName). Call one of the numbers on Home instead.")
            } else {
                message("Use this only when a call won't connect. Flare opens Messages to the emergency number. With no cell or Wi-Fi signal, your iPhone shows \u{201C}Emergency Services\u{201D}: tap it and follow the steps to connect to a satellite.")
                ForEach(groups) { group in
                    textButton(for: group, prominent: group.id == groups.first?.id)
                }
                Text("With signal, this goes as a normal text, which many emergency services can't receive. Needs iPhone 14 or later, outdoors with a clear view of the sky.")
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.flareSecondary)
            .foregroundStyle(FlareColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func textButton(for group: NumberGroup, prominent: Bool) -> some View {
        Button {
            if let url = Dialer.smsURL(for: group.displayNumber) { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "message.fill")
                    .font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Text \(group.displayNumber)")
                        .font(.flareBodyLarge)
                    Text(group.title)
                        .font(.flareCaption)
                        .opacity(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(prominent ? FlareColor.onFlare : FlareColor.text)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(FlareGradient.flare) : AnyShapeStyle(FlareColor.cardFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FlareColor.cardBorder, lineWidth: prominent ? 0 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text \(group.displayNumber), \(group.title). Opens Messages")
        .accessibilityHint("With no signal, your iPhone offers to send it by satellite")
    }
}

// MARK: - Sheet from Home

/// The "SMS / Satellite" tool: text emergency services, other ways into
/// Apple's satellite feature, and a way to send your location to contacts.
struct SatelliteHelpView: View {
    /// Closes this sheet and opens Emergency Mode (location SMS to contacts).
    let openEmergencyMode: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SatelliteTextCard()
                        otherWays
                        practice
                        contactsCard
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("SMS / Satellite")
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

    private var otherWays: some View {
        card(title: "Other ways in") {
            step("Call the emergency number first. If the call can't connect, your iPhone may offer \u{201C}Emergency Text via Satellite\u{201D} right away.")
            step("Or open Control Center or Settings, choose Satellite, then Emergency SOS via satellite.")
            step("Once connected, answer the questions by tapping and keep pointing your iPhone where the screen shows. Your iPhone can also tell your emergency contacts.")
            step("Started it by accident? Don't close it. Wait for a reply and tell them you don't need help.")
        }
    }

    private var practice: some View {
        card(title: "Practise before a trip") {
            step("In Settings > Emergency SOS, scroll down and tap Try Demo. It connects to a real satellite but doesn't contact anyone.")
            step("Set up your Medical ID and emergency contacts in the Health app, so they can be shared in an emergency.")
        }
    }

    private var contactsCard: some View {
        card(title: "Tell your contacts where you are") {
            Text("Emergency Mode can text your coordinates to the contacts in your Medical ID, and saves battery while you wait.")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LinkButton(title: "Open Emergency Mode") {
                dismiss()
                openEmergencyMode()
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func step(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}").foregroundStyle(FlareColor.secondaryText)
            Text(text)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
