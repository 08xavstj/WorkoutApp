import Foundation
import Observation
import AppCore

/// The end-of-block report's suggestions you applied to the next block
/// (`NextBlockAdjustments`), as JSON in Application Support (`SafeJSONFile`).
/// The planner (`GymStore.planner`: rep ranges, variation swaps) and the
/// weekly set targets (`WeeklyPlanStore.volumeTargets`: sets added, "same
/// volume") read it; it ends with the block it was applied to (`observe`).
@Observable
final class NextBlockStore {
    static let shared = NextBlockStore()

    private struct Saved: Codable {
        var current: NextBlockAdjustments? = nil
    }

    @ObservationIgnored private let file = SafeJSONFile.appSupport("nextblock.json")
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
        file.saveLogged(saved, canSave: canSave)
    }

    // MARK: Reading

    /// What the weekly targets use, an undo's one-off take-back included.
    var current: NextBlockAdjustments? { saved.current }

    /// The changes you applied and haven't undone.
    var applied: NextBlockAdjustments? {
        guard let current = saved.current, !current.isUndo else { return nil }
        return current
    }

    /// Rep ranges and variation swaps for `WorkoutPlanner.blockPreferences`.
    var plannerPreferences: WorkoutPlanner.BlockPreferences? { applied?.plannerPreferences }

    /// True when the report of the block that started on `sourceStart` is applied.
    func isApplied(from sourceStart: Date) -> Bool {
        guard let applied else { return false }
        return Calendar.current.isDate(applied.sourceStart, inSameDayAs: sourceStart)
    }

    /// This week's part for the set targets, for the block that started on `blockStart`.
    func volume(blockStart: Date, weekStart: Date) -> VolumeProgression.Adjustment? {
        guard let current = saved.current, current.applies(toBlockStarting: blockStart) else { return nil }
        return current.volume(weekStart: weekStart)
    }

    // MARK: Changing

    /// Saves the chosen changes (nothing chosen clears them). The caller has
    /// this week's set targets worked out again (`WeeklyPlanStore.redoVolume`).
    func apply(_ value: NextBlockAdjustments) {
        reloadIfUnavailable()
        saved.current = value.isEmpty ? nil : value
        write()
    }

    /// Takes the applied changes back. Sets already built into an earlier
    /// week's targets come off once (`NextBlockAdjustments.undone`); the
    /// caller has this week's targets worked out again.
    func undo(thisWeek: Date) {
        reloadIfUnavailable()
        guard let applied else { return }
        saved.current = applied.undone(thisWeek: thisWeek)
        write()
    }

    /// Called once this week's targets are saved: the offsets now live in
    /// them, so later weeks build on them instead of adding them again. A
    /// spent undo record goes.
    func markOffsetsApplied(blockStart: Date, weekStart: Date) {
        guard let current = saved.current, current.applies(toBlockStarting: blockStart), current.offsetsWeek == nil,
              let volume = current.volume(weekStart: weekStart), !volume.offsets.isEmpty else { return }
        saved.current = current.isUndo ? nil : current.markingOffsets(weekStart: weekStart)
        write()
    }

    /// Ends the changes once the block they were applied to has been
    /// replaced by a new one. Call from a task (it may write).
    func observe(blockStart: Date?) {
        guard let blockStart, let current = saved.current, !current.applies(toBlockStarting: blockStart) else { return }
        saved.current = nil
        write()
    }
}
