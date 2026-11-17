import AppCore
import Foundation

/// The reminders that went out and the lines the pending ones hold
/// (`WorkoutBanter.Store`), in a small JSON file in Application Support like
/// the app's other stores. Behind a lock, so the scheduler and the
/// background writer can both use it off the main actor.
nonisolated final class WorkoutVoiceStore: @unchecked Sendable {
    static let shared = WorkoutVoiceStore()

    private let lock = NSLock()
    private let file = SafeJSONFile.appSupport("workout-voice.json")
    private var cached: WorkoutBanter.Store?
    private var canSave = true
    private var asking = false

    /// Call with the lock held. A file that can't be read yet (phone locked)
    /// isn't cached and isn't written over; the next call reads it again.
    private func loaded() -> WorkoutBanter.Store {
        if let cached { return cached }
        let result = file.loadLogged(WorkoutBanter.Store.self)
        canSave = result.state.canSave
        let store = result.value ?? WorkoutBanter.Store()
        if canSave { cached = store }
        return store
    }

    /// Call with the lock held.
    private func save(_ store: WorkoutBanter.Store) {
        guard canSave else { return }
        cached = store
        file.saveLogged(store, canSave: true)
    }

    /// Each pending reminder's facts as last scheduled, so a line the model
    /// finishes later is checked against them (`finishAsking`). Not saved.
    private var latestFacts: [String: WorkoutBanter.Facts] = [:]
    /// Whether model lines were allowed at the last schedule (switched on, model available).
    private var latestFreshLines = true

    /// Gives each reminder being scheduled its line (`WorkoutBanter.reconcile`) and saves the result.
    /// - Parameter freshLines: model lines are switched on and the model is available.
    func reconcile(_ requests: [WorkoutBanter.DayRequest], tone: WorkoutBanter.Tone, freshLines: Bool,
                   now: Date) -> [String: WorkoutBanter.Assigned] {
        lock.lock(); defer { lock.unlock() }
        latestFacts = Dictionary(requests.map { ($0.dayKey, $0.facts) }, uniquingKeysWith: { _, last in last })
        latestFreshLines = freshLines
        let before = loaded()
        let after = WorkoutBanter.reconcile(before, requests: requests, tone: tone, now: now, freshLines: freshLines)
        if after != before { save(after) }
        return Dictionary(after.pending.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func history() -> WorkoutBanter.History {
        lock.lock(); defer { lock.unlock() }
        return loaded().history
    }

    /// One request to the model at a time; false when one is already running.
    func startAsking() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !asking else { return false }
        asking = true
        return true
    }

    /// Notes that the model was asked about `dayKey`'s reminder and stores its
    /// line when it passed every check, only if the reminder still holds the
    /// line it was asked about (`askedFor`) and the line is still true for the
    /// facts as last scheduled (`WorkoutBanter.applyGenerated`). Returns what
    /// that reminder holds now, or nil when it is no longer pending.
    func finishAsking(dayKey: String, facts: WorkoutBanter.Facts, accepted: String?,
                      askedFor: WorkoutBanter.Assigned) -> WorkoutBanter.Assigned? {
        lock.lock(); defer { lock.unlock() }
        asking = false
        let before = loaded()
        let after = WorkoutBanter.applyGenerated(before, dayKey: dayKey, facts: facts, accepted: accepted,
                                                 askedFor: askedFor, currentFacts: latestFacts[dayKey] ?? facts,
                                                 freshLines: latestFreshLines)
        if after != before { save(after) }
        return after.pending.first { $0.dayKey == dayKey }
    }
}
