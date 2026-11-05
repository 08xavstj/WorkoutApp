import Foundation
import Observation
import AppCore

/// The movement warm-up of a live session (`WarmUpRoutine`) and how far
/// through it you are, keyed by the session's start time in UserDefaults,
/// like `SupersetRegistry`: `WorkoutSession` has no field for it (a schema
/// migration), and it only matters while the session is open, so entries
/// older than two days are dropped.
nonisolated struct WarmUpEntry: Codable, Sendable, Equatable {
    var routine: WarmUpRoutine.Routine
    /// Index into `routine.movements`; past the end once finished.
    var stepIndex: Int
    /// When the current step began; its countdown runs from here.
    var stepStartedAt: Date
    /// Finished or skipped.
    var isDone: Bool

    var current: WarmUpRoutine.Movement? {
        guard !isDone, stepIndex < routine.movements.count else { return nil }
        return routine.movements[stepIndex]
    }

    var stepEndsAt: Date? {
        current.map { stepStartedAt.addingTimeInterval(Double($0.seconds)) }
    }

    /// Steps after the current one.
    var upcoming: [WarmUpRoutine.Movement] {
        guard !isDone, stepIndex + 1 < routine.movements.count else { return [] }
        return Array(routine.movements[(stepIndex + 1)...])
    }
}

@Observable
final class WarmUpStore {
    static let shared = WarmUpStore()

    private static let key = "warmUpRoutines"
    private static let keepSeconds: TimeInterval = 2 * 86_400
    /// A session older than this when the workout screen opens was started
    /// without this feature (or long ago): no warm-up is made for it.
    private static let freshSeconds: TimeInterval = 3 * 60

    /// Session id (`WatchSession.id(for:)`) → entry.
    private(set) var entries: [String: WarmUpEntry]

    init() {
        entries = Self.load()
    }

    func entry(for sessionStart: Date) -> WarmUpEntry? {
        entries[Self.id(sessionStart)]
    }

    /// Makes the routine for a session that just started, once, when the
    /// builder's toggle is on. Sessions with no exercises get none.
    func prepareIfNeeded(sessionStart: Date, enabled: Bool, exerciseIDs: [String], gym: GymProfile, now: Date = .now) {
        guard enabled, !exerciseIDs.isEmpty, entries[Self.id(sessionStart)] == nil,
              now.timeIntervalSince(sessionStart) < Self.freshSeconds else { return }
        let routine = WarmUpRoutine.make(focus: nil, exerciseIDs: exerciseIDs, gym: gym)
        save(WarmUpEntry(routine: routine, stepIndex: 0, stepStartedAt: now, isDone: false), for: sessionStart)
    }

    /// Moves to the next movement; the last one finishes the warm-up.
    func advance(for sessionStart: Date, now: Date = .now) {
        guard var entry = entry(for: sessionStart), !entry.isDone else { return }
        entry.stepIndex += 1
        entry.stepStartedAt = now
        if entry.stepIndex >= entry.routine.movements.count { entry.isDone = true }
        save(entry, for: sessionStart)
    }

    /// Finishes (or skips) the warm-up.
    func finish(for sessionStart: Date) {
        guard var entry = entry(for: sessionStart), !entry.isDone else { return }
        entry.isDone = true
        save(entry, for: sessionStart)
    }

    private func save(_ entry: WarmUpEntry, for sessionStart: Date) {
        let cutoff = Date.now.addingTimeInterval(-Self.keepSeconds)
        entries = entries.filter { Double($0.key).map { Date(timeIntervalSince1970: $0) >= cutoff } ?? false }
        entries[Self.id(sessionStart)] = entry
        let encoder = JSONEncoder()
        var raw: [String: Data] = [:]
        for (id, value) in entries {
            if let data = try? encoder.encode(value) { raw[id] = data }
        }
        UserDefaults.standard.set(raw, forKey: Self.key)
    }

    private static func id(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    private static func load() -> [String: WarmUpEntry] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] else { return [:] }
        let decoder = JSONDecoder()
        var result: [String: WarmUpEntry] = [:]
        for (id, data) in raw {
            if let entry = try? decoder.decode(WarmUpEntry.self, from: data) { result[id] = entry }
        }
        return result
    }
}
