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
        // The seventh exercise is a second chest movement, not a repeat of the first.
        #expect(Set(long.exercises.map(\.exerciseID)).count == 7)
        #expect(long.exercises.last?.exerciseID == "Dumbbell_Bench_Press")
        #expect(!long.hasSupersets)
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
        #expect(plan.rationale.contains("effort 7.5/10"))
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
