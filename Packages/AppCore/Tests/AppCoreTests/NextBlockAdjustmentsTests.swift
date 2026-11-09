import Foundation
import Testing
@testable import AppCore

/// The block report's suggestions applied to the next block
/// (`NextBlockAdjustments`): set offsets once, "same volume" caps, rep ranges
/// and variation swaps in the planner, inside the gym and pain rules.
struct NextBlockAdjustmentsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 2 March 2026, 00:00 UTC.
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))! }
    func weeks(_ count: Int) -> Date { calendar.date(byAdding: .day, value: 7 * count, to: monday)! }

    let benchID = "Barbell_Bench_Press_-_Medium_Grip"
    let dumbbellBenchID = "Dumbbell_Bench_Press"
    let rowID = "Bent_Over_Barbell_Row"

    func report(_ next: [BlockReport.NextChange]) -> BlockReport.Report {
        let lift = BlockReport.LiftChange(exerciseID: benchID, name: "Bench Press", isBodyweight: false, start: 100, end: 100,
                                          change: 0, points: [], isStalled: true)
        let row = BlockReport.LiftChange(exerciseID: rowID, name: "Barbell Row", isBodyweight: false, start: 80, end: 80,
                                         change: 0, points: [], isStalled: true)
        return BlockReport.Report(number: 3, start: weeks(-5), end: monday, weeksRun: 5, hadDeload: true, sessionsDone: 15,
                                  sessionsPlanned: 15, weeksKept: 5, weeksPlanned: 5, volumeKg: 1, volumeChange: nil,
                                  lifts: [lift, row], records: [], muscles: [], bodyWeight: nil, hrv: nil, next: next)
    }

    var changes: [BlockReport.NextChange] {
        [
            BlockReport.NextChange(kind: .addSets(.chest, sets: 2), text: "Chest +2", why: ""),
            BlockReport.NextChange(kind: .repRange(exerciseID: rowID, reps: 8...12), text: "Row 8-12", why: ""),
            BlockReport.NextChange(kind: .swapExercise(fromID: benchID, toID: dumbbellBenchID, toName: "Dumbbell Bench Press"),
                                   text: "Swap bench", why: ""),
            BlockReport.NextChange(kind: .holdVolume, text: "Same volume", why: "")
        ]
    }

    func applied(_ chosen: Set<String>) -> NextBlockAdjustments {
        NextBlockAdjustments.make(report: report(changes), chosen: chosen, sourceStart: weeks(-5), blockStart: monday,
                                  finishedTargets: [[.chest: 12, .lats: 10], [.chest: 16, .lats: 14]], now: monday)
    }

    // MARK: Making

    @Test func onlyChosenSuggestionsAreApplied() {
        let all = applied(Set(changes.map(\.id)))
        #expect(all.setOffsets == ["chest": 2])
        #expect(all.repRanges == [NextBlockAdjustments.RepRange(exerciseID: rowID, name: "Barbell Row", reps: 8...12)])
        #expect(all.swaps.first?.fromName == "Bench Press")
        #expect(all.holdVolume)
        #expect(all.holdCeilings == ["chest": 16, "lats": 14])
        #expect(all.label == "Block 3 report")
        #expect(all.summaryLines.contains("Chest +2 sets a week"))

        let none = applied([])
        #expect(none.isEmpty)
        let swapOnly = applied(["Swap bench"])
        #expect(swapOnly.setOffsets.isEmpty && !swapOnly.holdVolume && swapOnly.repRanges.isEmpty && swapOnly.swaps.count == 1)
    }

    @Test func appliesOnlyToItsBlock() {
        let value = applied(["Chest +2"])
        #expect(value.applies(toBlockStarting: monday.addingTimeInterval(3_600), calendar: calendar))
        #expect(!value.applies(toBlockStarting: weeks(5), calendar: calendar))
    }

    // MARK: Volume

    @Test func offsetsArePendingUntilAWeekTakesThem() {
        let value = applied(["Chest +2"])
        #expect(value.volume(weekStart: monday, calendar: calendar)?.offsets == [.chest: 2])
        let marked = value.markingOffsets(weekStart: monday)
        // The same week can be worked out again with them; later weeks build on it instead.
        #expect(marked.volume(weekStart: monday, calendar: calendar)?.offsets == [.chest: 2])
        #expect(marked.volume(weekStart: weeks(1), calendar: calendar) == nil)
        #expect(marked.markingOffsets(weekStart: weeks(1)).offsetsWeek == monday)
    }

    @Test func startingWeekGetsTheOffsetInsideCaps() {
        let block = TrainingBlock.WeekState(week: 1, length: 5, setMultiplier: 1, targetRIR: 3, isDeload: false)
        let up = VolumeProgression.target(for: .chest, previous: nil, week: block, style: .muscle, lastWeek: nil, state: nil,
                                          sessions: 2, timeCap: 20, recent: 12, offset: 2)
        #expect(up.sets == 14)
        #expect(up.change == .fromReport(offset: 2))
        #expect(up.note == "Chest 14 sets: +2 from the block report.")
        // The week's time still caps it.
        let capped = VolumeProgression.target(for: .chest, previous: nil, week: block, style: .muscle, lastWeek: nil, state: nil,
                                              sessions: 2, timeCap: 11, recent: 10, offset: 2)
        #expect(capped.sets == 11)
        // Never on a deload or a stamina goal's steady weeks.
        let deload = TrainingBlock.WeekState(week: 5, length: 5, setMultiplier: 0.5, targetRIR: 3, isDeload: true)
        #expect(VolumeProgression.target(for: .chest, previous: 16, week: deload, style: .muscle, lastWeek: nil, state: nil,
                                         sessions: 2, timeCap: 20, offset: 2).change == .deload)
        #expect(VolumeProgression.target(for: .chest, previous: 10, week: block, style: .endurance, lastWeek: nil, state: nil,
                                         sessions: 2, timeCap: 20, offset: 2).sets == 10)
    }

    @Test func sameVolumeCapsAtLastBlocksPeak() {
        let value = applied(["Same volume"])
        let adjustment = value.volume(weekStart: weeks(2), calendar: calendar)
        #expect(adjustment?.ceilings[.chest] == 16)
        let block = TrainingBlock.WeekState(week: 3, length: 5, setMultiplier: 1, targetRIR: 2, isDeload: false)
        let fresh = MuscleRecovery.State(muscle: .chest, recovery: 95, weeklySets: 16, lastTrained: nil)
        let held = VolumeProgression.target(for: .chest, previous: 16, week: block, style: .muscle,
                                            lastWeek: VolumeProgression.Performance(sets: 16), state: fresh, sessions: 2,
                                            timeCap: 20, reportCeiling: adjustment?.ceilings[.chest])
        #expect(held.sets == 16)
        #expect(held.change == .heldReport)
        #expect(held.change.isHeld && held.change.isFromReport)
        // With sets added for the muscle too, its cap moves up by them.
        let both = applied(["Same volume", "Chest +2"])
        #expect(both.volume(weekStart: monday, calendar: calendar)?.ceilings[.chest] == 18)
    }

    @Test func weekUsesTheAdjustment() {
        let days = [PlannedDay(weekday: 2, time: 1080, focus: .push, minutes: 60), PlannedDay(weekday: 5, time: 1080, focus: .push, minutes: 60)]
        let block = TrainingBlock.WeekState(week: 1, length: 5, setMultiplier: 1, targetRIR: 3, isDeload: false)
        let plain = VolumeProgression.week(weekStart: monday, block: block, style: .muscle, days: days, previous: nil,
                                           lastWeek: [:], states: [:])
        let adjusted = VolumeProgression.week(weekStart: monday, block: block, style: .muscle, days: days, previous: nil,
                                              lastWeek: [:], states: [:],
                                              adjustment: VolumeProgression.Adjustment(offsets: [.chest: 2]))
        let before = plain.target(for: .chest)?.sets ?? 0
        #expect(before > 0)
        #expect(adjusted.target(for: .chest)?.sets == before + 2)
        #expect(adjusted.target(for: .triceps)?.sets == plain.target(for: .triceps)?.sets)
    }

    @Test func undoAfterAWeekTookTheOffsetsTakesThemBackOnce() {
        let value = applied(["Chest +2", "Swap bench"]).markingOffsets(weekStart: monday)
        // Same week: nothing left, the week is worked out again.
        #expect(value.undone(thisWeek: monday, calendar: calendar) == nil)
        let reversal = value.undone(thisWeek: weeks(2), calendar: calendar)
        #expect(reversal?.isUndo == true)
        #expect(reversal?.volume(weekStart: weeks(2), calendar: calendar)?.offsets == [.chest: -2])
        #expect(reversal?.plannerPreferences == nil)
        #expect(reversal?.summaryLines.isEmpty == true)
        // Before any week took them: nothing to take back.
        #expect(applied(["Chest +2"]).undone(thisWeek: weeks(2), calendar: calendar) == nil)
    }

    @Test func codableRoundTrip() throws {
        let value = applied(Set(changes.map(\.id))).markingOffsets(weekStart: monday)
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(NextBlockAdjustments.self, from: data) == value)
    }

    // MARK: Planner

    func planner(_ preferences: WorkoutPlanner.BlockPreferences?, filter: ExerciseFilter? = nil) -> WorkoutPlanner {
        var planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        planner.blockPreferences = preferences
        planner.exerciseFilter = filter
        return planner
    }

    @Test func repRangeOverrideAndNote() {
        let preferences = applied(["Row 8-12"]).plannerPreferences
        let choice = ExerciseCatalog.exercise(id: rowID)!
        let planned = planner(preferences).prescribe(choice, slot: .horizontalRow, minutes: 60, sessionRPE: 8, history: [:])
        #expect(planned.reps == 8...12)
        #expect(planned.adjustmentNote == "8-12 reps: applied from the Block 3 report")
        let plain = planner(nil).prescribe(choice, slot: .horizontalRow, minutes: 60, sessionRPE: 8, history: [:])
        #expect(plain.reps == 6...10)
        #expect(plain.adjustmentNote == nil)
    }

    @Test func swapIsPreferredOverTheStalledLift() {
        let preferences = applied(["Swap bench"]).plannerPreferences
        let history = [benchID: ExerciseHistory(bestEstimatedOneRepMax: 120, lastWeight: 100, lastReps: 5, lastRPE: 8, lastDate: monday)]
        // Without it, the logged bench wins.
        #expect(planner(nil).choose(.horizontalPress, excluding: [], history: history)?.id == benchID)
        let swapped = planner(preferences)
        #expect(swapped.choose(.horizontalPress, excluding: [], history: history)?.id == dumbbellBenchID)
        #expect(swapped.choose(.horizontalPress)?.id == dumbbellBenchID)
        let options = swapped.alternatives(for: .horizontalPress).map(\.id)
        #expect(options.firstIndex(of: dumbbellBenchID)! < options.firstIndex(of: benchID)!)
        let planned = swapped.prescribe(ExerciseCatalog.exercise(id: dumbbellBenchID)!, slot: .horizontalPress, minutes: 60,
                                        sessionRPE: 8, history: [:])
        #expect(planned.adjustmentNote == "In place of Bench Press: applied from the Block 3 report")
    }

    @Test func swapRespectsGymAndNeverAgain() {
        let preferences = applied(["Swap bench"]).plannerPreferences
        // Never again: the swap target isn't offered, the stalled lift stays.
        let filtered = planner(preferences, filter: ExerciseFilter(neverAgain: [dumbbellBenchID]))
        #expect(filtered.choose(.horizontalPress)?.id == benchID)
        // A gym without dumbbells: same.
        var gym = GymProfile.commercialKilograms
        gym.equipment.remove(.dumbbell)
        var noDumbbells = WorkoutPlanner(gym: gym, style: .muscle)
        noDumbbells.blockPreferences = preferences
        #expect(noDumbbells.alternatives(for: .horizontalPress).allSatisfy { $0.id != dumbbellBenchID })
        #expect(noDumbbells.choose(.horizontalPress)?.id == benchID)
    }

    @Test func undoRecordHasNoPlannerChanges() {
        #expect(applied(["Chest +2"]).plannerPreferences == nil)
        #expect(applied(["Same volume"]).volume(weekStart: monday, calendar: calendar)?.offsets.isEmpty == true)
    }
}
