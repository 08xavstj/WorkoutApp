import Foundation
import Testing
@testable import AppCore

/// Session length changes the plan (`WorkoutPlanner.baseSets`, `exerciseCount`,
/// `WorkoutFocus.extraSlot`), and every plan says why and which muscles.
struct SessionLengthTests {
    let planner = WorkoutPlanner(gym: .commercialPounds)

    @Test func seventyFiveMinutesBuysMoreThanSixty() {
        let hour = planner.plan(focus: .push, minutes: 60, recovery: 80, history: [:])
        let long = planner.plan(focus: .push, minutes: 75, recovery: 80, history: [:])
        #expect(hour.exercises.count == 6)
        #expect(long.exercises.count == 7)
        #expect(long.totalSets > hour.totalSets)
        let hourMinutes = WorkoutPlanner.estimatedMinutes(hour.exercises)
        let longMinutes = WorkoutPlanner.estimatedMinutes(long.exercises)
        #expect(longMinutes > hourMinutes)
        #expect(hourMinutes <= 60)
        #expect((65...75).contains(longMinutes))
        // The seventh exercise is a second triceps movement, not a repeat of the first: chest
        // already has three, and a fourth went past the session cap (`capSessionVolume`).
        #expect(Set(long.exercises.map(\.exerciseID)).count == 7)
        #expect(long.exercises.last?.exerciseID == "Dumbbell_One-Arm_Triceps_Extension")
        #expect(!long.hasSupersets)
        #expect(hour.estimatedMinutes == hourMinutes)
    }

