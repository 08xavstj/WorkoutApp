import Foundation
import Observation
import AppCore

/// The movement warm-up of a live session (`WarmUpRoutine`) and where you
/// are in it: the pre-flight overview, a step, or done. Keyed by the
/// session's start time in UserDefaults, like `SupersetRegistry`:
/// `WorkoutSession` has no field for it (a schema migration), and it only
/// matters while the session is open, so entries older than two days are
/// dropped.
nonisolated struct WarmUpEntry: Codable, Sendable, Equatable {
    var routine: WarmUpRoutine.Routine
    /// Index into `routine.steps`; past the end once finished.
    var stepIndex: Int
    /// When the current step began; a timed step's countdown runs from here.
    var stepStartedAt: Date
    /// False while the overview ("Start warm-up" / "Skip to ramp sets") shows.
    var hasStarted: Bool
    /// Finished or skipped.
    var isDone: Bool

    var current: WarmUpRoutine.Step? {
        guard hasStarted, !isDone, stepIndex < routine.steps.count else { return nil }
        return routine.steps[stepIndex]
    }

    /// When the current step's countdown ends; nil for a rep step.
    var stepEndsAt: Date? {
        current?.dose.seconds.map { stepStartedAt.addingTimeInterval(Double($0)) }
    }

    var canGoBack: Bool { hasStarted && !isDone }
}

@Observable
final class WarmUpStore {
    static let shared = WarmUpStore()

    /// New key: entries saved by the old routine shape don't decode.
    private static let key = "warmUpRoutines2"
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

    /// Makes the routine for a session that just started, once, when the tier
    /// has movement steps (off and ramp-only make none: the ramp sets are
    /// `WarmUp`). `firstSlots`: the session's exercises' movement slots in order.
    func prepareIfNeeded(sessionStart: Date, tier: WarmUpRoutine.Tier, firstSlots: [MovementSlot], gym: GymProfile, now: Date = .now) {
        guard tier.hasSteps, entries[Self.id(sessionStart)] == nil,
              now.timeIntervalSince(sessionStart) < Self.freshSeconds else { return }
        let routine = WarmUpRoutine.make(tier: tier, firstSlots: firstSlots, gym: gym)
        guard !routine.isEmpty else { return }
        save(WarmUpEntry(routine: routine, stepIndex: 0, stepStartedAt: now, hasStarted: false, isDone: false), for: sessionStart)
    }

    /// Leaves the overview for the first step.
    func start(for sessionStart: Date, now: Date = .now) {
        guard var entry = entry(for: sessionStart), !entry.isDone, !entry.hasStarted else { return }
        entry.hasStarted = true
        entry.stepIndex = 0
        entry.stepStartedAt = now
        save(entry, for: sessionStart)
    }

    /// Moves to the next step; the last one finishes the warm-up. From the
    /// overview it starts instead. `fromStep` makes a timed step's auto-advance
    /// idempotent: the phone and the Watch both fire at 0, only one counts.
    func advance(for sessionStart: Date, fromStep: Int? = nil, now: Date = .now) {
        guard var entry = entry(for: sessionStart), !entry.isDone else { return }
        guard entry.hasStarted else {
            start(for: sessionStart, now: now)
            return
        }
        if let fromStep, fromStep != entry.stepIndex { return }
        entry.stepIndex += 1
        entry.stepStartedAt = now
        if entry.stepIndex >= entry.routine.steps.count { entry.isDone = true }
        save(entry, for: sessionStart)
    }

    /// Back one step; from the first step, back to the overview.
    func back(for sessionStart: Date, now: Date = .now) {
        guard var entry = entry(for: sessionStart), entry.canGoBack else { return }
        if entry.stepIndex == 0 {
            entry.hasStarted = false
        } else {
            entry.stepIndex -= 1
        }
        entry.stepStartedAt = now
        save(entry, for: sessionStart)
    }

    /// Finishes (or skips) the warm-up: on to the ramp sets.
    func finish(for sessionStart: Date) {
        guard var entry = entry(for: sessionStart), !entry.isDone else { return }
        entry.isDone = true
        entry.hasStarted = true
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
