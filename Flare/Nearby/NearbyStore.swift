import Foundation
import Combine
import MapKit
import CoreLocation

/// Live "nearby" search through Apple Maps, plus the offline fallback.
///
/// - Online: searches hospital, police, fire station and pharmacy points of interest
///   around the person (5 km, then 20 km, then 60 km if nothing is found) and keeps the results.
/// - Offline or failed: shows places saved from earlier searches within 100 km, and says so.
/// - Nothing here is verified by Flare. Searching sends the approximate location to Apple Maps.
@MainActor
final class NearbyStore: ObservableObject {
    enum Source: Equatable {
        case live(Date)
        case saved
    }

    struct Result {
        var places: [NearbyPlace]
        var source: Source
    }

    @Published var selectedKind: NearbyKind = .hospital
    @Published var selectedPlaceID: String?
    @Published private(set) var fix: CLLocation?
    @Published private(set) var live: [NearbyKind: [NearbyPlace]] = [:]
    @Published private(set) var liveAt: Date?
    @Published private(set) var isSearching = false
    /// The most recent search could not reach Apple Maps (offline, throttled, ...).
    @Published private(set) var searchFailed = false
    @Published private(set) var savedCount = 0

    private var cache: NearbyCache
    private var lastSearchCenter: CLLocation?
    private var searchTask: Task<Void, Never>?
    /// "Try again" was tapped and a new GPS position was asked for: search as soon as it arrives.
    private var searchOnNextFix = false
    private var fixWaitTask: Task<Void, Never>?

    private static let usedKey = "flare.nearby.used.v1"
    nonisolated private static let radii: [CLLocationDistance] = [5_000, 20_000, 60_000]
    /// Saved places farther than this from the person are not shown.
    static let savedRadius: CLLocationDistance = 100_000
    nonisolated private static let resultLimit = 20

    init() {
        cache = NearbyCache()
        savedCount = cache.places.count
    }

    /// True once the person has opened Nearby. Only then does Flare search in the
    /// background (so the saved places stay fresh); before that it never searches.
    private var hasUsedNearby: Bool {
        UserDefaults.standard.bool(forKey: Self.usedKey)
    }

    // MARK: Lifecycle

    func updateFix(_ newFix: CLLocation) {
        fix = newFix
        if searchOnNextFix {
            searchOnNextFix = false
            fixWaitTask?.cancel()
            refreshIfNeeded(force: true)
            return
        }
        if hasUsedNearby { refreshIfNeeded(force: false) }
    }

    /// Called when the Nearby tab is shown.
    func activate() {
        UserDefaults.standard.set(true, forKey: Self.usedKey)
        refreshIfNeeded(force: false)
    }

    /// Searches again. With `awaitingNewFix` the search waits (up to 8 seconds) for the fresh
    /// GPS position the caller has just asked for, so it is centred on where the person is now;
    /// if none arrives it searches around the last known position.
    func refresh(awaitingNewFix: Bool = false) {
        fixWaitTask?.cancel()
        guard awaitingNewFix else {
            searchOnNextFix = false
            refreshIfNeeded(force: true)
            return
        }
        searchOnNextFix = true
        fixWaitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.searchOnNextFix else { return }
            self.searchOnNextFix = false
            self.refreshIfNeeded(force: true)
        }
    }

    // MARK: Results

    func result(for kind: NearbyKind) -> Result {
        guard let fix else { return Result(places: [], source: .saved) }
        if !searchFailed, let places = live[kind], !places.isEmpty {
            let sorted = places.sorted { $0.distance(from: fix) < $1.distance(from: fix) }
            return Result(places: Array(sorted.prefix(Self.resultLimit)),
                          source: .live(liveAt ?? Date()))
        }
        let saved = cache.nearest(kind, to: fix, within: Self.savedRadius, limit: Self.resultLimit)
        return Result(places: saved, source: .saved)
    }

    func nearestDistance(for kind: NearbyKind) -> CLLocationDistance? {
        guard let fix, let first = result(for: kind).places.first else { return nil }
        return first.distance(from: fix)
    }

    func clearSavedPlaces() {
        cache.clear()
        savedCount = 0
    }

    // MARK: Searching

    private func refreshIfNeeded(force: Bool) {
        guard let fix else { return }
        if !force {
            if isSearching { return }
            if !searchFailed, let center = lastSearchCenter, let at = liveAt,
               center.distance(from: fix) < 1_000, Date().timeIntervalSince(at) < 600 {
                return
            }
        }
        search(around: fix)
    }

    private func search(around center: CLLocation) {
        searchTask?.cancel()
        isSearching = true
        let coordinate = center.coordinate
        searchTask = Task { [weak self] in
            let found = await withTaskGroup(of: (NearbyKind, [NearbyPlace]?).self) { group in
                for kind in NearbyKind.allCases {
                    group.addTask {
                        (kind, try? await NearbyStore.searchPlaces(kind: kind, around: coordinate))
                    }
                }
                var collected: [NearbyKind: [NearbyPlace]] = [:]
                for await (kind, places) in group {
                    if let places { collected[kind] = places }
                }
                return collected
            }
            if Task.isCancelled { return }
            self?.finishSearch(found, center: center)
        }
    }

    private func finishSearch(_ found: [NearbyKind: [NearbyPlace]], center: CLLocation) {
        isSearching = false
        if found.isEmpty {
            // Every request failed: most likely no connection.
            searchFailed = true
            return
        }
        searchFailed = false
        live = found
        liveAt = Date()
        lastSearchCenter = center
        cache.merge(found.values.flatMap { $0 })
        savedCount = cache.places.count
    }

    nonisolated private static func searchPlaces(kind: NearbyKind,
                                                 around center: CLLocationCoordinate2D) async throws -> [NearbyPlace] {
        for radius in radii {
            let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [kind.category])
            do {
                let response = try await MKLocalSearch(request: request).start()
                let now = Date()
                var seen = Set<String>()
                let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
                let places = response.mapItems
                    .compactMap { NearbyPlace(item: $0, kind: kind, savedAt: now) }
                    .filter { seen.insert($0.id).inserted }
                    .sorted { $0.distance(from: origin) < $1.distance(from: origin) }
                if !places.isEmpty { return Array(places.prefix(resultLimit)) }
            } catch let error as MKError where error.code == .placemarkNotFound {
                continue   // nothing in this radius: try a wider one
            }
        }
        return []
    }
}
