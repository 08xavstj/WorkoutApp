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
        #expect(down?.message(unit: "kg") == "Next set 57.5 kg (you went to failure; plan: 2 in reserve)")
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
        #expect(trim?.message(unit: "kg") == "Next set 9 reps, same weight (you went to failure; plan: 2 in reserve)")
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
        // Changed with double progression: the note names today's rep target;
        // 20 → 25 lb dumbbells is a big jump, so the top moves to 14.
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12, loadKind: .dumbbell)
                == "Same weight, aim for 13 reps; it moves up at 14")
        // Changed with real rep and set progression: the note names today's target.
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12, mode: .reps)
                == "Same weight as last time: aim for 13 reps; it moves up at 14")
        #expect(planner.progressionNote(load: 20, history: held, reps: 10...12, mode: .sets)
                == "Same weight: hit 12 reps to add a set; it moves up at 5 sets")
        var three = held
        three.lastSets = 3
        #expect(planner.progressionNote(load: 20, history: three, reps: 10...12, mode: .sets)
                == "Same weight, one more set: you hit 12 reps; it moves up at 5 sets")
        // The big-jump tip is for load progression only.
        #expect(planner.notes(load: 20, history: held, reps: 10...12, rpe: 9, kind: .dumbbell, mode: .reps) == "20 lb each hand")
    }

    @Test func plannerUsesYourChoice() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .reps]
        let plan = planner.plan(focus: .push, minutes: 45, recovery: 80, history: [benchID: bench])
        #expect(plan.exercises.first?.exerciseID == benchID)
        #expect(plan.exercises.first?.load == 185)
        #expect(plan.exercises.first?.progressionNote == "Same weight as last time: aim for 9 reps; it moves up at 10")
        // The live session pre-fills the top of the range: 9 today.
        #expect(plan.exercises.first?.reps == 6...9)
    }
}

/// Rep and set progression over several sessions, and one easier day in between.
struct ProgressionRuleTests {
    let gym = GymProfile.commercialPounds
    let benchID = "Barbell_Bench_Press_-_Medium_Grip"

