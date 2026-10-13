import Foundation

/// Turns the phone numbers stored in the database into `tel:` / `sms:` URLs.
///
/// Rules (from the database integration notes):
/// - strip presentation separators for dialing only
/// - keep leading zeros, short codes and a leading "+"
/// - never guess: a value with unexpected characters is not dialed automatically
/// - nothing here places a call; the person must tap a button.
enum Dialer {
    private static let separators: Set<Character> = [
        " ", "-", "(", ")", ".", "\u{00A0}", "\u{2011}", "\u{2013}"
    ]

    /// Digits with an optional leading "+", or nil if the value can't be dialed safely.
    static func normalized(_ raw: String) -> String? {
        var output = ""
        for character in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isASCII && character.isWholeNumber {
                output.append(character)
            } else if character == "+" && output.isEmpty {
                output.append(character)
            } else if separators.contains(character) {
                continue
            } else {
                return nil
            }
        }
        let hasDigits = output.contains { $0.isASCII && $0.isWholeNumber }
        return hasDigits ? output : nil
    }

    /// Key used to group identical numbers regardless of formatting.
    static func groupingKey(for raw: String) -> String {
        normalized(raw) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func telURL(for raw: String) -> URL? {
        guard let number = normalized(raw) else { return nil }
        return URL(string: "tel:\(number)")
    }

    static func smsURL(for raw: String) -> URL? {
        guard let number = normalized(raw) else { return nil }
        return URL(string: "sms:\(number)")
    }

    /// Web contacts are only opened when they are plain http(s) links.
    static func webURL(for raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") else { return nil }
        return URL(string: trimmed)
    }
}
