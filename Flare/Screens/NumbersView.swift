import SwiftUI

/// The Numbers tab: every number that applies where the person is, grouped by what it
/// is for, with search. Another country can be looked up without changing the location.
struct NumbersView: View {
    @EnvironmentObject private var store: EmergencyStore
    @State private var query = ""
    @State private var sheet: NumbersSheet?

    enum NumbersSheet: String, Identifiable {
        case changeLocation, lookUp, dataset
        var id: String { rawValue }
    }

    private var title: String {
        if let selection = store.selection { return selection.title }
        if let place = store.unsupportedPlace { return place }
        return "Choose location"
    }

    private var subtitle: String? {
        if let selection = store.selection { return selection.subtitle }
        if store.unsupportedPlace != nil { return "No verified numbers yet" }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Numbers")
                    .font(.flareTitle)
                    .foregroundStyle(FlareColor.text)
                    .accessibilityAddTraits(.isHeader)

                Button {
                    sheet = .changeLocation
                } label: {
                    LocationPill(title: title, subtitle: subtitle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Location: \(title). Change location")

                content

                lookUpCard
                NumbersDisclaimer()
                LinkButton(title: "About this data") { sheet = .dataset }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $sheet) { current in
            switch current {
            case .changeLocation: AreaPickerView()
            case .lookUp: AreaPickerView(browseOnly: true)
            case .dataset: DatasetInfoView()
            }
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch store.databaseState {
        case .loading:
            ProgressView().tint(FlareColor.link)
                .frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let message):
            stateCard(
                systemImage: "exclamationmark.octagon.fill", tint: FlareColor.failure,
                title: "Emergency data unavailable",
                text: "\(message) Flare will not guess a number. You can also use your phone's built-in emergency call feature.")
        case .ready:
            ready
        }
    }

    @ViewBuilder
    private var ready: some View {
        if store.selection == nil {
            if let place = store.unsupportedPlace {
                stateCard(
                    systemImage: "globe", tint: FlareColor.warning,
                    title: "No verified numbers for \(place)",
                    text: "This dataset has no verified numbers for \(place) yet. Flare will not guess one. You can look up another country below.")
            } else {
                stateCard(
                    systemImage: "location.magnifyingglass", tint: FlareColor.link,
                    title: store.location.isLocating ? "Finding where you are\u{2026}" : "Where are you?",
                    text: "Choose your country or state to see the numbers that apply there, or look up another country below.")
            }
        } else if store.lookupFailed {
            stateCard(
                systemImage: "exclamationmark.octagon.fill", tint: FlareColor.failure,
                title: "Couldn't read the numbers",
                text: "The emergency database could not be read. Flare will not guess a number.")
        } else if store.rows.isEmpty {
            stateCard(
                systemImage: "questionmark.circle.fill", tint: FlareColor.warning,
                title: "No verified numbers here",
                text: "This dataset has no verified numbers for \(title) yet. Flare will not guess one. You can also use your phone's built-in emergency call feature.")
        } else {
            if store.needsConfirmation {
                NoticeCard(
                    systemImage: "exclamationmark.triangle.fill",
                    message: "Flare can't confirm where you are right now (it may need a connection). Showing numbers for \(title). Make sure that is right.") {
                    LinkButton(title: "Check or change location") { sheet = .changeLocation }
                }
            }
            Text("\(store.rows.count) \(store.rows.count == 1 ? "number applies" : "numbers apply") in \(title), including the country or state above it.")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            FlareSearchField(text: $query, prompt: "Search numbers")
            NumbersList(rows: store.rows, query: query)
        }
    }

    private func stateCard(systemImage: String, tint: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
            }
            Text(text)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Look up another country

    private var lookUpCard: some View {
        Button {
            sheet = .lookUp
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FlareColor.police.opacity(0.22))
                    Image(systemName: "globe")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FlareColor.police)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look up another country")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                    Text("Works offline \u{00B7} doesn't change your location")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FlareColor.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .cardSurface(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}