    private func history(weight: Double, reps: Int, rpe: Double? = 8, sets: Int? = 3,
                         recent: [Double] = []) -> ExerciseHistory {
        ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: weight, lastReps: reps, lastRPE: rpe, lastDate: .now,
                        recentWeights: recent + [weight], lastSets: sets)
    }

    private func bench(_ planner: WorkoutPlanner, _ past: ExerciseHistory, rpe: Double = 8) -> PlannedExercise {
        let choice = CatalogExercise(id: benchID, name: "Bench Press", load: .barbell, requires: [.barbell, .bench])
        return planner.prescribe(choice, slot: .horizontalPress, minutes: 45, sessionRPE: rpe, history: [benchID: past])
    }

    @Test func repProgressionAddsARepThenTheWeight() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .reps]
        // 6-8 reps. Last time 185 × 7: today aims for the top of the range.
        let seven = bench(planner, history(weight: 185, reps: 7))
        #expect(seven.load == 185)
        #expect(seven.reps == 6...8)
        // 185 × 8 → 9 today, 185 × 9 → 10 today (2 past the range is the most).
        #expect(bench(planner, history(weight: 185, reps: 8)).reps == 6...9)
        #expect(bench(planner, history(weight: 185, reps: 9)).reps == 6...10)
        // 185 × 10: one step up and back to the range.
        let up = bench(planner, history(weight: 185, reps: 10))
        #expect(up.load == 190)
        #expect(up.reps == 6...8)
    }

    @Test func setProgressionAddsASetThenTheWeight() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .sets]
        // Top of the range at the target: one more set than last time.
        let four = bench(planner, history(weight: 185, reps: 8, sets: 3))
        #expect(four.load == 185)
        #expect(four.sets == 4)
        #expect(bench(planner, history(weight: 185, reps: 8, sets: 4)).sets == 5)
        // Short of the top, or too hard: hold the sets.
        #expect(bench(planner, history(weight: 185, reps: 7, sets: 4)).sets == 4)
        #expect(bench(planner, history(weight: 185, reps: 8, rpe: 9, sets: 4)).load ?? 0 < 185)
        // Five sets at the top of the range: up a step, back to the usual sets.
        let up = bench(planner, history(weight: 185, reps: 8, sets: 5))
        #expect(up.load == 190)
        #expect(up.sets == WorkoutPlanner.baseSets(compound: true, minutes: 45))
    }

    @Test func setProgressionSurvivesTheBlockButNotTheDeload() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .sets]
        let earned = history(weight: 185, reps: 8, rpe: 7, sets: 4)
        let notYet = history(weight: 185, reps: 7, rpe: 7, sets: 4)
        let build = TrainingBlock.weekState(1, style: .balanced, length: 5)
        func benchSets(_ past: ExerciseHistory, _ week: TrainingBlock.WeekState) -> Int {
            let plan = planner.plan(focus: .push, minutes: 60, recovery: 80, history: [benchID: past], block: week)
            return plan.exercises.first { $0.exerciseID == benchID }?.sets ?? 0
        }
        // The earned set is kept through the block's scaling (the time fit may still trim).
        #expect(benchSets(earned, build) > benchSets(notYet, build))
        // The deload cuts the base sets as usual, with no set added.
        let deload = TrainingBlock.weekState(5, style: .balanced, length: 5)
        let base = WorkoutPlanner.baseSets(compound: true, minutes: 60)
        #expect(benchSets(earned, deload) == TrainingBlock.scaledSets(base, multiplier: deload.setMultiplier))
    }

    @Test func oneEasierDayDoesNotLowerTheWeightForGood() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .reps]
        // Deload week: a lower effort target, so lighter today only.
        let normal = history(weight: 185, reps: 8, rpe: 8)
        let deloadDay = bench(planner, normal, rpe: 7)
        let deloadLoad = deloadDay.load ?? 185
        #expect(deloadLoad < 185)
        // The week after: last time was the lighter deload weight at RPE 7,
        // but 185 was the heaviest of the last sessions, so it comes back
        // (without a step for the easy reps).
        let after = history(weight: deloadLoad, reps: 8, rpe: 7, recent: [185, 185])
        let back = bench(planner, after)
        #expect(back.load == 185)
        #expect(back.reps == 6...8)
        #expect(back.progressionNote?.hasPrefix("Back to 185 lb") == true)
        #expect(planner.suggestedLoad(history: after, reps: 6...8, rpe: 8, kind: .barbell, mode: .sets) == 185)
    }

    @Test func aPainCapIsForThatDayOnly() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .reps]
        // Wrist pain at 4/10 capped bench about 20% lighter last time.
        let filter = ExerciseFilter(pains: [PainReport(area: .wrist, level: 4, loggedAt: .now)])
        var capped = bench(planner, history(weight: 185, reps: 8))
        filter.capLoad(&capped, slot: .horizontalPress, gym: gym)
        let cappedLoad = capped.load ?? 0
        #expect(cappedLoad <= 185 * PainGuard.loadCapFraction)
        #expect(capped.maxLoadKg == gym.unit.toKilograms(cappedLoad))
        // Pain gone: the next session goes back to 185, not the capped weight.
        let after = history(weight: cappedLoad, reps: 8, recent: [185, 185])
        #expect(bench(planner, after).load == 185)
        // Older sessions drop out: three lighter sessions in a row are the new level.
        let settled = history(weight: 155, reps: 8, recent: [155, 155])
        #expect(bench(planner, settled).load == 155)
    }

    @Test func historyKeepsTheLastThreeWeights() {
        #expect(ExerciseHistory.appending(100, to: [80, 85, 90]) == [85, 90, 100])
        let past = ExerciseHistory(bestEstimatedOneRepMax: 100, lastWeight: 70, lastReps: 8, lastRPE: 8, lastDate: .now,
                                   recentWeights: [60, 90, 80, 70])
        #expect(past.recentWeights == [90, 80, 70])
        #expect(past.recentHeaviestWeight == 90)
        #expect(past.lastWasLighter)
    }

    @Test func templatesFollowTheProgressionMode() {
        var planner = WorkoutPlanner(gym: gym)
        planner.progressionModes = [benchID: .reps]
        let item = TemplateItem(exerciseID: benchID, name: "Bench Press", sets: 3, reps: 6...8)
        let past = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)
        // Load progression would go to 190; rep progression holds 185. Your own sets and reps stay.
        let planned = planner.prescribe(template: [item], history: [benchID: past])
        #expect(planned.first?.load == 185)
        #expect(planned.first?.reps == 6...8)
        #expect(planned.first?.sets == 3)
    }

    @Test func plannedExerciseDecodesWithoutACap() throws {
        let exercise = PlannedExercise(exerciseID: "x", name: "X", sets: 3, reps: 8...10, rpe: 8, load: 50, loadKind: .barbell, note: nil)
        var json = try #require(String(data: JSONEncoder().encode(exercise), encoding: .utf8))
        #expect(!json.contains("maxLoadKg"))
        json = json.replacingOccurrences(of: "}", with: ",\"maxLoadKg\":40}")
        let capped = try JSONDecoder().decode(PlannedExercise.self, from: Data(json.utf8))
        #expect(capped.maxLoadKg == 40)
    }
}
