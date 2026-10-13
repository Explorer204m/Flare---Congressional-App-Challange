import Foundation

/// The area whose numbers are being shown, remembered between launches so the
/// app works immediately, and offline, on the next start.
struct AreaSelection: Codable, Equatable {
    enum Source: String, Codable {
        /// Worked out from the phone's location.
        case location
        /// Chosen by the person; location updates won't change it.
        case manual
    }

    var areaID: Int64
    /// Header line, for example "Atlanta, Georgia".
    var title: String
    /// Second header line, for example "United States".
    var subtitle: String
    var countryCode: String
    var source: Source
    /// When the area was last confirmed (by location lookup or by the person).
    var resolvedAt: Date
    /// Where a location-based selection was made, for judging if it is still plausible offline.
    var latitude: Double?
    var longitude: Double?
}
