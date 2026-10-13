import Foundation

/// Open Location Code ("Plus Code"): a short, free, offline way to say where you are that
/// works as a search term in most map apps. 10 digits, about 14 m x 14 m.
enum PlusCode {
    private static let alphabet = Array("23456789CFGHJMPQRVWX")

    static func encode(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite else { return nil }

        let lat = min(max(latitude, -90), 89.9999)
        var lon = longitude
        while lon < -180 { lon += 360 }
        while lon >= 180 { lon -= 360 }

        // Work in integer steps of 1/8000 degree (the 10-digit resolution).
        var latValue = Int(((lat + 90) * 25_000_000).rounded(.down)) / 3125
        var lonValue = Int(((lon + 180) * 25_000_000).rounded(.down)) / 3125

        var latDigits: [Character] = []
        var lonDigits: [Character] = []
        for _ in 0..<5 {
            latDigits.insert(alphabet[latValue % 20], at: 0)
            lonDigits.insert(alphabet[lonValue % 20], at: 0)
            latValue /= 20
            lonValue /= 20
        }

        var code = ""
        for index in 0..<5 {
            code.append(latDigits[index])
            code.append(lonDigits[index])
            if index == 3 { code.append("+") }
        }
        return code
    }
}
