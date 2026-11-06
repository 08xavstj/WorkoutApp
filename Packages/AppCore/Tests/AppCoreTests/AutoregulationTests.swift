import Foundation
import Testing
@testable import AppCore

struct AutoregulationTests {
    let gym = GymProfile.commercialKilograms

    private func next(_ weight: Double, _ reps: Int, rpe: Double?, target: Double, set: Int = 2,
                      adjusted: Bool = false, kind: EquipmentKind? = .barbell) -> Autoregulation.Suggestion? {
        Autoregulation.nextSet(after: LiftProgress.LoggedSet(weight: weight, reps: reps, rpe: rpe), setNumber: set,
                               targetRIR: target, alreadyAdjusted: adjusted, kind: kind, gym: gym)
    }

    @Test func twoOrMoreRepsFresherGoesUpOneJump() {
        // RPE 7 = 3 in reserve against a target of 1: up one 2.5 kg jump.
        let up = next(60, 8, rpe: 7, target: 1)
        #expect(up?.change == .loadUp)
        #expect(up?.load == 62.5)
        #expect(up?.reps == 8)
        #expect(up?.message(unit: "kg") == "Next set 62.5 kg (you had 3 in reserve)")
    }

    @Test func twoOrMoreRepsHarderGoesDownOneJump() {
        let down = next(60, 8, rpe: 10, target: 2)
        #expect(down?.change == .loadDown)
        #expect(down?.load == 57.5)
        #expect(down?.message(unit: "kg") == "Next set 57.5 kg (you had none in reserve; the plan is 2)")
    }

    @Test func withinOneRepHolds() {
        #expect(next(60, 8, rpe: 8, target: 2)?.change == .hold)
        #expect(next(60, 8, rpe: 7, target: 2)?.change == .hold)       // 1 fresher
        #expect(next(60, 8, rpe: 9, target: 2)?.change == .hold)       // 1 harder
        #expect(next(60, 8, rpe: 8.5, target: 2.5)?.change == .hold)
        #expect(next(60, 8, rpe: 8, target: 2)?.message(unit: "kg") == nil)
        #expect(next(60, 8, rpe: 8, target: 2)?.load == 60)
    }

    @Test func bigJumpDownTrimsRepsInstead() {
        // 10 kg dumbbells: the next pair down (8 kg) is 20% lighter.
        let trim = next(10, 10, rpe: 10, target: 2, kind: .dumbbell)
        #expect(trim?.change == .trimReps)
        #expect(trim?.load == 10)
        #expect(trim?.reps == 9)
        #expect(trim?.message(unit: "kg") == "Next set 9 reps at the same weight (you had none in reserve; the plan is 2)")
        // Three reps past the target trims two.
        #expect(next(10, 10, rpe: 10, target: 3, kind: .dumbbell)?.reps == 8)
    }

    @Test func bigJumpUpAddsRepsInstead() {
        let more = next(10, 10, rpe: 6, target: 1, kind: .dumbbell)
        #expect(more?.change == .addReps)
        #expect(more?.reps == 12)
        // Never past the 12-rep ceiling.
        #expect(next(10, 12, rpe: 6, target: 1, kind: .dumbbell)?.change == .hold)
    }

    @Test func bodyweightOnlyMovesReps() {
        let trim = next(0, 8, rpe: 10, target: 2, kind: nil)
        #expect(trim?.change == .trimReps)
        #expect(trim?.reps == 7)
    }

    @Test func guardsStopAdjustments() {
        // Never off the first working set.
        #expect(next(60, 8, rpe: 7, target: 1, set: 1) == nil)
        // No RPE logged, no reps, or a long set (RPE is least accurate there).
        #expect(next(60, 8, rpe: nil, target: 1) == nil)
        #expect(next(60, 0, rpe: 7, target: 1) == nil)
        #expect(next(60, 13, rpe: 7, target: 1) == nil)
        #expect(next(60, 12, rpe: 7, target: 1)?.change == .loadUp)
        // At most one change per exercise per session.
        #expect(next(60, 8, rpe: 7, target: 1, adjusted: true) == nil)
    }
}

