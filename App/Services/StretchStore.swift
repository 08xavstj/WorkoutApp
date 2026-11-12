import Foundation
import Observation
import AppCore

/// The stretching you've done and how you like it set up (`Stretching` in
/// AppCore), as JSON in Application Support (`SafeJSONFile`).
@Observable
final class StretchStore {
    static let shared = StretchStore()

    private struct Saved: Codable {
        var done: [Stretching.Done] = []
        var focus: [StretchArea] = []
        var remindersOn: Bool = true
        var reminderMinutes: Int = Stretching.defaultReminderMinutes
    }

    /// Entries older than this are dropped (the routine reads the last 7 days;
    /// the rest only tells which stretch variation is next).
    static let keepDays = 60.0

    @ObservationIgnored private let file = SafeJSONFile.appSupport("stretching.json")
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
        saved.done.removeAll { $0.date < cutoff }
        file.saveLogged(saved, canSave: canSave)
    }

    // MARK: Reading

    var done: [Stretching.Done] { saved.done }
    var focus: Set<StretchArea> { Set(saved.focus) }
    var stretchedToday: Bool { Stretching.stretchedToday(saved.done) }
    var weekMinutes: (done: Int, goal: Int) { Stretching.weekMinutes(done: saved.done) }

    var remindersOn: Bool {
        get { saved.remindersOn }
        set { saved.remindersOn = newValue; write() }
    }

    var reminderMinutes: Int {
        get { saved.reminderMinutes }
        set { saved.reminderMinutes = newValue; write() }
    }

    /// Today's routine from the last week's stretching and lifting.
    func routine(lifts: [Stretching.Lift], now: Date = .now) -> Stretching.Routine {
        Stretching.routine(done: saved.done, lifts: lifts, focus: focus, now: now)
    }

    func week(lifts: [Stretching.Lift], now: Date = .now) -> [Stretching.AreaWeek] {
        Stretching.week(done: saved.done, lifts: lifts, focus: focus, now: now)
    }

    /// Finished lifting sessions of the last week as the areas each took
    /// through a long range (`Stretching.areas(forExerciseIDs:)`).
    static func lifts(from sessions: [WorkoutSession], now: Date = .now) -> [Stretching.Lift] {
        let start = now.addingTimeInterval(-Double(Stretching.windowDays) * 86_400)
        return sessions.filter { !$0.isActive && $0.startedAt >= start }.compactMap { session in
            let areas = Stretching.areas(forExerciseIDs: session.exercises.map(\.exerciseID))
            return areas.isEmpty ? nil : Stretching.Lift(date: session.startedAt, areas: areas)
        }
    }

    // MARK: Writing

    func log(_ entries: [Stretching.Done]) {
        guard !entries.isEmpty else { return }
        saved.done += entries
        write()
    }

    func setFocus(_ area: StretchArea, on: Bool) {
        var focus = Set(saved.focus)
        if on { focus.insert(area) } else { focus.remove(area) }
        saved.focus = StretchArea.allCases.filter(focus.contains)
        write()
    }
}
