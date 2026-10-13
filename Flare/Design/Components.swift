import SwiftUI

// MARK: - Background

struct FlareBackground: View {
    var body: some View {
        FlareGradient.background.ignoresSafeArea()
    }
}

// MARK: - Card surface

struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FlareColor.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(FlareColor.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Pills (header)

struct LocationPill: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FlareColor.link)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.flareCaption)
                        .foregroundStyle(FlareColor.secondaryText)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FlareColor.secondaryText)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .cardSurface(cornerRadius: 22)
    }
}

struct StatusPill: View {
    let label: String
    let dot: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(label)
                .font(.flareCaption)
                .foregroundStyle(FlareColor.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .cardSurface(cornerRadius: 22)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.flareSection)
                .foregroundStyle(FlareColor.text)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.flareBody)
                        .foregroundStyle(FlareColor.link)
                        .frame(minHeight: 44)
                }
            }
        }
    }
}

// MARK: - Calling

/// The large circular CALL button, used when one number covers the area.
struct BigCallButton: View {
    let number: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(FlareColor.flareStart.opacity(0.14), lineWidth: 2)
                    .frame(width: 236, height: 236)
                Circle().stroke(FlareColor.flareStart.opacity(0.26), lineWidth: 2)
                    .frame(width: 208, height: 208)
                Circle()
                    .fill(FlareGradient.flare)
                    .frame(width: 176, height: 176)
                    .shadow(color: FlareColor.flareEnd.opacity(0.55), radius: 30, y: 8)
                VStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 42, weight: .bold))
                    Text("CALL")
                        .font(.archivo(.extraBold, size: 24, relativeTo: .title2))
                        .tracking(2)
                }
                .foregroundStyle(FlareColor.onFlare)
            }
            .frame(width: 236, height: 236)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call \(number)")
    }
}

/// One full-width call button for a number that serves particular services.
struct ServiceCallButton: View {
    let group: NumberGroup
    let action: () -> Void

    private var foreground: Color { FlareGradient.buttonForeground(for: group.tint) }

    private var iconName: String {
        switch group.tint {
        case .allPurpose: return "exclamationmark.triangle.fill"
        case .ambulance: return "cross.fill"
        case .police: return "shield.fill"
        case .fire: return "flame.fill"
        case .rescue: return "lifepreserver.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(foreground.opacity(0.18))
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .bold))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.flareBodyLarge)
                        .lineLimit(2)
                    if let subtitle = group.subtitle {
                        Text(subtitle)
                            .font(.flareCaption)
                            .opacity(0.85)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text(group.displayNumber)
                    .font(.archivo(.extraBold, size: 30, relativeTo: .title))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(FlareGradient.buttonGradient(for: group.tint))
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call \(group.displayNumber), \(group.title)")
    }
}

// MARK: - Tiles (Nearby and Tools)

struct FeatureTile: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.22))
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.flareBody)
                    .foregroundStyle(FlareColor.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.flareCaption)
                    .foregroundStyle(FlareColor.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .cardSurface(cornerRadius: 16)
    }
}

// MARK: - Notices

struct NoticeCard<Actions: View>: View {
    let systemImage: String
    let message: String
    var tint: Color = FlareColor.warning
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.top, 2)
                Text(message)
                    .font(.flareSecondary)
                    .foregroundStyle(FlareColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 16)
    }
}

struct LinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.flareBody)
                .foregroundStyle(FlareColor.link)
                .frame(minHeight: 44, alignment: .leading)
        }
    }
}

// MARK: - Tool tile (vertical, three across)

struct ToolTile: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.22))
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            Text(title)
                .font(.flareBody)
                .foregroundStyle(FlareColor.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.flareCaption)
                .foregroundStyle(FlareColor.secondaryText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .cardSurface(cornerRadius: 16)
    }
}

extension View {
    /// Dims a control that is designed but not built yet, and tells VoiceOver.
    func comingSoon() -> some View {
        self
            .opacity(0.6)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Not available yet")
    }
}

// MARK: - Search field

/// Plain search box used inside scrolling screens (the system `.searchable` needs a navigation bar).
struct FlareSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FlareColor.secondaryText)
            TextField("", text: $text,
                      prompt: Text(prompt).foregroundStyle(FlareColor.secondaryText))
                .font(.flareBody)
                .foregroundStyle(FlareColor.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FlareColor.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, text.isEmpty ? 14 : 0)
        .frame(minHeight: 48)
        .cardSurface(cornerRadius: 16)
    }
}
