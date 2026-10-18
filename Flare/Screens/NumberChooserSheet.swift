import SwiftUI

/// Every number the dataset lists for one service (for example the five police numbers of a
/// country), each named by the unit that answers it. Flare can't tell which is the main one,
/// so the person picks the unit they need.
struct NumberChooserSheet: View {
    let slot: ServiceSlot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                FlareBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These numbers are all listed for \(slot.title.lowercased()) here. The data doesn't say which one is the main one, so pick the unit you need.")
                            .font(.flareSecondary)
                            .foregroundStyle(FlareColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(slot.groups) { group in
                            row(group)
                        }

                        Text("Numbers come from the offline database. Unit names are as reported by the country.")
                            .font(.flareCaption)
                            .foregroundStyle(FlareColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("\(slot.title) numbers")
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

    private func row(_ group: NumberGroup) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.displayNumber)
                    .font(.archivo(.extraBold, size: 30, relativeTo: .title))
                    .foregroundStyle(FlareColor.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let label = group.unitLabel {
                    Text(label)
                        .font(.flareSecondary)
                        .foregroundStyle(FlareColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if group.title.caseInsensitiveCompare(slot.title) != .orderedSame {
                    Text("Also reaches: \(group.title)")
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if let url = group.dialURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Call", systemImage: "phone.fill")
                        .font(.flareBodyLarge)
                        .foregroundStyle(FlareColor.onFlare)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 52)
                        .background(Capsule().fill(FlareGradient.flare))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(group.displayNumber)\(group.unitLabel.map { ", \($0)" } ?? "")")
            } else {
                Text("Dial by hand")
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.warning)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 16)
    }
}
