import Foundation
import Testing
@testable import AppCore

/// The November 2026 workout audit (docs/research/workout-audit-2026-11.md):
/// one check per fixed finding, for the user who kept getting light, short,
/// abs-free sessions (85 kg man, commercial kg gym, lose fat + muscle + strength).
struct PlannerAuditFixTests {
    let kg = GymProfile.commercialKilograms
    let monday = Date(timeIntervalSince1970: 1_767_571_200) // Mon 5 Jan 2026, 00:00 UTC
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    // §3: muscle + strength gets heavy main lifts.
    @Test func muscleAndStrengthGetsAHeavyFirstLift() {
        #expect(GoalPlanner.trainingStyle(Goals(focuses: [.muscle, .strength])) == .strengthAndMuscle)
        #expect(GoalPlanner.trainingStyle(Goals(weight: .lose, focuses: [.muscle, .strength])) == .strengthAndMuscle)
        #expect(GoalPlanner.trainingStyle(Goals(focuses: [.muscle])) == .muscle)
        let planner = WorkoutPlanner(gym: kg, style: .strengthAndMuscle)
        let plan = planner.plan(focus: .upper, minutes: 60, recovery: 70, history: [:], bodyMassKg: 85,
                                trainingStatus: .intermediate, includeCore: false)
        let first = plan.exercises[0]
        #expect(first.reps == 4...6)
        #expect(first.restSeconds == RestTimer.heavyLiftSeconds)
        // Other big lifts 6-10, small lifts 8-12 (not 15).
        #expect(plan.exercises[1].reps == 6...10)
        let small = plan.exercises.filter { ExerciseCatalog.slot(for: $0.exerciseID)?.isCompound == false }
        #expect(!small.isEmpty)
        #expect(small.allSatisfy { $0.reps.upperBound <= 12 })
        #expect(TrainingStyle.muscle.defaultReps(compound: false) == 8...12)
        #expect(TrainingBlock.length(for: .strengthAndMuscle) == 6)
    }

    // §1: the worked example's lifter gets a real working weight first time.
    @Test func theAuditLifterStartsNearAWorkingWeight() {
        let planner = WorkoutPlanner(gym: kg, style: .strengthAndMuscle)
        let plan = planner.plan(focus: .upper, minutes: 60, recovery: 70, history: [:],
                                block: TrainingBlock.weekState(1, style: .strengthAndMuscle, length: 6),
                                bodyMassKg: 85, trainingStatus: .intermediate, includeCore: false)
        let bench = plan.exercises.first { $0.exerciseID == "Barbell_Bench_Press_-_Medium_Grip" }
        // Was 32.5 kg × 10 (about 44% of realistic). A ~110 kg bencher's heavy set of 5 is 80-90 kg;
        // the start is a cautious estimate under that, not half of it.
        #expect((65...90).contains(bench?.load ?? 0), "bench \(bench?.load ?? 0)")
        #expect(bench?.targetReps == 5)
        // Small lifts get a number too, not "pick a weight".
        #expect(plan.exercises.filter { $0.loadKind != nil }.allSatisfy { $0.load != nil })
    }

    // §2: a session far easier than planned catches up fast.
    @Test func aVeryEasyFirstSessionCatchesUp() {
        let planner = WorkoutPlanner(gym: kg, style: .muscle)
        let easy = ExerciseHistory(bestEstimatedOneRepMax: 25 * (1 + 14.0 / 30), lastWeight: 25, lastReps: 10, lastRPE: 5,
                                   lastDate: monday, recentWeights: [25], lastSets: 3)
        let next = planner.progression(history: easy, reps: 6...10, rpe: 8, kind: .barbell)
        // Up to +30% while a lift has under three logged sessions; at least one step.
        #expect((next?.load ?? 0) > 25)
        #expect((next?.load ?? 99) <= 32.5)
        // Clearly easier (2+ reps) but not at the RPE-5 floor: from that session's 1RM.
        let lessEasy = ExerciseHistory(bestEstimatedOneRepMax: 100, lastWeight: 80, lastReps: 8, lastRPE: 6,
                                       lastDate: monday, recentWeights: [80, 80, 80], lastSets: 3)
        let caught = planner.progression(history: lessEasy, reps: 6...10, rpe: 8.5, kind: .barbell)
        // 80 × (1 + 12/30) = 112 → 8 reps at 1.5 in reserve ≈ 85 kg, within +15% upper body.
        #expect(caught?.load == 85)
        #expect(caught.map { (6...10).contains($0.targetReps) } == true)
        // Not when last time was at the target.
        let onTarget = ExerciseHistory(bestEstimatedOneRepMax: 100, lastWeight: 80, lastReps: 8, lastRPE: 8,
                                       lastDate: monday, recentWeights: [80, 80, 80], lastSets: 3)
        #expect(planner.progression(history: onTarget, reps: 6...10, rpe: 8.5, kind: .barbell)?.load == 80)
    }

