import SwiftUI

/// Honest placeholder for screens that are designed but not built yet.
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(FlareColor.cardFill).frame(width: 96, height: 96)
                Circle().stroke(FlareColor.cardBorder, lineWidth: 1).frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(FlareColor.link)
            }
            Text(title)
                .font(.flareTitle)
                .foregroundStyle(FlareColor.text)
            Text("Coming soon")
                .font(.flareBody)
                .foregroundStyle(FlareColor.link)
            Text(message)
                .font(.flareSecondary)
                .foregroundStyle(FlareColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
