import SwiftUI

/// What the offline data is, where it came from, and what it can't promise.
struct DatasetInfoView: View {
    @EnvironmentObject private var store: EmergencyStore
    @Environment(\.dismiss) private var dismiss

    private var rootAreaCount: Int {
        store.allAreas.filter { $0.parentID == nil }.count
    }

    private var publishedText: String {
        if let date = store.datasetInfo?.publishedAt {
            return date.formatted(date: .long, time: .omitted)
        }
        return "Unknown"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusCard

                        infoCard(title: "Where the numbers come from",
                                 text: "Published government and official sources, reviewed with AI assistance. Nobody has test-called these numbers, and numbers can change after they were checked. Each number shows its own notes and the date it was last confirmed.")

                        infoCard(title: "What works without a signal",
                                 text: "The numbers are stored on your phone, so you can look them up with no connection. Calling or texting still needs a usable signal. Finding your country or state from your location can need a connection; offline, Flare uses the last place it confirmed, or the one you chose.")

                        infoCard(title: "Sources",
                                 text: "Includes information derived from ITU-T E.129 \u{201C}Important numbers\u{201D} (\u{00A9} ITU), which is based on reports from national authorities, and from official national government pages. Flare is not endorsed by ITU or by any listed organization.")
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("About this data")
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

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.databaseState == .ready ? FlareColor.offlineDot : FlareColor.failure)
                    .frame(width: 10, height: 10)
                Text(store.databaseState == .ready ? "Offline ready" : "Data problem")
                    .font(.flareSection)
                    .foregroundStyle(FlareColor.text)
            }
            if case .failed(let message) = store.databaseState {
                Text(message)
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.secondaryText)
            }
            if let info = store.datasetInfo {
                row("Data version", info.version)
                row("Published", publishedText)
                row("Coverage", "\(rootAreaCount) countries and areas, \(store.allAreas.count) places in total")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func row(_ label: String, _ value: String) -> some View {
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

    private func infoCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.flareBodyLarge)
                .foregroundStyle(FlareColor.text)
            Text(text)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
