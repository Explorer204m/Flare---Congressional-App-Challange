import SwiftUI

/// Every active number for the selected area (and the areas above it), with the
/// details the dataset requires us to show: coverage, notes, hours and the
/// date it was last confirmed.
struct NumbersDetailView: View {
    @EnvironmentObject private var store: EmergencyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if let selection = store.selection {
                            Text("Numbers that apply in \(selection.title)")
                                .font(.flareSecondary)
                                .foregroundStyle(FlareColor.secondaryText)
                        }

                        if store.rows.isEmpty {
                            Text("This dataset has no verified numbers for this area yet.")
                                .font(.flareBody)
                                .foregroundStyle(FlareColor.text)
                        }

                        ForEach(ServiceCategory.displayOrder, id: \.self) { category in
                            let items = store.rows.filter { $0.category == category }
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(category.sectionTitle)
                                        .font(.flareSection)
                                        .foregroundStyle(FlareColor.text)
                                    ForEach(items) { row in
                                        ContactCard(row: row)
                                    }
                                }
                            }
                        }

                        Text("These numbers come from public sources that were reviewed with AI assistance. Nobody has test-called them, and numbers can change. Check each note and date.")
                            .font(.flareCaption)
                            .foregroundStyle(FlareColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("All numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.flareBody)
                }
            }
        }
    }
}

private struct ContactCard: View {
    let row: ContactRow
    @Environment(\.openURL) private var openURL

    private var headline: String {
        row.channel == .web ? "Information page" : row.value
    }

    private var availabilityText: String {
        // nil means unknown: never present it as 24/7.
        row.availability ?? "Hours not confirmed"
    }

    private var confirmedText: String {
        "Last confirmed \(DateText.shortDate(fromISO: row.lastConfirmedAt) ?? "date unknown")"
    }

    private var action: (title: String, url: URL)? {
        switch row.channel {
        case .voice:
            guard let url = Dialer.telURL(for: row.value) else { return nil }
            return ("Call \(row.value)", url)
        case .sms:
            guard let url = Dialer.smsURL(for: row.value) else { return nil }
            return ("Text \(row.value)", url)
        case .web:
            guard let url = Dialer.webURL(for: row.value) else { return nil }
            return ("Open page", url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.archivo(.extraBold, size: 26, relativeTo: .title2))
                    .foregroundStyle(FlareColor.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.channel.label)
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }

            Text(row.serviceName.sentenceCased)
                .font(.flareBody)
                .foregroundStyle(FlareColor.text)

            detail("Applies to \(row.coverageName) (\(row.coverageType.label.lowercased()))")
            detail(availabilityText)
            if let notes = row.notes {
                detail(notes)
            }
            detail(confirmedText)

            if let action {
                Button {
                    openURL(action.url)
                } label: {
                    Text(action.title)
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.onFlare)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            Capsule().fill(FlareGradient.flare)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else if row.channel == .voice {
                detail("This number can't be dialed automatically. Dial it by hand.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 16)
        .accessibilityElement(children: .contain)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.flareSecondary)
            .foregroundStyle(FlareColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