struct ProgressionModeTests {
    let gym = GymProfile.commercialPounds
    let benchID = "Barbell_Bench_Press_-_Medium_Grip"
    let bench = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)

    @Test func suggestedModeFollowsTheEquipment() {
        #expect(ProgressionMode.suggested(kind: .barbell, compound: true, bigJump: false) == .load)
        #expect(ProgressionMode.suggested(kind: .ezBar, compound: false, bigJump: false) == .load)
        #expect(ProgressionMode.suggested(kind: .dumbbell, compound: true, bigJump: false) == .load)
        #expect(ProgressionMode.suggested(kind: .dumbbell, compound: true, bigJump: true) == .reps)
        #expect(ProgressionMode.suggested(kind: .machine, compound: false, bigJump: false) == .sets)
        #expect(ProgressionMode.suggested(kind: nil, compound: true, bigJump: false) == .reps)

        let planner = WorkoutPlanner(gym: gym)
        // 20 → 25 lb dumbbells is a 25% jump; 50 → 55 is 10%.
        #expect(planner.progressionMode(for: "x", kind: .dumbbell, compound: true, at: 20) == .reps)
        #expect(planner.progressionMode(for: "x", kind: .dumbbell, compound: true, at: 50) == .load)
        var own = planner
        own.progressionModes = ["x": .sets]
        #expect(own.progressionMode(for: "x", kind: .barbell, compound: true, at: 185) == .sets)
    }

    @Test func repAndSetProgressionHoldTheWeight() {
        let planner = WorkoutPlanner(gym: gym)
        #expect(planner.suggestedLoad(history: bench, reps: 6...8, rpe: 8, kind: .barbell) == 190)
        #expect(planner.suggestedLoad(history: bench, reps: 6...8, rpe: 8, kind: .barbell, mode: .load) == 190)
        #expect(planner.suggestedLoad(history: bench, reps: 6...8, rpe: 8, kind: .barbell, mode: .reps) == 185)
        #expect(planner.suggestedLoad(history: bench, reps: 6...8, rpe: 8, kind: .barbell, mode: .sets) == 185)
        // Two reps past the top of the range: up one jump.
        var earned = bench
        earned.lastReps = 10
        #expect(planner.suggestedLoad(history: earned, reps: 6...8, rpe: 8, kind: .barbell, mode: .reps) == 190)
        // An easier day than last time still goes lighter.
        #expect(planner.suggestedLoad(history: bench, reps: 6...8, rpe: 6.5, kind: .barbell, mode: .reps) == 165)
    }

    @Test func progressionNotesFollowTheMode() {
        let planner = WorkoutPlanner(gym: gym)
        let held = ExerciseHistory(bestEstimatedOneRepMax: 32, lastWeight: 20, lastReps: 12, lastRPE: 9, lastDate: .now)
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12) == "Same weight as last time: get 12 reps to move up")
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12, mode: .reps)
                == "Same weight as last time: add a rep; it moves up at 14 reps")
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12, mode: .sets)
                == "Same weight and reps: add a set when 12 reps feel on target; it moves up at 14 reps")
        // The big-jump tip is for load progression only.
        #expect(planner.notes(load: 20, history: held, reps: 10...12, rpe: 9, kind: .dumbbell, mode: .reps) == "20 lb each hand")
    }

    @Test func plannerUsesYourChoice() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .reps]
        let plan = planner.plan(focus: .push, minutes: 45, recovery: 80, history: [benchID: bench])
        #expect(plan.exercises.first?.exerciseID == benchID)
        #expect(plan.exercises.first?.load == 185)
        #expect(plan.exercises.first?.progressionNote == "Same weight as last time: add a rep; it moves up at 10 reps")
    }
}