    // §5: an isolation lift on weekly set goals still adds weight.
    @Test func legExtensionOnWeeklyGoalsStepsUp() {
        let planner = WorkoutPlanner(gym: kg, style: .muscle)
        #expect(planner.progressionMode(for: "Leg_Extensions", kind: .machine, compound: false, at: 60) == .load)
        var history = ExerciseHistory(bestEstimatedOneRepMax: 60 * (1 + 13.5 / 30), lastWeight: 60, lastReps: 10, lastRPE: 8.5,
                                      lastDate: monday, recentWeights: [60, 60, 60], lastSets: 3)
        var loads: [Double] = []
        for _ in 0..<4 {
            let plan = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: ["Leg_Extensions": history],
                                    muscleSetGoals: [.quadriceps: 3])
            guard let ext = plan.exercises.first(where: { $0.exerciseID == "Leg_Extensions" }), let load = ext.load else { break }
            loads.append(load)
            history = ExerciseHistory(bestEstimatedOneRepMax: history.bestEstimatedOneRepMax, lastWeight: load,
                                      lastReps: ext.repsToday, lastRPE: ext.rpe, lastDate: monday,
                                      recentWeights: ExerciseHistory.appending(load, to: history.recentWeights), lastSets: ext.sets)
        }
        #expect(loads.contains(65), "leg extension loads \(loads)")
    }

    // §4: the reps after a step are what the new weight allows.
    @Test func afterAStepTheRepsComeFromTheNewWeight() {
        let planner = WorkoutPlanner(gym: kg, style: .muscle)
        let top = ExerciseHistory(bestEstimatedOneRepMax: 113, lastWeight: 80, lastReps: 10, lastRPE: 7.5,
                                  lastDate: monday, recentWeights: [80, 80, 80], lastSets: 3)
        let next = planner.progression(history: top, reps: 6...10, rpe: 7.5, kind: .barbell)
        #expect(next == WorkoutPlanner.Progression(load: 82.5, targetReps: 8))
    }

    // §6: new weekly plans train every big muscle at least twice a week.
    @Test func defaultSplitsTrainEachMuscleTwice() {
        for count in 2...6 {
            let focuses = WeeklyPlan.focusRotation(start: .push, count: count)
            let days = focuses.enumerated().map { PlannedDay(weekday: 2 + $0.offset, time: 1080, focus: $0.element, minutes: 60) }
            for muscle in [Muscle.chest, .lats, .quadriceps, .hamstrings] {
                #expect(VolumeProgression.capacity(muscle, days: days).sessions >= 2, "\(count) days: \(muscle) \(focuses)")
            }
        }
    }

    // §7/§8: upper and full-body versions cover side and rear delts and balance push and pull.
    @Test func upperAndFullBodyVersionsCoverTheDelts() {
        let upper = Set(WorkoutFocus.upper.slots(variant: 0) + WorkoutFocus.upper.slots(variant: 1))
        #expect(upper.isSuperset(of: [.lateralRaise, .rearDelt, .verticalPull, .horizontalRow, .verticalPress]))
        let full = WorkoutFocus.fullBody.slots(variant: 0) + WorkoutFocus.fullBody.slots(variant: 1)
        let push = full.filter { $0.muscleGroup == .push }.count
        let pull = full.filter { $0.muscleGroup == .pull }.count
        #expect(push == pull)
        #expect(full.contains(.verticalPull))
        // The version alternates from history: after a session of A's own lifts, B.
        let didA = ["Barbell_Bench_Press_-_Medium_Grip": ExerciseHistory(bestEstimatedOneRepMax: 100, lastWeight: 80, lastReps: 8,
                                                                         lastRPE: 8, lastDate: monday)]
        #expect(WorkoutPlanner.suggestedVariant(focus: .upper, history: didA) == 1)
        #expect(WorkoutPlanner.suggestedVariant(focus: .upper, history: [:]) == 0)
        #expect(WorkoutPlanner.suggestedVariant(focus: .push, history: didA) == 0)
    }

    // §12: equipment fallbacks and staples.
    @Test func bodyweightAndMachineGymsKeepThePatterns() {
        let empty = GymProfile(name: "", unit: .kg, equipment: [], barbellWeight: 20, ezBarWeight: 10, smithBarWeight: 10,
                               plates: [], dumbbells: [], kettlebells: [],
                               cableStack: WeightStack(start: 5, step: 5, max: 100), machineStack: WeightStack(start: 5, step: 5, max: 150))
        let pull = WorkoutPlanner(gym: empty).plan(focus: .pull, minutes: 30, recovery: 80, history: [:], includeCore: false)
        #expect(pull.exercises.contains { $0.exerciseID == "Inverted_Row" })
        let machines = GymProfile(name: "", unit: .kg, equipment: [.machine, .cable], barbellWeight: 20, ezBarWeight: 10, smithBarWeight: 10,
                                  plates: [], dumbbells: [], kettlebells: [],
                                  cableStack: WeightStack(start: 5, step: 5, max: 100), machineStack: WeightStack(start: 5, step: 5, max: 150))
        #expect(!WorkoutPlanner(gym: machines).alternatives(for: .hinge).isEmpty)
        #expect(!WorkoutPlanner(gym: machines).alternatives(for: .hipThrust).isEmpty)
        #expect(ExerciseCatalog.slot(for: "Barbell_Deadlift") == .hinge)
        #expect(MuscleCoverage.muscles(for: .hipThrust).primary == .glutes)
    }

    // §10: one side at a time is timed as two.
    @Test func unilateralSetsTakeLonger() {
        let split = PlannedExercise(exerciseID: "Split_Squat_with_Dumbbells", name: "", sets: 3, reps: 6...10, rpe: 8,
                                    load: 20, loadKind: .dumbbell, note: nil)
        let goblet = PlannedExercise(exerciseID: "Goblet_Squat", name: "", sets: 3, reps: 6...10, rpe: 8,
                                     load: 20, loadKind: .kettlebell, note: nil)
        #expect(WorkoutPlanner.estimatedMinutes([split]) > WorkoutPlanner.estimatedMinutes([goblet]))
        #expect(ExerciseCatalog.exercise(id: "One-Arm_Dumbbell_Row")?.isUnilateral == true)
    }

    // §11: bodyweight lifts progress.
    @Test func bodyweightLiftsAddRepsThenWeight() {
        let planner = WorkoutPlanner(gym: kg, style: .balanced)
        let chin = ExerciseCatalog.exercise(id: "Pullups")!
        let past = ExerciseHistory(bestEstimatedOneRepMax: 0, lastWeight: 0, lastReps: 7, lastRPE: 8, lastDate: monday)
        let next = planner.prescribe(chin, slot: .verticalPull, minutes: 60, sessionRPE: 8, history: ["Pullups": past])
        #expect(next.targetReps == 8)
        #expect(next.progressionNote?.contains("one more") == true)
        let strong = ExerciseHistory(bestEstimatedOneRepMax: 0, lastWeight: 0, lastReps: 10, lastRPE: 8, lastDate: monday)
        let harder = planner.prescribe(chin, slot: .verticalPull, minutes: 60, sessionRPE: 8, history: ["Pullups": strong])
        #expect(harder.progressionNote?.contains("add 2.5-5 kg") == true)
        #expect(harder.reps.contains(harder.targetReps ?? 0))
        let weak = ExerciseHistory(bestEstimatedOneRepMax: 0, lastWeight: 0, lastReps: 3, lastRPE: 9, lastDate: monday)
        let assisted = planner.prescribe(chin, slot: .verticalPull, minutes: 60, sessionRPE: 8, history: ["Pullups": weak])
        #expect(assisted.progressionNote?.contains("assisted") == true)
    }

    // §9: weekly sets start near what you've been doing.
    @Test func volumeStartsFromRecentWeeks() {
        #expect(VolumeProgression.startingSets(recent: nil, style: .muscle) == 10)
        #expect(VolumeProgression.startingSets(recent: 15, style: .muscle) == 15)
        #expect(VolumeProgression.startingSets(recent: 19, style: .muscle) == 16)   // ceiling 20 − 4
        #expect(VolumeProgression.startingSets(recent: 6, style: .muscle) == 10)
        var sets: [VolumeProgression.LoggedSet] = []
        for week in 1...4 {
            let start = monday.addingTimeInterval(-Double(week) * 7 * 86_400 + 3600)
            for index in 0..<14 {
                sets.append(VolumeProgression.LoggedSet(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench",
                                                        sessionStart: start, order: index, primary: [.chest],
                                                        weightKg: 80, reps: 8, rpe: 8, isCompound: true))
            }
        }
        let recent = VolumeProgression.recentWeeklySets(sets, before: monday, style: .muscle, calendar: utc)
        #expect(recent[.chest] == 14)
        let week = VolumeProgression.week(weekStart: monday, block: TrainingBlock.weekState(1, style: .muscle, length: 6),
                                          style: .muscle, days: [PlannedDay(weekday: 2, time: 1080, focus: .push, minutes: 75),
                                                                 PlannedDay(weekday: 5, time: 1080, focus: .push, minutes: 75)],
                                          previous: nil, lastWeek: [:], states: [:], recentWeeklySets: recent)
        #expect((week.target(for: .chest)?.sets ?? 0) > 10)
        // Two weeks away doesn't restart the block any more.
        #expect(TrainingBlock.restartAfterWeeksAway == 4)
    }

    // §15: short sessions get a brief ramp on the first lift only; full body warms each region.
    @Test func warmUpsFitTheSession() {
        let planner = WorkoutPlanner(gym: kg, style: .balanced)
        let squat = ExerciseHistory(bestEstimatedOneRepMax: 140, lastWeight: 100, lastReps: 8, lastRPE: 8, lastDate: monday)
        let bench = ExerciseHistory(bestEstimatedOneRepMax: 100, lastWeight: 75, lastReps: 8, lastRPE: 8, lastDate: monday)
        let history = ["Barbell_Squat": squat, "Barbell_Bench_Press_-_Medium_Grip": bench]
        let full = planner.plan(focus: .fullBody, minutes: 60, recovery: 80, history: history, variant: 0)
        #expect((full.exercises[0].warmUpSets?.count ?? 0) >= 3)
        // The bench (a new region) gets two steps, not one feeler.
        #expect(full.exercises[1].warmUpSets?.count == 2)
        let short = planner.plan(focus: .fullBody, minutes: 30, recovery: 80, history: history, variant: 0)
        #expect(short.exercises[0].warmUpSets?.count == 2)
        #expect(short.exercises.dropFirst().allSatisfy { $0.warmUpSets == nil })
    }

    // Workout flow #22: no finisher on short sessions.
    @Test func shortSessionsSkipTheFinisher() {
        #expect(AbsFinisher.length(.five, sessionMinutes: 20) == .off)
        #expect(AbsFinisher.length(.ten, sessionMinutes: 30) == .ten)
        #expect(AbsFinisher.length(.five, sessionMinutes: 45, isShortVersion: true) == .off)
    }

    // Workout flow #30: an empty focus says why and what fits.
    @Test func anEmptyFocusSaysWhy() {
        let filter = ExerciseFilter(pains: [PainReport(area: .shoulder, level: 8, loggedAt: monday)])
        let plan = WorkoutPlanner(gym: .homeDumbbells).plan(focus: .push, minutes: 45, recovery: 80, history: [:], exerciseFilter: filter)
        #expect(plan.exercises.isEmpty)
        #expect(plan.lengthNote?.contains("loads a sore area") == true)
        #expect(plan.lengthNote?.contains("Try") == true)
    }

    // Workout flow #4: saved workouts follow the same rules as planned ones.
    @Test func savedWorkoutsFollowThePainAndGymRules() {
        let planner = WorkoutPlanner(gym: kg)
        let items = [
            TemplateItem(exerciseID: "Barbell_Squat", name: "Back Squat", sets: 3, reps: 6...8),
            TemplateItem(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench Press", sets: 3, reps: 6...8, weight: 61),
            TemplateItem(exerciseID: "Leg_Extensions", name: "Leg Extension", sets: 3, reps: 10...12)
        ]
        let filter = ExerciseFilter(neverAgain: ["Barbell_Squat"], pains: [PainReport(area: .knee, level: 4, loggedAt: monday)])
        let checked = planner.checkedTemplate(items, history: [:], exerciseFilter: filter)
        let ids = checked.exercises.map(\.exerciseID)
        #expect(!ids.contains("Barbell_Squat"))
        #expect(checked.exercises.first?.note?.contains("Swapped in for Back Squat") == true)
        // A fixed 61 kg bench is rounded down to what the plates make.
        #expect(checked.exercises.first { $0.exerciseID == "Barbell_Bench_Press_-_Medium_Grip" }?.load == 60)
        // The knee (4/10) gets the easy-going note on the leg extension.
        #expect(checked.exercises.first { $0.exerciseID == "Leg_Extensions" }?.note?.contains("your knee") == true)
        // A dumbbell gym has no barbell: the bench is swapped for a dumbbell press.
        let home = WorkoutPlanner(gym: .homeDumbbells).checkedTemplate(items, history: [:])
        #expect(home.exercises.contains { $0.exerciseID == "Dumbbell_Bench_Press" })
    }
}
