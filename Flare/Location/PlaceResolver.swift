import Foundation
import CoreLocation

/// What reverse geocoding told us about a position.
struct ResolvedPlace: Equatable {
    let locality: String?
    let adminArea: String?
    let countryCode: String
    let countryName: String?

    /// "Atlanta, Georgia", or whichever parts are known.
    func displayTitle(fallback: String) -> String {
        var parts: [String] = []
        for part in [locality, adminAreaDisplayName] {
            if let part, !part.isEmpty, !parts.contains(part) { parts.append(part) }
        }
        return parts.isEmpty ? fallback : parts.joined(separator: ", ")
    }

    private var adminAreaDisplayName: String? {
        guard let adminArea else { return nil }
        if countryCode.uppercased() == "US", let name = USStates.names[adminArea.uppercased()] {
            return name
        }
        return adminArea
    }
}

enum PlaceResolverError: Error {
    case noCountry
}

enum PlaceResolver {
    /// Reverse geocodes a position. Needs a network connection; callers must
    /// handle failure (offline use falls back to the last known area).
    static func reverseGeocode(_ location: CLLocation) async throws -> ResolvedPlace {
        let geocoder = CLGeocoder()
        // English names so they line up with the (English) dataset.
        let placemarks = try await geocoder.reverseGeocodeLocation(
            location, preferredLocale: Locale(identifier: "en_US"))
        guard let mark = placemarks.first,
              let code = mark.isoCountryCode, !code.isEmpty else {
            throw PlaceResolverError.noCountry
        }
        return ResolvedPlace(locality: mark.locality,
                             adminArea: mark.administrativeArea,
                             countryCode: code.uppercased(),
                             countryName: mark.country)
    }

    /// Finds the most specific dataset area for a place: a matching city or
    /// district, else a matching region (for example a US state), else the
    /// country. Returns nil when the dataset has no root area for the country,
    /// in which case the app must say so instead of guessing.
    static func matchArea(for place: ResolvedPlace, in areas: [Area]) -> Area? {
        let code = place.countryCode.uppercased()
        let inCountry = areas.filter { $0.countryCode == code }
        guard let root = inCountry.first(where: { $0.parentID == nil }) else { return nil }

        if let locality = place.locality.map(normalize), !locality.isEmpty,
           let city = inCountry.first(where: {
               ($0.type == .city || $0.type == .district) && normalize($0.name) == locality
           }) {
            return city
        }

        if var admin = place.adminArea {
            if code == "US", let full = USStates.names[admin.uppercased()] { admin = full }
            let wanted = normalize(admin)
            if let region = inCountry.first(where: { $0.type == .region && normalize($0.name) == wanted }) {
                return region
            }
        }
        return root
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Geography only (not emergency data): US state abbreviations as returned by
/// Core Location, used to match the dataset's full state names.
enum USStates {
    static let names: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
        "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
        "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
        "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
        "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
        "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
        "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"
    ]
}
