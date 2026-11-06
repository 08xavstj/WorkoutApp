import Foundation
import Testing
@testable import AppCore

/// Starting weights for lifts without history (`LoadEstimator`) and the
/// progression note the planner writes when there is history.
struct LoadEstimatorTests {
    let gym = GymProfile.commercialPounds
    // 185 × 8 at RPE 7 last time: e1RM ≈ 234 lb.
    let bench = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)
    let benchID = "Barbell_Bench_Press_-_Medium_Grip"

    @Test func sameMovementUsesTheExerciseRatio() {
        // Dumbbell bench ≈ 0.4 × barbell per hand: 93.6 e1RM → 70 for 8 at RPE 8 → 85% → 55 lb dumbbells.
        let estimate = LoadEstimator.estimate(exerciseID: "Dumbbell_Bench_Press", reps: 6...8, rpe: 8,
                                              history: [benchID: bench], lifter: .unknown, gym: gym)
        #expect(estimate?.load == 55)
        #expect(estimate?.source == "your Bench Press")
        #expect(estimate?.note == "Estimated from your Bench Press: start here and adjust after set 1")
    }

    @Test func relatedMovementUsesTheSlotRatio() {
        // Incline ≈ 0.8 × flat bench: 187 e1RM → 140 → 85% = 119 → 115 lb on the bar.
        let estimate = LoadEstimator.estimate(exerciseID: "Barbell_Incline_Bench_Press_-_Medium_Grip", reps: 6...8, rpe: 8,
                                              history: [benchID: bench], lifter: .unknown, gym: gym)
        #expect(estimate?.load == 115)
        #expect(estimate?.source == "your Bench Press")
    }

    @Test func bodyWeightFallbackScalesBySexAndStatus() {
        // 80 kg = 176 lb; untrained squat standard 0.75 × BW = 132 e1RM → 98 for 8 at RPE 7.5 → 85% → 83 → 80 lb.
        let novice = LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 7.5, history: [:],
                                            lifter: .init(bodyMassKg: 80, sex: .male, status: .novice), gym: gym)
        #expect(novice?.load == 80)
        #expect(novice?.source == "your body weight")
        let intermediate = LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 7.5, history: [:],
                                                  lifter: .init(bodyMassKg: 80, sex: .male, status: .intermediate), gym: gym)
        #expect(intermediate?.load == 105) // × 1.3
        let female = LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 7.5, history: [:],
                                            lifter: .init(bodyMassKg: 80, sex: .female, status: .novice), gym: gym)
        #expect(female?.load == 55)
        #expect(LoadEstimator.statusMultiplier(.untrained) == 1)
        #expect(LoadEstimator.statusMultiplier(.advanced) == 1.6)
    }

    @Test func estimatesAreConservativeAndLoadable() {
        let estimate = LoadEstimator.estimate(exerciseID: "Dumbbell_Bench_Press", reps: 6...8, rpe: 8,
                                              history: [benchID: bench], lifter: .unknown, gym: gym)
        let load = estimate?.load ?? 0
        #expect(gym.achievableLoads(for: .dumbbell).contains(load))
        // Without the 85% cut the pick would be the 70 lb pair.
        #expect(gym.load(atMost: 93.6 / (1 + 10.0 / 30), on: .dumbbell) == 70)
        #expect(load < 70)
        #expect(LoadEstimator.conservativeFraction == 0.85)
    }

    @Test func nothingToEstimateFromGivesNil() {
        #expect(LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 8, history: [:], lifter: .unknown, gym: gym) == nil)
        // Bodyweight and unknown exercises never get a weight.
        #expect(LoadEstimator.estimate(exerciseID: "Pushups", reps: 8...12, rpe: 8, history: [benchID: bench], lifter: .unknown, gym: gym) == nil)
        #expect(LoadEstimator.estimate(exerciseID: "not-in-catalog", reps: 8...12, rpe: 8, history: [benchID: bench],
                                       lifter: .init(bodyMassKg: 80), gym: gym) == nil)
        // No standard for core work.
        #expect(LoadEstimator.bodyweightFraction(slot: .core, sex: .male) == nil)
    }

    @Test func plannerPrefillsEstimatedLoadsWithANote() {
        let planner = WorkoutPlanner(gym: gym)
        let plan = planner.plan(focus: .push, minutes: 60, recovery: 80, history: [benchID: bench])
        // Overhead press ≈ 0.6 × bench, dumbbells 0.4 each: 56 e1RM → 42 → 85% → 35 lb.
        let press = plan.exercises[1]
        #expect(press.exerciseID == "Dumbbell_Shoulder_Press")
        #expect(press.load == 35)
        #expect(press.note?.hasPrefix("Estimated from your Bench Press: start here and adjust after set 1") == true)
        #expect(press.note?.hasSuffix("35 lb each hand") == true)
        // An estimated weight still gets its ramp set; no progression note without history.
        #expect(press.warmUpSets?.isEmpty == false)
        #expect(press.progressionNote == nil)
    }

    @Test func progressionNoteSaysHowTheWeightMoved() {
        let planner = WorkoutPlanner(gym: gym)
        let plan = planner.plan(focus: .push, minutes: 45, recovery: 80, history: [benchID: bench])
        #expect(plan.exercises.first?.load == 190)
        #expect(plan.exercises.first?.progressionNote == "+5 lb from last time: you hit 8 reps at RPE 7")
        // Held at the same weight until the reps are there.
        let held = ExerciseHistory(bestEstimatedOneRepMax: 32, lastWeight: 20, lastReps: 12, lastRPE: 9, lastDate: .now)
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12) == "Same weight as last time: get 12 reps to move up")
        let lighter = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: nil, lastDate: .now)
        #expect(planner.progressionNote(load: 175, history: lighter, reps: 6...8) == "−10 lb from last time for today's effort")
        #expect(planner.progressionNote(load: 190, history: lighter, reps: 6...8) == "+5 lb from last time: you hit 8 reps")
    }
}
