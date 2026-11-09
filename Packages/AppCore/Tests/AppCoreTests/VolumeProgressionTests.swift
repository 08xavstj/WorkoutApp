import Foundation
import Testing
@testable import AppCore

/// Per-muscle weekly sets through a block (`VolumeProgression`): +1 set per
/// session only when last week was done, at the effort target, with reps kept
/// and the muscle recovered; held otherwise; deload about half; capped at 20
/// and at what the sessions hold.
struct VolumeProgressionTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 2 March 2026, 00:00 UTC.
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))! }

    func week(_ number: Int, length: Int = 5, deload: Bool = false, held: Bool = false) -> TrainingBlock.WeekState {
        TrainingBlock.WeekState(week: number, length: length, setMultiplier: 1, targetRIR: 2, isDeload: deload, isHeld: held)
    }

    let fresh = MuscleRecovery.State(muscle: .chest, recovery: 95, weeklySets: 12, lastTrained: nil)
    let tired = MuscleRecovery.State(muscle: .chest, recovery: 70, weeklySets: 12, lastTrained: nil)
    let good = VolumeProgression.Performance(sets: 12)

    func target(previous: Int?, week: TrainingBlock.WeekState, style: TrainingStyle = .muscle,
                lastWeek: VolumeProgression.Performance?, state: MuscleRecovery.State? = nil,
                sessions: Int = 2, timeCap: Int = 20) -> VolumeProgression.Target {
        VolumeProgression.target(for: .chest, previous: previous, week: week, style: style, lastWeek: lastWeek,
                                 state: state ?? fresh, sessions: sessions, timeCap: timeCap)
    }

    // MARK: The rule, branch by branch

    @Test func rampsTenTwelveFourteenSixteenThenDeloadsToEight() {
        var previous: Int?
        var targets: [Int] = []
        for number in 1...4 {
            let result = target(previous: previous, week: week(number), lastWeek: VolumeProgression.Performance(sets: Double(previous ?? 10)))
            targets.append(result.sets)
            previous = result.sets
        }
        #expect(targets == [10, 12, 14, 16])
        let deload = target(previous: previous, week: week(5, deload: true), lastWeek: good)
        #expect(deload.sets == 8)
        #expect(deload.change == .deload)
        #expect(deload.note == "Chest 8 sets: the planned easier week, about half.")
    }

    @Test func blockStartAndSteadyGoals() {
        #expect(target(previous: 16, week: week(1), lastWeek: good).change == .start)
        #expect(target(previous: nil, week: week(3), lastWeek: good).change == .start)
        #expect(target(previous: nil, week: week(3), lastWeek: good).sets == 10)
        let steady = target(previous: 12, week: week(3), style: .endurance, lastWeek: good)
        #expect(steady.sets == 10)
        #expect(steady.change == .steady)
    }

    @Test func deloadKeepsAtLeastFourSets() {
        #expect(target(previous: 6, week: week(5, deload: true), lastWeek: good).sets == 4)
        #expect(target(previous: nil, week: week(5, deload: true), lastWeek: good).sets == 5)
    }

    @Test func oneSetPerSessionWhenEarned() {
        let twice = target(previous: 12, week: week(3), lastWeek: good, sessions: 2)
        #expect(twice.sets == 14)
        #expect(twice.change == .added)
        #expect(twice.previous == 12)
        #expect(target(previous: 12, week: week(3), lastWeek: good, sessions: 1).sets == 13)
        // Three sessions still add two: the step is capped at about one set per session twice a week.
        #expect(target(previous: 12, week: week(3), lastWeek: good, sessions: 3).sets == 14)
    }

    @Test func holdsForEachReason() {
        let hrv = target(previous: 12, week: week(3, held: true), lastWeek: good)
        #expect(hrv.sets == 12)
        #expect(hrv.change == .heldHRV)

        #expect(target(previous: 12, week: week(3), lastWeek: nil).change == .heldNotTrained)
        #expect(target(previous: 12, week: week(3), lastWeek: VolumeProgression.Performance(sets: 0.2)).change == .heldNotTrained)

        let missed = target(previous: 12, week: week(3), lastWeek: VolumeProgression.Performance(sets: 10))
        #expect(missed.change == .heldMissedSets(done: 10, target: 12))
        #expect(missed.note == "Chest held at 12 sets: 10 of 12 done last week.")
        // One set short is within the tolerance.
        #expect(target(previous: 12, week: week(3), lastWeek: VolumeProgression.Performance(sets: 11)).change == .added)
        let unfinished = VolumeProgression.Performance(sets: 12, allCompleted: false)
        #expect(target(previous: 12, week: week(3), lastWeek: unfinished).change == .heldMissedSets(done: 12, target: 12))

        let reps = target(previous: 14, week: week(4), lastWeek: VolumeProgression.Performance(sets: 14, repsDropped: ["Bench Press"]))
        #expect(reps.sets == 14)
        #expect(reps.note == "Chest held at 14 sets: reps dropped on Bench Press last week.")

        let hard = target(previous: 14, week: week(4), lastWeek: VolumeProgression.Performance(sets: 14, overEffort: ["Cable Fly"]))
        #expect(hard.change == .heldTooHard(exercise: "Cable Fly"))

        let recovering = target(previous: 14, week: week(4), lastWeek: VolumeProgression.Performance(sets: 14), state: tired)
        #expect(recovering.change == .heldNotRecovered)
        #expect(recovering.change.isHeld)
        #expect(!VolumeProgression.Change.added.isHeld)
    }

    @Test func capsAtTwentyTheGoalAndTheSessions() {
        let top = target(previous: 20, week: week(5, length: 6), lastWeek: VolumeProgression.Performance(sets: 20))
        #expect(top.sets == 20)
        #expect(top.change == .cappedCeiling)
        // Strength and balanced goals stop at 16.
        let balanced = target(previous: 16, week: week(4), style: .balanced, lastWeek: VolumeProgression.Performance(sets: 16))
        #expect(balanced.sets == 16)
        #expect(balanced.change == .cappedCeiling)
        // The sessions only hold 13.
        let time = target(previous: 12, week: week(3), lastWeek: good, timeCap: 13)
        #expect(time.sets == 13)
        #expect(time.change == .cappedTime)
        // A shorter plan pulls an old target down, even on a hold.
        #expect(target(previous: 16, week: week(4), lastWeek: nil, timeCap: 10).sets == 10)
        #expect(VolumeProgression.Target(muscle: .chest, sets: 14, previous: 12, change: .added).bandText == "12-14 sets")
        #expect(VolumeProgression.Target(muscle: .chest, sets: 4, previous: 8, change: .deload).band == 4...4)
    }

    // MARK: Last week from logged sets

    func set(_ exercise: String, day: Int, order: Int, weight: Double = 60, reps: Int = 8, rpe: Double? = 8,
             completed: Bool = true, primary: [Muscle] = [.chest], secondary: [Muscle] = [],
             compound: Bool = true, group: Int? = nil) -> VolumeProgression.LoggedSet {
        VolumeProgression.LoggedSet(
            exerciseID: exercise, name: exercise, sessionStart: monday.addingTimeInterval(Double(day) * 86_400 + 3600 * 18),
            order: order, primary: primary, secondary: secondary, weightKg: weight, reps: reps, rpe: rpe,
            isCompleted: completed, isCompound: compound, supersetGroup: group)
    }

    @Test func summarizesSetsEffortAndCompletion() {
        let sets = [
            set("Bench", day: 0, order: 0, secondary: [.triceps]),
            set("Bench", day: 0, order: 1, secondary: [.triceps]),
            set("Bench", day: 0, order: 2, rpe: 6, secondary: [.triceps]),   // easy: 0.6
            set("Bench", day: 0, order: 3, completed: false),
            set("Bench", day: 9, order: 0),                                   // next week: ignored
        ]
        let result = VolumeProgression.summarize(sets, weekStart: monday, targetRPE: 8, style: .muscle, calendar: calendar)
        #expect(result[.chest]?.sets == 2.6)
        #expect(result[.triceps]?.sets == 1.3)
        #expect(result[.chest]?.allCompleted == false)
        #expect(result[.triceps]?.allCompleted == true)
        #expect(result[.chest]?.overEffort == [])
    }

    @Test func effortCeilingFollowsThePlannersOffsets() {
        #expect(VolumeProgression.effortCeiling(targetRPE: 8, compound: true, style: .muscle) == 8.5)
        #expect(VolumeProgression.effortCeiling(targetRPE: 8, compound: false, style: .muscle) == 10)
        #expect(VolumeProgression.effortCeiling(targetRPE: 8, compound: false, style: .balanced) == 9.5)
        #expect(VolumeProgression.effortCeiling(targetRPE: 7, compound: false, style: .strength) == 8)
        let sets = [
            set("Bench", day: 1, order: 0, rpe: 9),                                    // compound, over 8.5
            set("Fly", day: 1, order: 0, rpe: 9.5, compound: false),                   // isolation, under 10
        ]
        let result = VolumeProgression.summarize(sets, weekStart: monday, targetRPE: 8, style: .muscle, calendar: calendar)
        #expect(result[.chest]?.overEffort == ["Bench"])
    }

    @Test func seesRepsFallAgainstTheSessionBefore() {
        let sets = [
            set("Row", day: -4, order: 0, weight: 60, reps: 10, primary: [.lats]),     // the week before
            set("Row", day: 2, order: 0, weight: 60, reps: 8, primary: [.lats]),       // same weight, fewer reps
            set("Squat", day: -4, order: 0, weight: 100, reps: 8, primary: [.quadriceps]),
            set("Squat", day: 2, order: 0, weight: 110, reps: 6, primary: [.quadriceps]), // heavier: compared, fell
            set("Curl", day: -4, order: 0, weight: 20, reps: 10, primary: [.biceps]),
            set("Curl", day: 2, order: 0, weight: 15, reps: 8, primary: [.biceps]),    // lighter: not compared
            set("Press", day: 1, order: 0, weight: 40, reps: 8, primary: [.shoulders]),
            set("Press", day: 3, order: 0, weight: 40, reps: 9, primary: [.shoulders]), // went up
        ]
        let result = VolumeProgression.summarize(sets, weekStart: monday, targetRPE: 8, style: .balanced, calendar: calendar)
        #expect(result[.lats]?.repsDropped == ["Row"])
        #expect(result[.quadriceps]?.repsDropped == ["Squat"])
        #expect(result[.biceps]?.repsDropped == [])
        #expect(result[.shoulders]?.repsDropped == [])
        let lastWeek = VolumeProgression.Performance(sets: 14, repsDropped: result[.lats]?.repsDropped ?? [])
        let next = VolumeProgression.target(for: .lats, previous: 14, week: week(3), style: .muscle, lastWeek: lastWeek,
                                            state: nil, sessions: 2, timeCap: 20)
        #expect(next.note == "Lats held at 14 sets: reps dropped on Row last week.")
    }

    @Test func supersetRoundsCountOncePerMuscle() {
        // Lateral raise paired with a rear-delt fly: both are "shoulders" here.
        let sets = [
            set("Raise", day: 1, order: 0, primary: [.shoulders], compound: false, group: 1),
            set("Rear", day: 1, order: 0, primary: [.shoulders], secondary: [.middleBack], compound: false, group: 1),
            set("Raise", day: 1, order: 1, primary: [.shoulders], compound: false, group: 1),
            set("Rear", day: 1, order: 1, primary: [.shoulders], secondary: [.middleBack], compound: false, group: 1),
        ]
        let result = VolumeProgression.summarize(sets, weekStart: monday, targetRPE: 8, style: .muscle, calendar: calendar)
        #expect(result[.shoulders]?.sets == 2)
        #expect(result[.middleBack]?.sets == 1)

        let raise = PlannedExercise(exerciseID: "Side_Lateral_Raise", name: "Lateral Raise", sets: 3, reps: 10...12, rpe: 9,
                                    load: nil, loadKind: .dumbbell, note: nil, supersetGroup: 1)
        let rear = PlannedExercise(exerciseID: "Reverse_Flyes", name: "Reverse Fly", sets: 3, reps: 10...12, rpe: 9,
                                   load: nil, loadKind: .dumbbell, note: nil, supersetGroup: 1)
        let press = PlannedExercise(exerciseID: "Dumbbell_Shoulder_Press", name: "Shoulder Press", sets: 4, reps: 6...8, rpe: 8,
                                    load: nil, loadKind: .dumbbell, note: nil)
        #expect(VolumeProgression.directSets([raise, rear, press])[.shoulders] == 7)
    }

    // MARK: The week and today's session

    let upperLower = [
        PlannedDay(weekday: 2, time: 1080, focus: .upper, minutes: 60),
        PlannedDay(weekday: 3, time: 1080, focus: .lower, minutes: 60),
        PlannedDay(weekday: 5, time: 1080, focus: .push, minutes: 60),
        PlannedDay(weekday: 6, time: 1080, focus: .lower, minutes: 30),
    ]

    @Test func capacityCountsDirectMovementsAndTime() {
        // Upper has one chest movement (5 sets at most); push has three (10 in an hour).
        let chest = VolumeProgression.capacity(.chest, days: upperLower)
        #expect(chest.sessions == 2)
        #expect(chest.timeCap == 15)
        // Lower 60: squat and single-leg (10); lower 30 keeps both in its four movements but holds 6.
        let quads = VolumeProgression.capacity(.quadriceps, days: upperLower)
        #expect(quads.sessions == 2)
        #expect(quads.timeCap == 16)
        #expect(VolumeProgression.capacity(.calves, days: [upperLower[3]]).sessions == 0)
    }

    @Test func buildsTheWeekFromLastWeek() {
        let previous = VolumeProgression.WeekTargets(weekStart: monday, targetRIR: 3, targets: [
            VolumeProgression.Target(muscle: .chest, sets: 12, previous: 10, change: .added),
            VolumeProgression.Target(muscle: .lats, sets: 10, previous: 10, change: .start),
        ])
        let lastWeek: [Muscle: VolumeProgression.Performance] = [
            .chest: VolumeProgression.Performance(sets: 12),
            .lats: VolumeProgression.Performance(sets: 10, repsDropped: ["Row"]),
        ]
        let block = TrainingBlock.weekState(3, style: .muscle, length: 6)
        let next = VolumeProgression.week(weekStart: monday.addingTimeInterval(7 * 86_400), block: block, style: .muscle,
                                          days: upperLower, previous: previous, lastWeek: lastWeek, states: [:])
        #expect(next.target(for: .chest)?.sets == 14)
        // Lats: only the upper day trains them (two movements, 10 sets at most).
        #expect(next.target(for: .lats)?.sets == 10)
        #expect(next.target(for: .lats)?.change == .heldRepsDropped(exercise: "Row"))
        // Hamstrings: no earlier target, so the block's start value.
        #expect(next.target(for: .hamstrings)?.change == .start)
        #expect(next.target(for: .hamstrings)?.sets == 10)
        // Calves: one movement on one day holds 5.
        #expect(next.target(for: .calves)?.sets == 5)
        #expect(next.target(for: .calves)?.change == .cappedTime)
        #expect(next.targetRIR == block.targetRIR)
        #expect(next.sets[.chest] == 14)
        #expect(next.notable.map(\.muscle).contains(.lats))
        #expect(!next.notable.map(\.muscle).contains(.hamstrings))
        // Every tracked muscle the plan trains directly, none it doesn't.
        #expect(next.targets.allSatisfy { MuscleCoverage.tracked.contains($0.muscle) })
    }

    @Test func sharesWhatTheWeekOwesOverTheSessionsLeft() {
        let targets = VolumeProgression.WeekTargets(weekStart: monday, targetRIR: 2, targets: [
            VolumeProgression.Target(muscle: .chest, sets: 14, previous: 12, change: .added),
            VolumeProgression.Target(muscle: .lats, sets: 12, previous: 12, change: .heldNotRecovered),
        ])
        let goals = VolumeProgression.sessionGoals(targets: targets, doneThisWeek: [.chest: 4], focus: .push, minutes: 60,
                                                   laterSessions: [PlannedDay(weekday: 6, time: 1080, focus: .upper, minutes: 60)])
        #expect(goals[.chest] == 5)   // (14 - 4) / 2
        #expect(goals[.lats] == nil)  // push has no lat movement
        let done = VolumeProgression.sessionGoals(targets: targets, doneThisWeek: [.chest: 15], focus: .push, minutes: 60, laterSessions: [])
        #expect(done[.chest] == 0)
        let short = VolumeProgression.sessionGoals(targets: targets, doneThisWeek: [:], focus: .push, minutes: 30, laterSessions: [])
        #expect(short[.chest] == 6)   // capped by a 30-minute session
    }

    @Test func plannerFollowsTheSessionGoals() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        let free = planner.plan(focus: .push, minutes: 60, recovery: 80, history: [:])
        let steered = planner.plan(focus: .push, minutes: 60, recovery: 80, history: [:], muscleSetGoals: [.chest: 4, .triceps: 2])
        // Four chest sets over the chest movements: compound presses keep 3 sets
        // (`minimumCompoundSets`), isolation 2. The goals fit in far less than the hour, so
        // `fill`'s second pass adds sets past them (up to `VolumeProgression.sessionCap` a muscle)
        // and says so, instead of leaving a short session (a user's 75-min plan took 42.5).
        let chestMoves = steered.exercises.filter { VolumeProgression.primaryMuscle($0) == .chest }
        #expect(!chestMoves.isEmpty)
        #expect(chestMoves.allSatisfy { $0.sets >= (ExerciseCatalog.slot(for: $0.exerciseID)?.isCompound == true ? 3 : 2) })
        let direct = VolumeProgression.directSets(steered.exercises)
        #expect(direct.values.allSatisfy { $0 <= VolumeProgression.sessionCap(minutes: 60) })
        #expect((steered.estimatedMinutes ?? 0) <= 60)
        #expect(Double(steered.estimatedMinutes ?? 0) >= 0.85 * 60)
        // Past the goals only a few sets a muscle (`setsPastGoal`), so this one runs a little short and says so.
        #expect(steered.lengthNote?.contains("extra sets") == true || steered.lengthNote?.contains("every set") == true)
        // No goals: exactly the old plan.
        #expect(planner.plan(focus: .push, minutes: 60, recovery: 80, history: [:], muscleSetGoals: [:]) == free)
    }

    @Test func applySetGoalsSharesInSessionOrder() {
        func ex(_ id: String, _ sets: Int) -> PlannedExercise {
            PlannedExercise(exerciseID: id, name: id, sets: sets, reps: 8...10, rpe: 8, load: nil, loadKind: nil, note: nil)
        }
        var list = [ex("Barbell_Bench_Press_-_Medium_Grip", 3), ex("Incline_Dumbbell_Press", 3), ex("Cable_Crossover", 3), ex("Side_Lateral_Raise", 3)]
        WorkoutPlanner.applySetGoals(&list, goals: [.chest: 8])
        #expect(list.map(\.sets) == [3, 3, 2, 3])
        WorkoutPlanner.applySetGoals(&list, goals: [.chest: 20])
        #expect(list.map(\.sets) == [5, 5, 5, 3])
        // A met goal leaves isolation at 2 and compound presses at 3 (`minimumCompoundSets`); 2 in a deload.
        WorkoutPlanner.applySetGoals(&list, goals: [.chest: 0])
        #expect(list.map(\.sets) == [3, 3, 2, 3])
        WorkoutPlanner.applySetGoals(&list, goals: [.chest: 0], deload: true)
        #expect(list.map(\.sets) == [2, 2, 2, 3])
    }

    @Test func targetsSurviveSaving() throws {
        let targets = VolumeProgression.WeekTargets(weekStart: monday, targetRIR: 2, targets: [
            VolumeProgression.Target(muscle: .middleBack, sets: 12, previous: 12, change: .heldMissedSets(done: 9.5, target: 12)),
            VolumeProgression.Target(muscle: .chest, sets: 14, previous: 12, change: .added),
        ])
        let data = try JSONEncoder().encode(targets)
        #expect(try JSONDecoder().decode(VolumeProgression.WeekTargets.self, from: data) == targets)
    }
}