    /// The plan uses the time you picked: never over it, never far under it
    /// (`WorkoutPlanner.fill`, `fillFraction`). A user's 60-minute plan once
    /// took 40 because ramp sets, transitions and the rest style weren't counted.
    @Test func plansFillTheTimePicked() {
        for focus in WorkoutFocus.allCases {
            for minutes in [30, 45, 60, 75] {
                let plan = planner.plan(focus: focus, minutes: minutes, recovery: 80, history: [:])
                let estimate = plan.estimatedMinutes ?? 0
                #expect(estimate <= minutes, "\(focus) \(minutes): \(estimate)")
                #expect(Double(estimate) >= 0.8 * Double(minutes), "\(focus) \(minutes): \(estimate)")
                #expect(estimate == WorkoutPlanner.estimatedMinutes(plan.exercises))
                #expect(plan.exercises.allSatisfy { $0.sets <= WorkoutPlanner.maximumSetsPerExercise + 1 })
            }
        }
        // A 60-minute leg day lands near the hour, not at 40.
        let legs = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: [:])
        #expect((52...60).contains(legs.estimatedMinutes ?? 0))
    }

    @Test func estimateCountsWarmUpRampsTransitionsAndStyle() {
        var squat = PlannedExercise(exerciseID: "Barbell_Squat", name: "Squat", sets: 3, reps: 6...8, rpe: 8, load: 185, loadKind: .barbell, note: nil)
        let curl = PlannedExercise(exerciseID: "Seated_Leg_Curl", name: "Leg Curl", sets: 3, reps: 10...12, rpe: 9, load: nil, loadKind: .machine, note: nil)
        // Balanced, no movement warm-up: 2 min transition + 3 × 45 s per exercise, with the rest
        // (3 min on squats and hinges, 1.5 on small lifts; `RestTimer.defaultSeconds(style:slot:)`)
        // only between sets: the walk to the next exercise is the last set's rest.
        // 2 + (2.25 + 6) + (2.25 + 3) = 15.5 → 16 (rounded half up).
        #expect(WorkoutPlanner.estimatedMinutes([squat, curl]) == 16)
        // A 6-minute movement warm-up (short tier) is added as is.
        #expect(WorkoutPlanner.estimatedMinutes([squat, curl], warmUpMinutes: 6) == 22)
        // Muscle style rests 2.5 min on squats: 2 + (2.25 + 5) + 5.25 = 14.5 → 15.
        #expect(WorkoutPlanner.estimatedMinutes([squat, curl], style: .muscle) == 15)
        // Three ramp sets at 1.5 min each (30 s work + 60 s rest): 15.5 + 4.5 = 20.
        squat.warmUpSets = WarmUp.sets(workingLoad: 185, kind: .barbell, gym: .commercialPounds)
        #expect(squat.warmUpSets?.count == 3)
        #expect(WorkoutPlanner.estimatedMinutes([squat, curl]) == 20)
        // A one-side-at-a-time set takes twice the work (split squat: 3 × 90 s + 2 × 2.5 min rest).
        let split = PlannedExercise(exerciseID: "Split_Squat_with_Dumbbells", name: "Split Squat", sets: 3, reps: 6...8,
                                    rpe: 8, load: 20, loadKind: .dumbbell, note: nil)
        #expect(WorkoutPlanner.estimatedMinutes([split]) == 10) // 4.5 + 5 = 9.5 → 10
        // The plan's own rest wins (the heavy first lift's 3 min in the strength + muscle style).
        var heavy = PlannedExercise(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench", sets: 3, reps: 4...6,
                                    rpe: 8, load: 100, loadKind: .barbell, note: nil)
        heavy.restSeconds = 180
        #expect(WorkoutPlanner.estimatedMinutes([heavy], style: .strengthAndMuscle) == 8) // 2.25 + 6 = 8.25
    }

    @Test func rampSetsOnlyWhenThereIsAWeight() {
        // No history and no body weight: nothing to estimate from, so no load and no ramp sets.
        let plan = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: [:])
        #expect(plan.exercises.allSatisfy { $0.load == nil && $0.warmUpSets == nil })
        #expect(plan.exercises.first?.note?.hasPrefix("First time") == true)
        // With a body weight the first lift gets a starting weight and a ramp.
        let weighed = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: [:], bodyMassKg: 80)
        #expect(weighed.exercises.first?.load != nil)
        #expect(weighed.exercises.first?.warmUpSets?.isEmpty == false)
    }

    @Test func setsAndExerciseCountFollowTheLength() {
        #expect(WorkoutPlanner.baseSets(compound: true, minutes: 30) == 3)
        #expect(WorkoutPlanner.baseSets(compound: true, minutes: 60) == 4)
        #expect(WorkoutPlanner.baseSets(compound: false, minutes: 60) == 3)
        #expect(WorkoutPlanner.baseSets(compound: false, minutes: 75) == 4)
        #expect(WorkoutPlanner.exerciseCount(minutes: 30) == 4)
        #expect(WorkoutPlanner.exerciseCount(minutes: 45) == 5)
        #expect(WorkoutPlanner.exerciseCount(minutes: 60) == 6)
        #expect(WorkoutPlanner.exerciseCount(minutes: 75) == 7)
    }

    @Test func rationaleSaysWhy() {
        let plan = planner.plan(focus: .pull, minutes: 45, recovery: 50, history: [:],
                                focusReason: "based on what you've trained recently")
        #expect(!plan.rationale.isEmpty)
        #expect(plan.rationale.contains("Pull Day based on what you've trained recently"))
        #expect(plan.rationale.contains("Recovery 50%"))
        // No reps-in-reserve wording: the sets work to rep goals (`RepGoal`).
        #expect(!plan.rationale.contains("reps left"))
        #expect(!plan.rationale.contains("in the tank"))
        #expect(plan.rationale.contains("45 min"))
        let week3 = TrainingBlock.weekState(3, style: .balanced, length: 5)
        let blocked = planner.plan(focus: .legs, minutes: 60, recovery: 90, history: [:], block: week3)
        #expect(blocked.rationale.contains("Block week 3 of 5"))
        let unknown = planner.plan(focus: .legs, minutes: 60, recovery: nil, history: [:])
        #expect(unknown.rationale.contains("No recovery score yet"))
    }

    @Test func everyCatalogExerciseNamesItsMuscles() {
        for (slot, list) in ExerciseCatalog.options {
            #expect(!ExerciseCatalog.muscles(for: slot).isEmpty)
            for exercise in list {
                #expect(!ExerciseCatalog.muscles(forExerciseID: exercise.id).isEmpty, "\(exercise.id)")
            }
        }
        #expect(ExerciseCatalog.muscles(forExerciseID: "not-in-catalog").isEmpty)
        let plan = planner.plan(focus: .push, minutes: 45, recovery: 80, history: [:])
        #expect(plan.exercises.allSatisfy { !$0.muscles.isEmpty })
        #expect(plan.musclesCovered.first == "Chest")
        #expect(plan.musclesCovered.count == Set(plan.musclesCovered).count)
    }
}
