import Foundation
import Observation
import AppCore

/// The places hidden on shared routes and the start/end switch (Settings ›
/// Data & privacy › Route privacy), as JSON in Application Support. They
/// never leave the phone. The trimming itself is `RoutePrivacy` (AppCore).
@Observable
final class RoutePrivacyStore {
    static let shared = RoutePrivacyStore()

    nonisolated struct State: Codable, Equatable {
        var zones: [PrivacyZone] = []
        /// Trim 250–400 m off the start and end of every shared route (spec B2b).
        var hideEndpoints = true
        /// Random per phone, so a workout's trim can't be worked out from its ID.
        var salt = UUID().uuidString
    }

    private(set) var state = State()

    @ObservationIgnored private let file = SafeJSONFile.appSupport("route-privacy.json")
    @ObservationIgnored private var canSave = false
    /// The screenshot tour keeps its places in memory only.
    @ObservationIgnored private let isDemo = DemoHealth.active != nil

    init() {
        reload()
    }

    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        guard !isDemo else { return }
        let loaded = file.loadLogged(State.self)
        canSave = loaded.state.canSave
        guard canSave else { return }
        if let value = loaded.value {
            state = value
        } else {
            // No file yet (or an unreadable one set aside): save the new salt
            // now. Otherwise it changes every launch until a setting is
            // edited, each share of the same workout draws a new trim, and
            // comparing them reveals more of the route.
            state = State()
            write()
        }
    }

    private func write() {
        guard !isDemo else { return }
        file.saveLogged(state, canSave: canSave)
    }

    // MARK: Editing

    var zones: [PrivacyZone] { state.zones }
    var canAddZone: Bool { state.zones.count < RoutePrivacy.maximumZones }

    var hideEndpoints: Bool {
        get { state.hideEndpoints }
        set {
            reloadIfUnavailable()
            state.hideEndpoints = newValue
            write()
        }
    }

    /// Adds or replaces a place (matched by ID).
    func save(_ zone: PrivacyZone) {
        reloadIfUnavailable()
        if let index = state.zones.firstIndex(where: { $0.id == zone.id }) {
            state.zones[index] = zone
        } else if canAddZone {
            state.zones.append(zone)
        }
        write()
    }

    func remove(_ zone: PrivacyZone) {
        reloadIfUnavailable()
        state.zones.removeAll { $0.id == zone.id }
        write()
    }

    // MARK: Applying

    /// The route as it may leave the phone: private parts hidden, unless
    /// `full` (the per-export "Full route" switch).
    func trim(_ route: CardioRoute, workoutID: UUID, full: Bool = false) -> RoutePrivacy.Result {
        reloadIfUnavailable()
        guard !full else { return RoutePrivacy.untrimmed(route.points) }
        let seed = RoutePrivacy.seed(workoutID: workoutID, salt: state.salt)
        return RoutePrivacy.trim(route.points, zones: state.zones, hideEndpoints: state.hideEndpoints, seed: seed)
    }
}
