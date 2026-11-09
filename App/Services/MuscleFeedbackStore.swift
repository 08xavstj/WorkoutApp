import Foundation
import Observation
import AppCore

/// Your optional per-muscle answers after each session (`MuscleFeedback`:
/// pump, soreness from last time, joint pain), keyed by the session's start,
/// as JSON in Application Support (`SafeJSONFile`). `WorkoutSession` has no
/// field for them (that needs a schema migration). Kept `keepDays`; the
/// weekly set targets read last week's (`WeeklyPlanStore.volumeTargets`).
@Observable
final class MuscleFeedbackStore {
    static let shared = MuscleFeedbackStore()

    private struct Saved: Codable {
        var entries: [MuscleFeedback.Entry] = []
        /// Sessions whose card you skipped.
        var skipped: [Date] = []
    }

    /// Answers older than this are dropped (app choice: the rule reads last week's).
    static let keepDays = 60.0

    @ObservationIgnored private let file = SafeJSONFile.appSupport("musclefeedback.json")
    /// False after a read that failed (phone locked): nothing is saved until a read works.
    @ObservationIgnored private var canSave = false
    private var saved = Saved()

    init() {
        reload()
    }

    /// Reads again if the last read couldn't (the app calls this on unlock and foreground).
    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        let loaded = file.loadLogged(Saved.self)
        canSave = loaded.state.canSave
        if canSave { saved = loaded.value ?? Saved() }
    }

    private func write() {
        let cutoff = Date.now.addingTimeInterval(-Self.keepDays * 86_400)
        saved.entries.removeAll { $0.sessionStart < cutoff || $0.isEmpty }
        saved.skipped.removeAll { $0 < cutoff }
        file.saveLogged(saved, canSave: canSave)
    }

    private static func same(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 1 }

    // MARK: Reading

    func entry(for sessionStart: Date, muscle: Muscle) -> MuscleFeedback.Entry? {
        saved.entries.first { Self.same($0.sessionStart, sessionStart) && $0.muscle == muscle }
    }

    func hasAnswers(for sessionStart: Date) -> Bool {
        saved.entries.contains { Self.same($0.sessionStart, sessionStart) && !$0.isEmpty }
    }

    func isSkipped(_ sessionStart: Date) -> Bool {
        saved.skipped.contains { Self.same($0, sessionStart) }
    }

    /// Each muscle's answers from the week starting `weekStart` (`MuscleFeedback.signals`).
    func signals(sets: [VolumeProgression.LoggedSet], weekStart: Date) -> [Muscle: MuscleFeedback.Signal] {
        MuscleFeedback.signals(saved.entries, sets: sets, weekStart: weekStart)
    }

    // MARK: Changing

    /// Changes one muscle's answers for a session; an answer tapped again clears it.
    func update(sessionStart: Date, muscle: Muscle, _ change: (inout MuscleFeedback.Entry) -> Void) {
        reloadIfUnavailable()
        var entry = self.entry(for: sessionStart, muscle: muscle) ?? MuscleFeedback.Entry(sessionStart: sessionStart, muscle: muscle)
        change(&entry)
        saved.entries.removeAll { Self.same($0.sessionStart, sessionStart) && $0.muscle == muscle }
        if !entry.isEmpty { saved.entries.append(entry) }
        write()
    }

    /// Hides the card for a session (its answers stay).
    func skip(_ sessionStart: Date) {
        reloadIfUnavailable()
        guard !isSkipped(sessionStart) else { return }
        saved.skipped.append(sessionStart)
        write()
    }

    /// Shows the card again for a session you skipped.
    func unskip(_ sessionStart: Date) {
        reloadIfUnavailable()
        saved.skipped.removeAll { Self.same($0, sessionStart) }
        write()
    }
}
