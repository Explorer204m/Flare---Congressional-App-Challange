import SwiftUI

/// Every number for one area of the dataset, for looking up a country that is not
/// the person's current location (for example while planning a trip).
/// Pushed inside the browse picker's navigation stack.
struct AreaNumbersView: View {
    let area: Area
    @EnvironmentObject private var store: EmergencyStore
    @State private var rows: [ContactRow]?
    @State private var loaded = false
    @State private var query = ""

    var body: some View {
        ZStack {
            FlareBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Numbers that apply in \(store.displayTitle(for: area)). This does not change your location.")
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if !loaded {
                        ProgressView().tint(FlareColor.link)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if let rows {
                        if rows.isEmpty {
                            Text("This dataset has no verified numbers for this area yet.")
                                .font(.flareBody)
                                .foregroundStyle(FlareColor.text)
                        } else {
                            FlareSearchField(text: $query, prompt: "Search these numbers")
                            NumbersList(rows: rows, query: query)
                        }
                    } else {
                        Text("The emergency database could not be read.")
                            .font(.flareBody)
                            .foregroundStyle(FlareColor.failure)
                    }

                    NumbersDisclaimer()
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(store.displayTitle(for: area))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            rows = await store.contacts(forAreaID: area.id)
            loaded = true
        }
    }
}
