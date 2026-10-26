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
        /// Kinds whose places here come from the saved copy, not a live search.
        var savedKinds: Set<NearbyKind> = []
    }

    @Published var selectedScope: NearbyScope = .nearestOfEach
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
        return Result(places: saved, source: .saved, savedKinds: saved.isEmpty ? [] : [kind])
    }

    /// Either one kind, or the nearest hospital, police station, fire station and pharmacy
    /// (one of each, nearest first).
    /// A kind with no live results falls back to its saved places, and each place says which it is.
    func result(in scope: NearbyScope) -> Result {
        switch scope {
        case .kind(let kind):
            var single = result(for: kind)
            if single.source == .saved && !single.places.isEmpty { single.savedKinds = [kind] }
            return single
        case .nearestOfEach:
            guard let fix else { return Result(places: [], source: .saved) }
            // Only the kinds for people (no vet). A kind with nothing found is simply left out.
            let parts = NearbyKind.peopleKinds.map { result(for: $0) }
            let nearest = parts
                .compactMap { part in
                    part.places.min { $0.distance(from: fix) < $1.distance(from: fix) }
                }
                .sorted { $0.distance(from: fix) < $1.distance(from: fix) }
            let shown = Set(nearest.map { $0.kind })
            let saved = parts.reduce(into: Set<NearbyKind>()) { $0.formUnion($1.savedKinds) }
                .intersection(shown)
            let hasLive = parts.contains { part in
                if case .live = part.source, !part.places.isEmpty { return true }
                return false
            }
            return Result(places: Array(nearest),
                          source: hasLive ? .live(liveAt ?? Date()) : .saved,
                          savedKinds: saved)
        }
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
                        do {
                            let places = try await NearbyStore.searchPlaces(kind: kind, around: coordinate)
                            #if DEBUG
                            print("[Nearby] \(kind.rawValue): \(places.count) places around \(coordinate.latitude), \(coordinate.longitude)")
                            #endif
                            return (kind, places)
                        } catch {
                            #if DEBUG
                            print("[Nearby] \(kind.rawValue) search failed: \(error)")
                            #endif
                            return (kind, nil)
                        }
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
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let query: String
        switch kind {
        case .hospital: query = "hospital"
        case .police: query = "police station"
        case .fire: query = "fire station"
        case .pharmacy: query = "pharmacy"
        case .vet: query = "emergency veterinarian"
        }
        // A real failure (not just "nothing found here"), so a dead connection still shows as offline.
        var failure: Error?
        for radius in radii {
            var items: [MKMapItem] = []
            var fromText = false

            // 1. Apple Maps' own category search.
            if let category = kind.category {
                let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
                do {
                    items = try await MKLocalSearch(request: request).start().mapItems
                } catch {
                    if (error as? MKError)?.code != .placemarkNotFound { failure = error }
                }
            }

            // 2. Text search: how vets are found, and the fallback when the category search
            //    returns nothing (it can come back empty in places where the text search works).
            if items.isEmpty {
                fromText = true
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = MKCoordinateRegion(center: center,
                                                    latitudinalMeters: radius * 2,
                                                    longitudinalMeters: radius * 2)
                request.resultTypes = .pointOfInterest
                do {
                    items = try await MKLocalSearch(request: request).start().mapItems
                } catch {
                    if (error as? MKError)?.code != .placemarkNotFound { failure = error }
                }
            }

            let now = Date()
            var seen = Set<String>()
            let places = items
                // Text results can include other kinds of place: keep only the right category.
                .filter { item in
                    guard fromText, let wanted = kind.category,
                          let found = item.pointOfInterestCategory else { return true }
                    return found == wanted
                }
                .compactMap { NearbyPlace(item: $0, kind: kind, savedAt: now) }
                .filter { seen.insert($0.id).inserted }
                .filter { $0.distance(from: origin) <= radius }
                .sorted { $0.distance(from: origin) < $1.distance(from: origin) }
            if !places.isEmpty { return Array(places.prefix(resultLimit)) }
        }
        if let failure { throw failure }
        return []
    }
}
