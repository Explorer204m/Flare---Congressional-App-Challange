import Foundation
import Combine
import CoreLocation

/// Single source of truth for the Home screen: the offline database, the
/// selected area, and the call plan for that area.
///
/// Nothing here invents emergency numbers. Every number shown comes from the
/// bundled database; when the database has nothing for an area, the plan is empty
/// and the UI says so.
@MainActor
final class EmergencyStore: ObservableObject {
    enum DatabaseState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var databaseState: DatabaseState = .loading
    @Published private(set) var datasetInfo: DatasetInfo?
    @Published private(set) var allAreas: [Area] = []
    @Published private(set) var selection: AreaSelection?
    @Published private(set) var rows: [ContactRow] = []
    @Published private(set) var plan: CallPlan = .empty
    /// The position couldn't be matched to an area (offline and far from the last known place).
    @Published private(set) var needsConfirmation = false
    /// Name of the place we're in when the dataset has no entry for that country.
    @Published private(set) var unsupportedPlace: String?
    @Published private(set) var lookupFailed = false

    let location = LocationService()

    private var database: EmergencyDatabase?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var overrideManualOnNextFix = false
    private var geocodeTask: Task<Void, Never>?

    private static let selectionKey = "flare.selection.v1"
    /// Offline, a new fix this close to the last verified one keeps the same area.
    private static let trustedRadiusMeters: CLLocationDistance = 100_000

    init() {
        // Views observe the store; forward location changes (permission etc.).
        location.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true

        await openDatabase()
        restoreSelection()
        await reloadRows()

        location.$latestFix
            .compactMap { $0 }
            .sink { [weak self] fix in self?.handleFix(fix) }
            .store(in: &cancellables)
        location.start()
    }

    /// Called when the app returns to the foreground.
    func refreshLocation() {
        guard started, databaseState == .ready else { return }
        if selection?.source == .manual && !overrideManualOnNextFix { return }
        location.start()
    }

    // MARK: Selection

    func select(_ area: Area) {
        let selection = AreaSelection(
            areaID: area.id,
            title: displayTitle(for: area),
            subtitle: "Selected manually",
            countryCode: area.countryCode,
            source: .manual,
            resolvedAt: Date(),
            latitude: nil,
            longitude: nil)
        overrideManualOnNextFix = false
        needsConfirmation = false
        unsupportedPlace = nil
        apply(selection)
        Task { await reloadRows() }
    }

    /// Goes back to using the phone's location after a manual choice.
    func useMyLocation() {
        overrideManualOnNextFix = true
        location.start()
    }

    func countryName(for area: Area) -> String {
        allAreas.first(where: { $0.countryCode == area.countryCode && $0.parentID == nil })?.name
            ?? area.countryCode
    }

    func displayTitle(for area: Area) -> String {
        area.type.isRoot ? area.name : "\(area.name), \(countryName(for: area))"
    }

    func pickerSubtitle(for area: Area) -> String {
        area.type.isRoot ? area.type.label : "\(area.type.label) \u{00B7} \(countryName(for: area))"
    }

    // MARK: Database

    private func openDatabase() async {
        guard let url = BundleResource.url(forResource: "emergency", withExtension: "sqlite") else {
            databaseState = .failed("The emergency database is missing from the app.")
            return
        }
        do {
            let opened = try await Task.detached(priority: .userInitiated) {
                try EmergencyDatabase(bundleURL: url)
            }.value
            let areas = try await opened.areas()
            let metadata = try await opened.metadata()
            database = opened
            allAreas = areas
            datasetInfo = DatasetInfo(metadata: metadata)
            databaseState = .ready
        } catch {
            databaseState = .failed("The emergency database could not be opened.")
        }
    }

    private func reloadRows() async {
        guard let database, let selection else {
            rows = []
            plan = .empty
            lookupFailed = false
            return
        }
        do {
            let found = try await database.lookup(areaID: selection.areaID)
            rows = found
            plan = CallPlanner.plan(from: found)
            lookupFailed = false
        } catch {
            rows = []
            plan = .empty
            lookupFailed = true
        }
    }

    // MARK: Location handling

    private func handleFix(_ fix: CLLocation) {
        guard databaseState == .ready else { return }
        if selection?.source == .manual && !overrideManualOnNextFix { return }
        geocodeTask?.cancel()
        geocodeTask = Task { [weak self] in
            await self?.resolve(fix)
        }
    }

    private func resolve(_ fix: CLLocation) async {
        do {
            let place = try await PlaceResolver.reverseGeocode(fix)
            if Task.isCancelled { return }
            overrideManualOnNextFix = false
            needsConfirmation = false

            guard let area = PlaceResolver.matchArea(for: place, in: allAreas) else {
                // Country not in the dataset: say so, never fall back to another country's numbers.
                unsupportedPlace = place.countryName ?? place.countryCode
                apply(nil)
                await reloadRows()
                return
            }
            unsupportedPlace = nil
            let resolved = AreaSelection(
                areaID: area.id,
                title: place.displayTitle(fallback: area.name),
                subtitle: place.countryName ?? countryName(for: area),
                countryCode: area.countryCode,
                source: .location,
                resolvedAt: Date(),
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude)
            apply(resolved)
            await reloadRows()
        } catch {
            if Task.isCancelled { return }
            handleUnresolvedFix(fix)
        }
    }

    /// Reverse geocoding needs a connection. Offline, keep the last known area if
    /// the phone is still near where it was verified; otherwise ask the person to confirm.
    private func handleUnresolvedFix(_ fix: CLLocation) {
        guard let current = selection else {
            needsConfirmation = true
            return
        }
        if current.source == .location, let lat = current.latitude, let lon = current.longitude {
            let distance = fix.distance(from: CLLocation(latitude: lat, longitude: lon))
            needsConfirmation = distance > Self.trustedRadiusMeters
        } else {
            needsConfirmation = true
        }
    }

    // MARK: Persistence

    private func apply(_ newSelection: AreaSelection?) {
        selection = newSelection
        let defaults = UserDefaults.standard
        if let newSelection, let data = try? JSONEncoder().encode(newSelection) {
            defaults.set(data, forKey: Self.selectionKey)
        } else {
            defaults.removeObject(forKey: Self.selectionKey)
        }
    }

    private func restoreSelection() {
        guard let data = UserDefaults.standard.data(forKey: Self.selectionKey),
              let saved = try? JSONDecoder().decode(AreaSelection.self, from: data),
              allAreas.contains(where: { $0.id == saved.areaID }) else { return }
        selection = saved
    }
}
