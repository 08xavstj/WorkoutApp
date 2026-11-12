import Foundation
import Testing
@testable import AppCore

/// A user's report after a 75-min Upper session (muscle + strength goals, kg,
/// commercial gym): "it only came in at 42.5 mins", "only 2 sets per exercise",
/// "the weight was half of what I'd done last time" and "only wanting me to do
/// 15 reps". Root causes, each reproduced here:
/// - the time estimate counted the rest after every exercise's last set as
///   well as the walk to the next one, so 18 working sets "filled" 75 min;
/// - `fit` cut compound lifts to 2 sets as readily as isolation work, and
///   `applySetGoals` split a muscle's weekly goal into 3 + 2 over a row and a
///   pulldown; `fill` never went past the week's goals, so the session stayed short;
/// - the planner always took a slot's first catalog option, so a lift you do
///   as a variant (dumbbell curl, rope pushdown, barbell overhead press) was
///   swapped for one with no history, whose cautious first-time estimate
///   (`LoadEstimator`: 85%, for the top of the range) came out at about half
///   the weight, at 15 reps;
/// - an easier day took the load from the best e1RM with no limit.
struct UpperSessionReportTests {
    let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)

    func past(_ weight: Double, _ reps: Int, _ rpe: Double?, sets: Int = 3, best: Double? = nil) -> ExerciseHistory {
        ExerciseHistory(bestEstimatedOneRepMax: best ?? OneRepMax.estimate(weight: weight, reps: reps, rpe: rpe),
                        lastWeight: weight, lastReps: reps, lastRPE: rpe, lastDate: .now, recentWeights: [weight], lastSets: sets)
    }

    /// Last Upper session, logged with the variants this user does.
    var history: [String: ExerciseHistory] {
        [
            "Barbell_Bench_Press_-_Medium_Grip": past(82.5, 6, 8),
            "Bent_Over_Barbell_Row": past(60, 10, 8),
            "Standing_Military_Press": past(40, 8, 8),
            "Wide-Grip_Lat_Pulldown": past(65, 10, 8),
            "Dumbbell_Bicep_Curl": past(14, 12, 9),
            "Triceps_Pushdown_-_Rope_Attachment": past(25, 12, 9),
        ]
    }

    func plan(recovery: Int, week: Int, goals: [Muscle: Int]) -> PlannedWorkout {
        planner.plan(focus: .upper, minutes: 75, recovery: recovery, history: history,
                     block: TrainingBlock.weekState(week, style: .muscle, length: 6),
                     bodyMassKg: 85, trainingStatus: .intermediate, warmUpMinutes: 6,
                     muscleSetGoals: goals, includeCore: false)
    }

    @Test func seventyFiveMinuteUpperPlanMatchesLastSession() {
        let weekOneShare: [Muscle: Int] = [.chest: 5, .lats: 5, .shoulders: 5, .biceps: 5, .triceps: 5]
        let lateInWeek: [Muscle: Int] = [.chest: 3, .lats: 4, .shoulders: 3, .biceps: 2, .triceps: 2]
        for week in [1, 3] {
            for recovery in [40, 60, 80] {
                for goals in [[:], weekOneShare, lateInWeek] {
                    let workout = plan(recovery: recovery, week: week, goals: goals)
                    let label = "week \(week), recovery \(recovery), goals \(goals.values.reduce(0, +))"
                    // ~75 min of work, never over.
                    let minutes = workout.estimatedMinutes ?? 0
                    #expect((67...75).contains(minutes), "\(label): \(minutes) min")
                    // The variants you log are the ones planned (history, not a first-time estimate).
                    let ids = Set(workout.exercises.map(\.exerciseID))
                    for id in ["Standing_Military_Press", "Dumbbell_Bicep_Curl", "Triceps_Pushdown_-_Rope_Attachment"] {
                        #expect(ids.contains(id), "\(label): \(id) missing")
                    }
                    for exercise in workout.exercises {
                        let compound = ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound == true
                        #expect(exercise.sets >= (compound ? 3 : 2), "\(label): \(exercise.name) \(exercise.sets) sets")
                        guard let last = history[exercise.exerciseID], let load = exercise.load else { continue }
                        // Within 10% of last time: eased days a little lighter, never half.
                        #expect(load >= last.lastWeight * 0.9 - 0.001, "\(label): \(exercise.name) \(load) vs \(last.lastWeight)")
                        #expect(load <= last.lastWeight * 1.1 + 0.001, "\(label): \(exercise.name) \(load)")
                        // Double progression: about last time's reps (one more, or one fewer on an
                        // easier day at the same weight), or after a step up what the new weight
                        // allows (in the range, not more than last time's reps; audit 2026-11 §4).
                        let reps = exercise.repsToday
                        if load > last.lastWeight + 0.001 {
                            #expect(exercise.reps.contains(reps) && reps <= last.lastReps, "\(label): \(exercise.name) \(reps)")
                        } else {
                            #expect(abs(reps - last.lastReps) <= 1, "\(label): \(exercise.name) \(reps) vs \(last.lastReps)")
                        }
                    }
                }
            }
        }
    }

    /// The old estimate said the 18-set plan the user got (4 compounds × 3, 3 isolation × 2,
    /// ramps, a 6-min warm-up) was 74 min; with the last set's rest not counted twice it's
    /// about 62, so `fill` adds the sets 75 min holds.
    @Test func eighteenSetsDoNotFillSeventyFiveMinutes() {
        func ex(_ id: String, _ sets: Int, ramps: Int) -> PlannedExercise {
            var planned = PlannedExercise(exerciseID: id, name: id, sets: sets, reps: 6...10, rpe: 8, load: 50, loadKind: .barbell, note: nil)
            planned.warmUpSets = Array(repeating: WarmUp.RampSet(load: 20, reps: 5), count: ramps)
            return planned
        }
        let old = [ex("Barbell_Bench_Press_-_Medium_Grip", 3, ramps: 3), ex("Bent_Over_Barbell_Row", 3, ramps: 1),
                   ex("Dumbbell_Shoulder_Press", 3, ramps: 1), ex("Wide-Grip_Lat_Pulldown", 3, ramps: 1),
                   ex("Barbell_Curl", 2, ramps: 0), ex("Cable_Rope_Overhead_Triceps_Extension", 2, ramps: 0),
                   ex("Side_Lateral_Raise", 2, ramps: 0)]
        let minutes = WorkoutPlanner.estimatedMinutes(old, style: .muscle, warmUpMinutes: 6)
        #expect(minutes < 64)
        let planned = plan(recovery: 60, week: 1, goals: [:])
        #expect(planned.totalSets >= 22)
    }

    /// Easing for low recovery is about one more rep in reserve: at most 10% off last time,
    /// however high an older best e1RM sat, and on a coarse stack the same weight, one rep fewer.
    @Test func anEasierDayIsAFewPercentNotHalf() {
        // An e1RM from an old high-rep set that says ~60 kg at today's reserve.
        let bench = past(82.5, 6, 8, best: 85)
        let eased = planner.progression(history: bench, reps: 6...10, rpe: 6.5, kind: .barbell)
        #expect(eased?.load == 75)   // 74.25 is the floor; 75 is the first load at or over it
        // Rope pushdown on 5 kg steps: 22.5 isn't loadable, 20 would be 20% off.
        let pushdown = past(25, 12, 9)
        let held = planner.progression(history: pushdown, reps: 10...15, rpe: 8, kind: .cable, mode: .reps)
        #expect(held == WorkoutPlanner.Progression(load: 25, targetReps: 11))
        #expect(planner.progressionNote(load: 25, history: pushdown, reps: 10...15, mode: .reps, rpe: 8)
                == "Same weight, 11 reps for today's effort")
    }

    /// A deload week is meant to be short: 2 sets allowed on everything, and the builder says why.
    @Test func deloadIsShortAndSaysSo() {
        let deload = plan(recovery: 80, week: 6, goals: [:])
        #expect(deload.exercises.allSatisfy { $0.sets == 2 })
        #expect(deload.lengthNote?.hasPrefix("Deload week") == true)
        #expect(plan(recovery: 80, week: 1, goals: [:]).lengthNote == nil)
    }

    /// A logged variant is preferred, but not over a pain regression.
    @Test func loggedVariantYieldsToPainRegression() {
        #expect(planner.choose(.biceps, excluding: [], history: history)?.id == "Dumbbell_Bicep_Curl")
        // With no history the default curl is the dumbbell one; a logged barbell curl is kept.
        #expect(planner.choose(.biceps, excluding: [], history: [:])?.id == "Dumbbell_Bicep_Curl")
        let barbell = ["Barbell_Curl": ExerciseHistory(bestEstimatedOneRepMax: 40, lastWeight: 30, lastReps: 8, lastRPE: 8, lastDate: .now)]
        #expect(planner.choose(.biceps, excluding: [], history: barbell)?.id == "Barbell_Curl")
        var guarded = planner
        guarded.exerciseFilter = ExerciseFilter(pains: [PainReport(area: .lowerBack, level: 4, worseAfterTraining: nil, loggedAt: .now)])
        #expect(guarded.choose(.horizontalRow, excluding: [], history: history)?.id == "Seated_Cable_Rows")
    }
}
