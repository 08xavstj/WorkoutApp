import AppCore
import Foundation

/// Best efforts per Health workout (`CardioBests`), worked out once from its
/// route and kept as JSON in Application Support (`SafeJSONFile`, as the
/// other stores), so routes aren't read from Apple Health again on every open.
/// A workout without a route, or of a kind without bests, is kept as an empty
/// entry so it isn't read again either.
enum CardioBestsStore {
    static let fileName = "cardio-best-efforts.json"
    private static let file = SafeJSONFile.appSupport(fileName)
    /// Raise when `CardioBests`'s maths changes: older entries are worked out again.
    /// 2: GPS jumps and pause gaps no longer add distance; the end is interpolated too.
    static let version = 2
    /// UserDefaults key holding the `version` the last complete backfill used.
    static let backfillCompleteKey = "cardioBestsBackfillCompleteVersion"
    /// Routes read per backfill (the app's choice: about a minute's work at most).
    static let batch = 60
    /// How far back the backfill looks for workouts.
    static let years = 5
    /// A workout this recent with no route yet may still be syncing from
    /// the watch, so it isn't cached as "no route" (the app's choice).
    static let routeSyncGrace: TimeInterval = 24 * 3600

    nonisolated struct Entry: Codable, Sendable, Equatable {
        var version: Int
        /// Nil: no route, or not a run, walk or ride.
        var efforts: CardioBests.WorkoutEfforts?
        /// The workout's start, so `prune` knows whether the last read covered it.
        var date: Date?
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

    /// True when every workout of the last `years` has been checked with the
    /// current maths, so a "Best" compares with all of them, not only those
    /// read so far.
    static var isBackfillComplete: Bool {
        UserDefaults.standard.integer(forKey: backfillCompleteKey) == version
    }

    /// Saves entries (nil efforts = nothing to find) in one write.
    static func store(_ updates: [UUID: CardioBests.WorkoutEfforts?], dates: [UUID: Date] = [:]) {
        guard !updates.isEmpty else { return }
        var all = entries()
        guard canSave else { return }
        var changed = false
        for (id, efforts) in updates {
            let entry = Entry(version: version, efforts: efforts, date: efforts?.date ?? dates[id])
            if all[id.uuidString] != entry {
                all[id.uuidString] = entry
                changed = true
            }
        }
        guard changed else { return }
        cache = all
        file.saveLogged(all, canSave: canSave)
    }

    /// Forgets one workout (deleted from Health).
    static func remove(_ id: UUID) {
        var all = entries()
        guard canSave, all.removeValue(forKey: id.uuidString) != nil else { return }
        cache = all
        file.saveLogged(all, canSave: canSave)
    }

    /// Forgets workouts from `since` on (or of unknown date) that a complete
    /// read of Health no longer returned: deleted, or re-synced under a new ID.
    static func prune(keeping ids: Set<UUID>, since: Date) {
        var all = entries()
        guard canSave else { return }
        let kept = Set(ids.map(\.uuidString))
        let before = all.count
        all = all.filter { key, entry in
            kept.contains(key) || (entry.efforts?.date ?? entry.date).map { $0 < since } == true
        }
        guard all.count != before else { return }
        cache = all
        file.saveLogged(all, canSave: canSave)
    }

    /// Reads the routes of workouts not cached yet, newest first, `batch` at a
    /// time, and prunes workouts Health no longer has. `progress` gets the
    /// current workouts as they are saved. Returns how many are left for next
    /// time, or nil when Health's workout list couldn't be read.
    @discardableResult
    static func backfill(health: HealthKitClient,
                         progress: ([CardioBests.WorkoutEfforts]) -> Void = { _ in }) async -> Int? {
        let now = Date.now
        let start = Calendar.current.date(byAdding: .year, value: -years, to: now) ?? now
        // A failed read isn't "no workouts": keep the cache as it is.
        guard let found = try? await health.externalWorkouts(from: start, to: now), !Task.isCancelled else { return nil }
        prune(keeping: Set(found.map(\.uuid)), since: start)
        // Runs, walks and rides long enough for the shortest distance (400 m).
        let candidates = found
            .filter { CardioBests.Sport.of($0.kind) != nil && ($0.distanceKm ?? 0) >= 0.4 && !isKnown($0.uuid) }
            .sorted { $0.start > $1.start }
        let remaining = max(0, candidates.count - batch)
        var updates: [UUID: CardioBests.WorkoutEfforts?] = [:]
        var dates: [UUID: Date] = [:]
        var allRead = true
        var cancelled = false
        for workout in candidates.prefix(batch) {
            if Task.isCancelled { cancelled = true; break }
            let points: [RoutePoint]
            do {
                points = try await health.workoutRoute(id: workout.uuid)
            } catch {
                // Not "no route": try again next time.
                allRead = false
                continue
            }
            if Task.isCancelled { cancelled = true; break }
            // The route may still be on its way from the watch.
            if points.isEmpty, now.timeIntervalSince(workout.end) < routeSyncGrace { continue }
            let id = workout.uuid, date = workout.start, kind = workout.kind
            let efforts = await Task.detached(priority: .utility) {
                CardioBestsStore.efforts(id: id, date: date, kind: kind, route: CardioRoute(points: points))
            }.value
            updates.updateValue(efforts, forKey: id)
            dates[id] = date
            // Save as it goes, so leaving the page keeps what was read.
            if updates.count >= 10 {
                store(updates, dates: dates)
                updates = [:]
                dates = [:]
                progress(workouts())
            }
        }
        store(updates, dates: dates)
        progress(workouts())
        if !cancelled, !Task.isCancelled, allRead, remaining == 0 {
            UserDefaults.standard.set(version, forKey: backfillCompleteKey)
        }
        return remaining
    }

    /// Efforts for a loaded route, or nil when the kind has no bests or the route is empty.
    nonisolated static func efforts(id: UUID, date: Date, kind: ActivityKind, route: CardioRoute) -> CardioBests.WorkoutEfforts? {
        guard let sport = CardioBests.Sport.of(kind), route.points.count >= 2 else { return nil }
        let efforts = CardioBests.efforts(route: route, sport: sport)
        return efforts.isEmpty ? nil : CardioBests.WorkoutEfforts(workoutID: id.uuidString, date: date, sport: sport, efforts: efforts)
    }
}
