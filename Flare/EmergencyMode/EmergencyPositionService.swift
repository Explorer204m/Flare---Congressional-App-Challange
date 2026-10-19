import Foundation
import CoreLocation

/// GPS position for Emergency Mode. To save battery it asks for one fix now and then one
/// every few minutes (the interval grows as the battery drops) instead of keeping GPS
/// running. It runs only while the screen is open, and nothing here leaves the phone.
///
/// Routine fixes ask for about 10 m on a normal battery and about 100 m once the battery is
/// low. Before the location is sent, or when the person taps "Update now", a short precise
/// request (`precisePosition()`) asks for the best accuracy for at most 10 seconds. The
/// accuracy asked for is only a target: the message always states the accuracy and age of
/// the fix that is actually used.
@MainActor
final class EmergencyPositionService: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isDenied = false
    /// A precise fix is being looked for right now.
    @Published private(set) var isRefining = false

    /// A fix this accurate ends the precise request early.
    nonisolated static let preciseAccuracy: CLLocationAccuracy = 50
    /// The precise request never runs longer than this.
    nonisolated static let preciseTimeout: Duration = .seconds(10)

    private let manager = CLLocationManager()
    private var loop: Task<Void, Never>?
    private var tier: PowerTier = .normal
    /// The screen wants positions. False after `stop()`, so a late permission answer
    /// can't start GPS again for a screen that has gone away.
    private var wanted = false

    private var refineTimeout: Task<Void, Never>?
    private var refineStartedAt = Date.distantPast
    private var refineBest: CLLocation?
    private var refineWaiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        isDenied = Self.denied(manager.authorizationStatus)
    }

    private static func denied(_ status: CLAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }

    private static func authorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func start(tier: PowerTier) {
        self.tier = tier
        wanted = true
        configure()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginLoop()
        default:
            break
        }
    }

    func apply(tier: PowerTier) {
        self.tier = tier
        configure()
        if loop != nil { beginLoop() }
    }

    func stop() {
        wanted = false
        loop?.cancel()
        loop = nil
        finishRefining()
        // Also cancels a requestLocation() that hasn't answered yet.
        manager.stopUpdatingLocation()
    }

    /// "Update now": look for a precise fix in the background.
    func refreshNow() {
        Task { _ = await precisePosition() }
    }

    /// Asks for the best accuracy for up to `preciseTimeout`, stopping early once a fresh fix
    /// of `preciseAccuracy` or better arrives, then returns to routine fixes.
    ///
    /// Returns the most accurate fresh fix seen, or nil when none arrived in time (or location
    /// is off). `location` is updated as fixes arrive either way. Callers fall back to the last
    /// fix they had, which the location message labels with its accuracy and age.
    func precisePosition() async -> CLLocation? {
        guard wanted, Self.authorized(manager.authorizationStatus) else { return nil }
        if !isRefining { beginRefining() }
        return await withCheckedContinuation { continuation in
            refineWaiters.append(continuation)
        }
    }

    // MARK: Routine fixes

    /// One fix now, then one every `tier.locationInterval`.
    private func beginLoop() {
        loop?.cancel()
        if !isRefining { manager.requestLocation() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = self?.tier.locationInterval ?? 600
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                guard let self else { break }
                // A precise request already has GPS running; don't overlap it.
                if !self.isRefining { self.manager.requestLocation() }
            }
        }
    }

    private func configure() {
        guard !isRefining else { return }
        manager.desiredAccuracy = tier == .normal
            ? kCLLocationAccuracyNearestTenMeters
            : kCLLocationAccuracyHundredMeters
    }

    // MARK: Precise request

    private func beginRefining() {
        isRefining = true
        refineStartedAt = Date()
        refineBest = nil
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.startUpdatingLocation()
        refineTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.preciseTimeout)
            if Task.isCancelled { return }
            self?.finishRefining()
        }
    }

    private func finishRefining() {
        guard isRefining else { return }
        isRefining = false
        refineTimeout?.cancel()
        refineTimeout = nil
        manager.stopUpdatingLocation()
        configure()
        let result = refineBest
        refineBest = nil
        let waiters = refineWaiters
        refineWaiters = []
        for waiter in waiters { waiter.resume(returning: result) }
    }

    private func handle(_ fix: CLLocation) {
        if location.map({ fix.timestamp >= $0.timestamp }) ?? true {
            location = fix
        }
        guard isRefining else { return }
        // Location updates can start with a cached fix; only fixes from this request count.
        guard fix.timestamp >= refineStartedAt.addingTimeInterval(-2) else { return }
        if refineBest.map({ fix.horizontalAccuracy < $0.horizontalAccuracy }) ?? true {
            refineBest = fix
        }
        if fix.horizontalAccuracy <= Self.preciseAccuracy { finishRefining() }
    }
}

extension EmergencyPositionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isDenied = Self.denied(status)
            if Self.authorized(status) {
                // Only for a screen that still wants location (not after stop()).
                if self.wanted, self.loop == nil { self.beginLoop() }
            } else {
                self.finishRefining()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in self.handle(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last position; the screen shows how old it is. A precise request
        // simply runs until its time limit.
    }
}
