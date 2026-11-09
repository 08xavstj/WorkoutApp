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
        // Dumbbell bench ≈ 0.4 × barbell per hand: 93.6 e1RM → 72 for 7 (the middle of 6-8) at RPE 8
        // → 90% (from your own lift) = 64.8 → 60 lb dumbbells. (Was 55: top of the range and 85%.)
        let estimate = LoadEstimator.estimate(exerciseID: "Dumbbell_Bench_Press", reps: 6...8, rpe: 8,
                                              history: [benchID: bench], lifter: .unknown, gym: gym)
        #expect(estimate?.load == 60)
        #expect(estimate?.reps == 7)
        #expect(estimate?.source == "your Bench Press")
        #expect(estimate?.note == "Estimated from your Bench Press: start here and adjust after set 1")
    }

    @Test func relatedMovementUsesTheSlotRatio() {
        // Incline ≈ 0.8 × flat bench: 187 e1RM → 144 for 7 at RPE 8 → 90% = 130 → 125 lb on the bar.
        let estimate = LoadEstimator.estimate(exerciseID: "Barbell_Incline_Bench_Press_-_Medium_Grip", reps: 6...8, rpe: 8,
                                              history: [benchID: bench], lifter: .unknown, gym: gym)
        #expect(estimate?.load == 125)
        #expect(estimate?.source == "your Bench Press")
    }

    @Test func bodyWeightFallbackScalesBySexAndStatus() {
        // 80 kg = 176 lb; novice squat standard 1.3 × BW = 229 e1RM → 174 for 7 (middle of 6-8)
        // at RPE 7.5 → 85% = 148 → 145 lb. (Was 80 lb: the untrained column for everyone.)
        let novice = LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 7.5, history: [:],
                                            lifter: .init(bodyMassKg: 80, sex: .male, status: .novice), gym: gym)
        #expect(novice?.load == 145)
        #expect(novice?.source == "your body weight")
        let intermediate = LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 7.5, history: [:],
                                                  lifter: .init(bodyMassKg: 80, sex: .male, status: .intermediate), gym: gym)
        #expect(intermediate?.load == 190) // 1.7 × BW
        let female = LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 7.5, history: [:],
                                            lifter: .init(bodyMassKg: 80, sex: .female, status: .novice), gym: gym)
        #expect(female?.load == 110) // 0.75 × the men's lower-body figure
        let untrained = LoadEstimator.estimate(exerciseID: "Barbell_Squat", reps: 6...8, rpe: 7.5, history: [:],
                                               lifter: .init(bodyMassKg: 80, sex: .male, status: .untrained), gym: gym)
        #expect(untrained?.load == 100) // 0.9 × BW
        #expect(LoadEstimator.bodyweightFraction(slot: .horizontalPress, sex: .male, status: .untrained) == 0.7)
        #expect(LoadEstimator.bodyweightFraction(slot: .horizontalPress, sex: .male, status: .advanced) == 1.5)
    }

    /// Audit 2026-11 §1: an 85 kg intermediate man's first bench is a real
    /// working weight (55-75 kg for 6-10 at 2-3 in reserve); untrained stays light.
    @Test func firstBenchIsRealisticForTrainedAndCautiousForUntrained() {
        let kg = GymProfile.commercialKilograms
        let intermediate = LoadEstimator.estimate(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", reps: 6...10, rpe: 7.5,
                                                  history: [:], lifter: .init(bodyMassKg: 85, sex: .male, status: .intermediate), gym: kg)
        #expect((55...75).contains(intermediate?.load ?? 0), "\(intermediate?.load ?? 0) kg")
        #expect(intermediate?.reps == 8)
        let untrained = LoadEstimator.estimate(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", reps: 6...10, rpe: 7.5,
                                               history: [:], lifter: .init(bodyMassKg: 85, sex: .male, status: .untrained), gym: kg)
        #expect((untrained?.load ?? 99) <= 40, "\(untrained?.load ?? 0) kg")
        // Older: from 60 the tables scale down (0.8) and the cut stays conservative.
        let older = LoadEstimator.estimate(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", reps: 6...10, rpe: 7.5,
                                           history: [:], lifter: .init(bodyMassKg: 85, sex: .male, status: .intermediate, age: 65), gym: kg)
        #expect((older?.load ?? 99) < (intermediate?.load ?? 0))
    }

    /// Numbers you typed in beat the tables: a 100 kg × 5 bench → 116.7 kg 1RM.
    @Test func knownNumbersBeatTheTables() {
        let kg = GymProfile.commercialKilograms
        let anchors = LoadEstimator.anchors(benchKg: 100, deadliftKg: 180)
        #expect(abs((anchors[.horizontalPress] ?? 0) - 116.67) < 0.01)
        #expect(abs((anchors[.hinge] ?? 0) - 168) < 0.01) // RDL ≈ 0.8 × deadlift
        let lifter = LoadEstimator.Lifter(bodyMassKg: 85, sex: .male, status: .novice, anchorOneRepMaxKg: anchors)
        let bench = LoadEstimator.estimate(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", reps: 6...10, rpe: 7.5,
                                           history: [:], lifter: lifter, gym: kg)
        // 116.7 / (1 + 10.5/30) × 0.9 = 77.8 → 77.5 kg.
        #expect(bench?.load == 77.5)
        #expect(bench?.source == "the numbers you gave")
        // Incline borrows from it through the slot ratio (0.8).
        let incline = LoadEstimator.estimate(exerciseID: "Barbell_Incline_Bench_Press_-_Medium_Grip", reps: 6...10, rpe: 7.5,
                                             history: [:], lifter: lifter, gym: kg)
        #expect(incline?.source == "the numbers you gave")
    }

    @Test func estimatesAreConservativeAndLoadable() {
        let estimate = LoadEstimator.estimate(exerciseID: "Dumbbell_Bench_Press", reps: 6...8, rpe: 8,
                                              history: [benchID: bench], lifter: .unknown, gym: gym)
        let load = estimate?.load ?? 0
        #expect(gym.achievableLoads(for: .dumbbell).contains(load))
        // Without the 90% cut the pick would be the 70 lb pair.
        #expect(gym.load(atMost: 93.6 / (1 + 9.0 / 30), on: .dumbbell) == 70)
        #expect(load < 70)
        #expect(LoadEstimator.conservativeFraction == 0.85)
        #expect(LoadEstimator.historyFraction == 0.9)
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
        // Overhead press ≈ 0.6 × bench, dumbbells 0.4 each: 56 e1RM → 43 for 7 at RPE 8 → 90% → 35 lb.
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
        // 185 × 8 at RPE 7 (3 in reserve) → about 9 reps left at 190 with 2 in reserve: aim for 7, not the bottom (6).
        #expect(plan.exercises.first?.progressionNote == "+5 lb from last time: you hit 8 reps at RPE 7. Aim for 7 reps")
        #expect(plan.exercises.first?.targetReps == 7)
        // Held at the same weight until the reps are there.
        let held = ExerciseHistory(bestEstimatedOneRepMax: 32, lastWeight: 20, lastReps: 12, lastRPE: 9, lastDate: .now)
        // Changed with double progression: the note names today's rep target;
        // 20 → 25 lb dumbbells is a big jump, so the top moves to 14.
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12, loadKind: .dumbbell)
                == "Same weight, aim for 13 reps; the weight goes up once you hit 14")
        let lighter = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: nil, lastDate: .now)
        #expect(planner.progressionNote(load: 175, history: lighter, reps: 6...8) == "−10 lb from last time for today's effort")
        #expect(planner.progressionNote(load: 190, history: lighter, reps: 6...8) == "+5 lb from last time: you hit 8 reps")
    }
}
