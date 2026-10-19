import SwiftUI
import UIKit

/// Manual country / state / city selector. Works offline.
struct AreaPickerView: View {
    @EnvironmentObject private var store: EmergencyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var query = ""

    /// When true the picker only browses: choosing an area opens its numbers and does
    /// not change the person's location.
    let browseOnly: Bool
    @State private var browsed: Area?

    init(browseOnly: Bool = false) {
        self.browseOnly = browseOnly
    }

    private var filtered: [Area] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return store.allAreas }
        return store.allAreas.filter { area in
            area.name.localizedCaseInsensitiveContains(text)
                || store.countryName(for: area).localizedCaseInsensitiveContains(text)
                || area.countryCode.caseInsensitiveCompare(text) == .orderedSame
        }
    }

    var body: some View {
        // Filter once per update; the list and the empty message share the result.
        let results = filtered
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if !browseOnly { locationRow }
                        ForEach(results) { area in
                            row(for: area)
                        }
                        if results.isEmpty {
                            Text("No matching country, state or city in this dataset.")
                                .font(.flareSecondary)
                                .foregroundStyle(FlareColor.secondaryText)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(browseOnly ? "Look up numbers" : "Where are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search country, state or city")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.flareBody)
                }
            }
            .navigationDestination(item: $browsed) { area in
                AreaNumbersView(area: area)
            }
        }
    }

    // MARK: Use my location

    @ViewBuilder
    private var locationRow: some View {
        if store.location.isDenied {
            NoticeCard(
                systemImage: "location.slash.fill",
                message: "Location is off. Pick your area below, or turn location on in Settings to have Flare find it for you.") {
                LinkButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } else {
            Button {
                store.useMyLocation()
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Use my location")
                        .font(.flareBodyLarge)
                    Spacer()
                }
                .foregroundStyle(FlareColor.onFlare)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FlareGradient.flare)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Rows

    private func row(for area: Area) -> some View {
        let isSelected = store.selection?.areaID == area.id
        return Button {
            if browseOnly {
                browsed = area
            } else {
                store.select(area)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.name)
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.text)
                        .multilineTextAlignment(.leading)
                    Text(store.pickerSubtitle(for: area))
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                }
                Spacer(minLength: 8)
                if browseOnly {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FlareColor.secondaryText)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(FlareColor.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .cardSurface(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(area.name), \(store.pickerSubtitle(for: area))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
