import SwiftUI
import UIKit

// Design tokens from the Flare design overview (October 2026).

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum FlareColor {
    // Background: #0A0E24 -> #0E1A38 -> #17405F, top to bottom
    static let navyTop = Color(hex: 0x0A0E24)
    static let navyMid = Color(hex: 0x0E1A38)
    static let navyBottom = Color(hex: 0x17405F)

    static let text = Color.white
    static let secondaryText = Color(hex: 0xD3DCF6)

    // Flare orange: reserved for the action that matters, calling for help.
    static let flareStart = Color(hex: 0xFF8A4C)
    static let flareEnd = Color(hex: 0xFF4D2E)
    static let accent = Color(hex: 0xFF6A3D)
    static let link = Color(hex: 0xFFB066)
    static let onFlare = Color(hex: 0x1A0A06)

    // Card surface: white at 7%, 1 pt border at 12%
    static let cardFill = Color.white.opacity(0.07)
    static let cardBorder = Color.white.opacity(0.12)

    // Category tints (used on a 22% tinted tile)
    static let hospital = Color(hex: 0xFF9A8D)
    static let police = Color(hex: 0x9CC3FF)
    static let fire = Color(hex: 0xFFC070)
    static let pharmacy = Color(hex: 0x6EF0DC)
    static let vet = Color(hex: 0xC9A7FF)

    static let ready = Color(hex: 0x7CF0C8)
    static let offlineDot = Color(hex: 0x4ADE80)
    static let warning = Color(hex: 0xFFC070)
    static let failure = Color(hex: 0xFF9A8D)
}

enum FlareGradient {
    static let background = LinearGradient(
        colors: [FlareColor.navyTop, FlareColor.navyMid, FlareColor.navyBottom],
        startPoint: .top, endPoint: .bottom)

    static let flare = LinearGradient(
        colors: [FlareColor.flareStart, FlareColor.flareEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func buttonGradient(for tint: CallTint) -> LinearGradient {
        switch tint {
        case .allPurpose:
            return flare
        case .ambulance:
            return LinearGradient(colors: [Color(hex: 0xE5484D), Color(hex: 0xC22A33)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .police:
            return LinearGradient(colors: [Color(hex: 0x3B7BF0), Color(hex: 0x2455C8)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .fire:
            return LinearGradient(colors: [Color(hex: 0xFFB347), Color(hex: 0xFF8F1F)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rescue:
            return LinearGradient(colors: [Color(hex: 0x6EF0DC), Color(hex: 0x35C9B3)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Text colour that keeps contrast on each button gradient.
    static func buttonForeground(for tint: CallTint) -> Color {
        switch tint {
        case .allPurpose, .fire, .rescue: return FlareColor.onFlare
        case .ambulance, .police: return .white
        }
    }
}

// MARK: - Archivo

/// Archivo in three weights (Medium 500, Bold 700, ExtraBold 800).
/// Falls back to the system font if the bundled fonts could not be loaded,
/// so text is never missing.
enum ArchivoWeight {
    case medium, bold, extraBold

    var postScriptName: String {
        switch self {
        case .medium: return "Archivo-Medium"
        case .bold: return "Archivo-Bold"
        case .extraBold: return "Archivo-ExtraBold"
        }
    }

    var systemWeight: Font.Weight {
        switch self {
        case .medium: return .medium
        case .bold: return .bold
        case .extraBold: return .heavy
        }
    }
}

extension Font {
    static func archivo(_ weight: ArchivoWeight, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if UIFont(name: weight.postScriptName, size: size) != nil {
            return .custom(weight.postScriptName, size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight.systemWeight)
    }

    /// Display / 56 / 800: the emergency number.
    static var flareDisplay: Font { .archivo(.extraBold, size: 56, relativeTo: .largeTitle) }
    /// Screen title / 28 / 800
    static var flareTitle: Font { .archivo(.extraBold, size: 28, relativeTo: .title) }
    /// Section headings / 20 / 800
    static var flareSection: Font { .archivo(.extraBold, size: 20, relativeTo: .title3) }
    /// Body / 15-17 / 700
    static var flareBody: Font { .archivo(.bold, size: 16, relativeTo: .body) }
    static var flareBodyLarge: Font { .archivo(.bold, size: 17, relativeTo: .body) }
    /// Secondary / 12-14 / 500
    static var flareSecondary: Font { .archivo(.medium, size: 14, relativeTo: .subheadline) }
    static var flareCaption: Font { .archivo(.medium, size: 12, relativeTo: .caption) }
}
