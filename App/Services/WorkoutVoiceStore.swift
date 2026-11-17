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

    /// Gives each reminder being scheduled its line (`WorkoutBanter.reconcile`) and saves the result.
    func reconcile(_ requests: [WorkoutBanter.DayRequest], tone: WorkoutBanter.Tone, now: Date) -> [String: WorkoutBanter.Assigned] {
        lock.lock(); defer { lock.unlock() }
        let before = loaded()
        let after = WorkoutBanter.reconcile(before, requests: requests, tone: tone, now: now)
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
    /// line when it passed every check. Returns what that reminder holds now,
    /// or nil when it is no longer pending.
    func finishAsking(dayKey: String, facts: WorkoutBanter.Facts, accepted: String?) -> WorkoutBanter.Assigned? {
        lock.lock(); defer { lock.unlock() }
        asking = false
        let before = loaded()
        let after = WorkoutBanter.applyGenerated(before, dayKey: dayKey, facts: facts, accepted: accepted)
        if after != before { save(after) }
        return after.pending.first { $0.dayKey == dayKey }
    }
}
