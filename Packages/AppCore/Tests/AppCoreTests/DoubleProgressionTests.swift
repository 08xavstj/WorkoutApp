import Foundation
import Testing
@testable import AppCore

/// Double progression (`WorkoutPlanner.progression`): same weight and one
/// more rep until the top of the range, then the next weight and the bottom
/// of the range; the 1RM estimate only for easier days and missed ranges.
struct DoubleProgressionTests {
    let planner = WorkoutPlanner(gym: .commercialKilograms)

    /// 82.5 kg × `reps` at RPE `rpe` last time.
    private func squat(_ reps: Int, rpe: Double = 7) -> ExerciseHistory {
        let e1RM = 82.5 * (1 + (Double(reps) + 10 - rpe) / 30)
        return ExerciseHistory(bestEstimatedOneRepMax: e1RM, lastWeight: 82.5, lastReps: reps, lastRPE: rpe, lastDate: .now)
    }

    @Test func insideTheRangeKeepsTheWeightAndAddsARep() {
        // The reviewer's case: 82.5 × 6 at RPE 7, 3 in reserve again today.
        // The 1RM formula alone said 72.5 × 10.
        let today = planner.progression(history: squat(6), reps: 6...10, rpe: 7, kind: .barbell)
        #expect(today == WorkoutPlanner.Progression(load: 82.5, targetReps: 7))
        #expect(planner.progressionNote(load: 82.5, history: squat(6), reps: 6...10, rpe: 7, loadKind: .barbell)
                == "Same weight, aim for 7 reps; it moves up at 10")
    }

    @Test func theTopOfTheRangeStepsUpAndResetsTheReps() {
        let today = planner.progression(history: squat(10), reps: 6...10, rpe: 7, kind: .barbell)
        #expect(today?.targetReps == 6)
        #expect((today?.load ?? 0) > 82.5)
        #expect(today?.load == GymProfile.commercialKilograms.nextLoad(above: 82.5, on: .barbell))
    }

    @Test func anEasierDayGoesLighterFromTheEstimate() {
        // Deload or low recovery: RPE 5.5 today after RPE 7.
        let today = planner.progression(history: squat(6), reps: 6...10, rpe: 5.5, kind: .barbell)
        #expect((today?.load ?? 99) < 82.5)
        #expect(today?.targetReps == 6)
    }

    @Test func missingTheRangeGoesLighterForItsBottom() {
        let today = planner.progression(history: squat(4), reps: 6...10, rpe: 7, kind: .barbell)
        #expect((today?.load ?? 99) < 82.5)
        #expect(today?.targetReps == 6)
    }

    @Test func thePlanCarriesTheRepTarget() throws {
        // A good recovery day (effort at or above last time's RPE 7): 82.5 × 7.
        let plan = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: ["Barbell_Squat": squat(6)])
        let squat = try #require(plan.exercises.first { $0.exerciseID == "Barbell_Squat" })
        #expect(squat.load == 82.5)
        #expect(squat.repsToday == 7)
        #expect(squat.progressionNote == "Same weight, aim for 7 reps; it moves up at 8")
    }

    @Test func noRepTargetMeansTheTopOfTheRange() {
        let planned = PlannedExercise(exerciseID: "x", name: "X", sets: 3, reps: 8...12, rpe: 8, load: nil,
                                      loadKind: nil, note: nil)
        #expect(planned.repsToday == 12)
    }

    @Test func oldPlansWithoutTargetsStillDecode() throws {
        let planned = PlannedExercise(exerciseID: "x", name: "X", sets: 3, reps: 8...12, rpe: 8, load: 20,
                                      loadKind: .dumbbell, note: nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(planned)) as? [String: Any] ?? [:]
        json.removeValue(forKey: "targetReps")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(PlannedExercise.self, from: data).targetReps == nil)
    }

    @Test func bigJumpsAimPastTheTop() {
        // 20 → 25 lb dumbbells is 25%: reps climb to 14 first.
        let pounds = WorkoutPlanner(gym: .commercialPounds)
        let held = ExerciseHistory(bestEstimatedOneRepMax: 32, lastWeight: 20, lastReps: 12, lastRPE: 9, lastDate: .now)
        #expect(pounds.progression(history: held, reps: 10...12, rpe: 9, kind: .dumbbell)
                == WorkoutPlanner.Progression(load: 20, targetReps: 13))
    }

    @Test func repProgressionTargetsOneMoreRep() {
        var pounds = WorkoutPlanner(gym: .commercialPounds)
        pounds.progressionModes = ["Barbell_Bench_Press_-_Medium_Grip": .reps]
        let bench = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)
        let plan = pounds.plan(focus: .push, minutes: 45, recovery: 80, history: ["Barbell_Bench_Press_-_Medium_Grip": bench])
        #expect(plan.exercises.first?.targetReps == 9)
    }
}
