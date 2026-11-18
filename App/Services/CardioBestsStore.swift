import AppCore
import Foundation

/// Best efforts per Health workout (`CardioBests`), worked out once from its
/// route and kept as JSON in Application Support (`SafeJSONFile`, as the
/// other stores), so routes aren't read from Apple Health again on every open.
/// A workout without a route, or of a kind without bests, is kept as an empty
/// entry so it isn't read again either.
enum CardioBestsStore {
    private static let file = SafeJSONFile.appSupport("cardio-best-efforts.json")
    /// Raise when `CardioBests`'s maths changes: older entries are worked out again.
    static let version = 1

    nonisolated struct Entry: Codable, Sendable, Equatable {
        var version: Int
        /// Nil: no route, or not a run, walk or ride.
        var efforts: CardioBests.WorkoutEfforts?
    }

    private static var cache: [String: Entry]?
    private static var canSave = true

    /// Entries by workout UUID string.
    static func entries() -> [String: Entry] {
        if let cache { return cache }
        let loaded = file.loadLogged([String: Entry].self)
        canSave = loaded.state.canSave
        let value = loaded.value ?? [:]
        // Don't keep an unreadable file's empty result: try again next time.
        if loaded.state.canSave { cache = value }
        return value
    }

    /// Workouts with current efforts (version matches).
    static func workouts() -> [CardioBests.WorkoutEfforts] {
        entries().values.filter { $0.version == version }.compactMap(\.efforts)
    }

    /// True when the workout was already worked out with the current maths.
    static func isKnown(_ id: UUID) -> Bool {
        entries()[id.uuidString]?.version == version
    }

    /// Saves entries (nil efforts = nothing to find) in one write.
    static func store(_ updates: [UUID: CardioBests.WorkoutEfforts?]) {
        guard !updates.isEmpty else { return }
        var all = entries()
        guard canSave else { return }
        var changed = false
        for (id, efforts) in updates {
            let entry = Entry(version: version, efforts: efforts)
            if all[id.uuidString] != entry {
                all[id.uuidString] = entry
                changed = true
            }
        }
        guard changed else { return }
        cache = all
        file.saveLogged(all, canSave: canSave)
    }

    /// Efforts for a loaded route, or nil when the kind has no bests or the route is empty.
    nonisolated static func efforts(id: UUID, date: Date, kind: ActivityKind, route: CardioRoute) -> CardioBests.WorkoutEfforts? {
        guard let sport = CardioBests.Sport.of(kind), route.points.count >= 2 else { return nil }
        let efforts = CardioBests.efforts(route: route, sport: sport)
        return efforts.isEmpty ? nil : CardioBests.WorkoutEfforts(workoutID: id.uuidString, date: date, sport: sport, efforts: efforts)
    }
}
