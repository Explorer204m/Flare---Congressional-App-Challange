import SwiftUI

/// The call area of Home. Only this part changes with the country:
/// one big CALL button when a single number covers the area, otherwise one
/// button per number. Every number comes from the offline database.
struct CallArea: View {
    @EnvironmentObject private var store: EmergencyStore
    @Environment(\.openURL) private var openURL

    let onShowNumbers: () -> Void
    let onChooseLocation: () -> Void
    /// Emergency Mode hides the "All numbers and details" link to keep the screen minimal.
    var showsAllNumbersLink = true

    @State private var showOverflow = false

    private let builtInNote = "In an emergency you can also use your phone's built-in emergency call feature."

    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch store.databaseState {
        case .loading:
            ProgressView()
                .tint(FlareColor.link)
                .frame(maxWidth: .infinity, minHeight: 220)
        case .failed(let message):
            messageCard(
                systemImage: "exclamationmark.octagon.fill",
                tint: FlareColor.failure,
                title: "Emergency data unavailable",
                message: "\(message) Flare will not guess a number. \(builtInNote)")
        case .ready:
            readyContent
        }
    }

    // MARK: Ready

    @ViewBuilder
    private var readyContent: some View {
        if store.selection == nil {
            noAreaCard
        } else if store.lookupFailed {
            messageCard(
                systemImage: "exclamationmark.octagon.fill",
                tint: FlareColor.failure,
                title: "Couldn't read the numbers",
                message: "The emergency database could not be read. Flare will not guess a number. \(builtInNote)")
        } else if store.plan.isEmpty {
            emptyPlanCard
        } else if store.plan.isSingleNumber, let group = store.plan.groups.first {
            singleNumber(group)
            footer
        } else {
            multipleNumbers
            footer
        }
    }

    private func dial(_ group: NumberGroup) {
        if let url = group.dialURL { openURL(url) }
    }

    // MARK: One number

    private func singleNumber(_ group: NumberGroup) -> some View {
        VStack(spacing: 6) {
            Text(group.coversEverything ? "One number for everything here" : "Emergency number here")
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
            Text(group.displayNumber)
                .font(.flareDisplay)
                .foregroundStyle(FlareColor.text)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(group.subtitle ?? group.title)
                .font(.flareBody)
                .foregroundStyle(FlareColor.secondaryText)
                .multilineTextAlignment(.center)
            if group.dialURL != nil {
                BigCallButton(number: group.displayNumber) { dial(group) }
                    .padding(.top, 6)
            } else {
                Text("This number can't be dialed automatically. Dial it by hand.")
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.warning)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: Several numbers

    private var multipleCaption: String {
        let allCoverEverything = store.plan.groups.allSatisfy { $0.coversEverything }
        return allCoverEverything
            ? "Any of these numbers reaches emergency services here. Tap to call."
            : "Each service has its own number here. Tap to call."
    }

    private var multipleNumbers: some View {
        VStack(spacing: 12) {
            Text(multipleCaption)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            ForEach(store.plan.visibleGroups) { group in
                numberButton(group)
            }

            if !store.plan.overflowGroups.isEmpty {
                if showOverflow {
                    ForEach(store.plan.overflowGroups) { group in
                        numberButton(group)
                    }
                }
                Button {
                    withAnimation { showOverflow.toggle() }
                } label: {
                    Text(showOverflow
                         ? "Show fewer numbers"
                         : "Show \(store.plan.overflowGroups.count) more numbers")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.link)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder
    private func numberButton(_ group: NumberGroup) -> some View {
        if group.dialURL != nil {
            ServiceCallButton(group: group) { dial(group) }
        } else {
            // Unexpected characters in the stored number: show it, don't dial it.
            VStack(alignment: .leading, spacing: 4) {
                Text("\(group.title): \(group.displayNumber)")
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
                Text("This number can't be dialed automatically. Dial it by hand.")
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.warning)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 16)
        }
    }

    // MARK: Footer

    private var missingNote: String? {
        guard !store.plan.missingCore.isEmpty else { return nil }
        let names = store.plan.missingCore.map { $0.sectionTitle }.joined(separator: ", ")
        return "No verified number in this dataset for: \(names)."
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 4) {
            if let missingNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(FlareColor.warning)
                    Text(missingNote)
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            if showsAllNumbersLink {
                LinkButton(title: "All numbers and details", action: onShowNumbers)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Empty and error states

    private var areaTitle: String { store.selection?.title ?? "this area" }

    private var emptyPlanCard: some View {
        VStack(spacing: 12) {
            messageCard(
                systemImage: "questionmark.circle.fill",
                tint: FlareColor.warning,
                title: "No verified emergency number",
                message: "This dataset has no verified emergency number for \(areaTitle) yet. Flare will not guess one. \(builtInNote)")
            if !store.rows.isEmpty {
                LinkButton(title: "Other numbers for this area", action: onShowNumbers)
            }
            LinkButton(title: "Choose a different location", action: onChooseLocation)
        }
    }

    private var noAreaCard: some View {
        VStack(spacing: 14) {
            if let place = store.unsupportedPlace {
                messageCard(
                    systemImage: "globe",
                    tint: FlareColor.warning,
                    title: "No verified numbers for \(place)",
                    message: "This dataset has no verified emergency numbers for \(place) yet. Flare will not guess one. \(builtInNote)")
            } else if store.location.isLocating {
                VStack(spacing: 12) {
                    ProgressView().tint(FlareColor.link)
                    Text("Finding where you are\u{2026}")
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                messageCard(
                    systemImage: "location.magnifyingglass",
                    tint: FlareColor.link,
                    title: "Where are you?",
                    message: "Choose your country or state to see its emergency numbers. \(builtInNote)")
            }
            Button(action: onChooseLocation) {
                Text("Choose location")
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.onFlare)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(FlareGradient.flare)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func messageCard(systemImage: String, tint: Color, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.flareBodyLarge)
                    .foregroundStyle(FlareColor.text)
            }
            Text(message)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
