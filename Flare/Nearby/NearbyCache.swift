import Foundation
import CoreLocation

/// Places returned by live searches, kept on the phone so the Nearby tab and the compass
/// still work without a connection.
///
/// - Only places the person has actually searched near are stored.
/// - Entries older than 90 days are dropped, and the file holds at most 600 places.
/// - It reveals roughly where the person has been, so it uses complete file protection,
///   is excluded from backups, and can be cleared from the Nearby tab.
struct NearbyCache {
    static let maxAge: TimeInterval = 90 * 24 * 3600
    static let maxPlaces = 600

    private(set) var places: [NearbyPlace] = []
    private let fileURL: URL

    init(directory: URL? = nil) {
        let folder: URL
        if let directory {
            folder = directory
        } else {
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            folder = support.appendingPathComponent("Flare", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("nearby-cache.json")
        load()
    }

    // MARK: Reading

    /// Saved places of one kind close to `location`, nearest first.
    func nearest(_ kind: NearbyKind, to location: CLLocation,
                 within meters: CLLocationDistance, limit: Int) -> [NearbyPlace] {
        places
            .filter { $0.kind == kind }
            .map { ($0, $0.distance(from: location)) }
            .filter { $0.1 <= meters }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: Writing

    /// Adds or refreshes places (a newer search replaces an older copy of the same place).
    mutating func merge(_ newPlaces: [NearbyPlace]) {
        guard !newPlaces.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        for place in newPlaces { byID[place.id] = place }
        places = Self.pruned(Array(byID.values))
        save()
    }

    mutating func clear() {
        places = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: Storage

    private mutating func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([NearbyPlace].self, from: data) else { return }
        places = Self.pruned(decoded)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(places) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func pruned(_ list: [NearbyPlace]) -> [NearbyPlace] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let fresh = list.filter { $0.savedAt >= cutoff }
        guard fresh.count > maxPlaces else { return fresh }
        return Array(fresh.sorted { $0.savedAt > $1.savedAt }.prefix(maxPlaces))
    }
}
