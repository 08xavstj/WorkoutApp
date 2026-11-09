import Foundation
import Testing
@testable import AppCore

struct WorkoutSummaryTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func set(_ weight: Double, _ reps: Int, rpe: Double? = nil, warmup: Bool = false,
                     stage: Bool = false, at minute: Double? = nil, done: Bool = true) -> WorkoutSummary.LoggedSet {
        let time = minute.map { start.addingTimeInterval($0 * 60) } ?? (done ? start : nil)
        return WorkoutSummary.LoggedSet(weightKg: weight, reps: reps, rpe: rpe, isWarmup: warmup, isStage: stage,
                                        completedAt: done ? time : nil)
    }

    private func exercise(_ id: String, _ sets: [WorkoutSummary.LoggedSet]) -> WorkoutSummary.LoggedExercise {
        WorkoutSummary.LoggedExercise(exerciseID: id, name: id.capitalized, sets: sets)
    }

    private func session(_ name: String, daysAgo: Double = 0, minutes: Double = 60,
                         _ exercises: [WorkoutSummary.LoggedExercise]) -> WorkoutSummary.LoggedSession {
        let begin = start.addingTimeInterval(-daysAgo * 86_400)
        return WorkoutSummary.LoggedSession(name: name, start: begin, end: begin.addingTimeInterval(minutes * 60), exercises: exercises)
    }

    @Test func totalsCountWorkingSetsOnly() {
        let today = session("Push", [
            exercise("bench", [set(40, 8, warmup: true), set(60, 8), set(60, 8), set(60, 7)]),
            // A drop set: the stage adds volume and reps but not a set.
            exercise("fly", [set(20, 10), set(12, 8, stage: true)]),
            // Never ticked: not counted, and not an exercise done.
            exercise("dip", [set(0, 10, done: false)]),
        ])
        let totals = WorkoutSummary.totals(today)
        #expect(totals.volumeKg == 60 * 23 + 200 + 96)
        #expect(totals.workingSets == 4)
        #expect(totals.reps == 23 + 18)
        #expect(totals.exercises == 2)
        #expect(totals.duration == 3600)
    }

    @Test func typicalRestIsTheMedianGap() {
        let today = session("Push", [
            exercise("bench", [set(60, 8, at: 0), set(60, 8, at: 2), set(60, 8, at: 5), set(60, 8, at: 7)]),
            // A 20-minute break isn't rest between sets; a stage gap is skipped.
            exercise("fly", [set(20, 10, at: 27), set(12, 8, stage: true, at: 27.3), set(20, 10, at: 29.5)]),
        ])
        // Gaps 2, 3, 2, 2.2 min → median 2.1 min.
        let rest = WorkoutSummary.typicalRest(today)
        #expect(rest.map { abs($0 - 126) < 0.001 } == true)
        let tooFew = session("Push", [exercise("bench", [set(60, 8, at: 0), set(60, 8, at: 2)])])
        #expect(WorkoutSummary.typicalRest(tooFew) == nil)
    }

    @Test func exerciseResultGroupsSetsAndFindsTheBest() {
        let today = session("Push", [
            exercise("bench", [set(60, 8), set(60, 8), set(65, 5, rpe: 8), set(60, 6)]),
        ])
        let result = WorkoutSummary.exerciseResults(today)
        #expect(result.count == 1)
        let bench = result[0]
        #expect(bench.workingSets == 4)
        #expect(bench.groups == [
            .init(weightKg: 60, reps: 8, count: 2), .init(weightKg: 65, reps: 5, count: 1), .init(weightKg: 60, reps: 6, count: 1),
        ])
        // 65 × (5 + 2 in reserve) beats 60 × 8: 65 × (1 + 7/30) ≈ 80.2.
        #expect(bench.bestSet?.weightKg == 65)
        #expect(abs(bench.estimatedOneRepMaxKg - 65 * (1 + 7.0 / 30)) < 0.001)
    }

    @Test func bodyweightBestSetIsMostReps() {
        let today = session("Pull", [exercise("pullup", [set(0, 8), set(0, 10), set(0, 7)])])
        let result = WorkoutSummary.exerciseResults(today)[0]
        #expect(result.bestSet?.reps == 10)
        #expect(result.estimatedOneRepMaxKg == 0)
    }

    @Test func previousFindsTheLatestEarlierSession() {
        let old = session("Push", daysAgo: 7, [exercise("bench", [set(55, 8)])])
        let recent = session("Push", daysAgo: 3, [exercise("bench", [set(57.5, 8)]), exercise("bench", [set(57.5, 6)])])
        let other = session("Legs", daysAgo: 1, [exercise("squat", [set(100, 5)])])
        let found = WorkoutSummary.previous(exerciseID: "bench", before: start, in: [old, recent, other])
        #expect(found?.date == recent.start)
        #expect(found?.exercise.sets.count == 2)
        #expect(WorkoutSummary.previous(exerciseID: "row", before: start, in: [old, recent]) == nil)
    }

    @Test func changeNamesTheProgressionEarned() {
        let last = exercise("bench", [set(60, 8), set(60, 8), set(60, 7)])
        // One more rep at the same weight.
        let moreReps = WorkoutSummary.change(today: exercise("bench", [set(60, 8), set(60, 8), set(60, 8)]), last: last, lastDate: start)
        #expect(moreReps?.progression == .moreReps(1))
        #expect(moreReps?.volumeKg == 60)
        // Heavier top set.
        let heavier = WorkoutSummary.change(today: exercise("bench", [set(62.5, 8), set(62.5, 7), set(62.5, 6)]), last: last, lastDate: start)
        #expect(heavier?.progression == .heavier(kg: 2.5))
        #expect((heavier?.estimatedOneRepMaxKg ?? 0) > 0)
        // Same sets and reps plus one set.
        let moreSets = WorkoutSummary.change(today: exercise("bench", [set(60, 8), set(60, 8), set(60, 7), set(55, 8)]), last: last, lastDate: start)
        #expect(moreSets?.progression == .moreSets(1))
        // Lighter: no progression, volume down.
        let lighter = WorkoutSummary.change(today: exercise("bench", [set(55, 8)]), last: last, lastDate: start)
        #expect(lighter?.progression == nil)
        #expect((lighter?.volumeKg ?? 0) < 0)
    }

    @Test func bodyweightChangeHasNoOneRepMax() {
        let change = WorkoutSummary.change(today: exercise("pullup", [set(0, 10)]), last: exercise("pullup", [set(0, 8)]), lastDate: start)
        #expect(change?.estimatedOneRepMaxKg == nil)
        #expect(change?.progression == .moreReps(2))
    }

    @Test func comparableSessionBySameNameOrOverlap() {
        let today = session("Upper A", [exercise("bench", [set(60, 8)]), exercise("row", [set(50, 8)])])
        let sameName = session("upper a", daysAgo: 6, [exercise("bench", [set(60, 8)])])
        let overlap = session("Workout", daysAgo: 2, [exercise("bench", [set(60, 8)]), exercise("row", [set(50, 8)]), exercise("curl", [set(12, 10)])])
        let unrelated = session("Legs", daysAgo: 1, [exercise("squat", [set(100, 5)])])
        // Newest match first: 2 of 3 exercises shared (0.67).
        #expect(WorkoutSummary.comparableSession(to: today, in: [sameName, overlap, unrelated]) == overlap)
        #expect(WorkoutSummary.comparableSession(to: today, in: [sameName, unrelated]) == sameName)
        #expect(WorkoutSummary.comparableSession(to: today, in: [unrelated]) == nil)
        // A later session is never "last time".
        let later = WorkoutSummary.LoggedSession(name: "Upper A", start: start.addingTimeInterval(86_400),
                                                 end: start.addingTimeInterval(90_000), exercises: today.exercises)
        #expect(WorkoutSummary.comparableSession(to: today, in: [later]) == nil)
    }

    @Test func sessionChangeComparesVolumeAndDuration() {
        let today = session("Push", minutes: 55, [exercise("bench", [set(60, 10)])])
        let last = session("Push", daysAgo: 4, minutes: 60, [exercise("bench", [set(60, 8)])])
        let change = WorkoutSummary.sessionChange(today: today, last: last)
        #expect(change.volumeKg == 120)
        #expect(change.duration == -300)
    }

    @Test func muscleLinesShowTheWeekMoving() {
        let lines = WorkoutSummary.muscleLines(
            sessionSets: [.chest: 4, .triceps: 2, .shoulders: 0.25],
            weekBefore: [.chest: 7, .triceps: 18],
            targets: [.triceps: 12...14]
        )
        #expect(lines.map(\.muscle) == [.chest, .triceps])
        #expect(lines[0].status == .reached)
        #expect(lines[0].weekAfter == 11)
        #expect(lines[0].target == 10...20)
        #expect(lines[1].status == .above)
        let below = WorkoutSummary.muscleLines(sessionSets: [.biceps: 3], weekBefore: [:])
        #expect(below.first?.status == .below)
        let inRange = WorkoutSummary.muscleLines(sessionSets: [.biceps: 3], weekBefore: [.biceps: 11])
        #expect(inRange.first?.status == .inRange)
    }

    @Test func goalFractionIsClamped() {
        #expect(WorkoutSummary.goalFraction(currentKg: 90, targetKg: 100) == 0.9)
        #expect(WorkoutSummary.goalFraction(currentKg: 110, targetKg: 100) == 1)
        #expect(WorkoutSummary.goalFraction(currentKg: 0, targetKg: 100) == 0)
    }

    @Test func comparisonIsRoughAndOnlyForRealTotals() {
        #expect(WorkoutSummary.comparison(volumeKg: 150) == nil)
        #expect(WorkoutSummary.comparison(volumeKg: 1_200)?.text == "About the weight of a small car")
        #expect(WorkoutSummary.comparison(volumeKg: 4_800)?.text == "About 3 hippos")
        #expect(WorkoutSummary.comparison(volumeKg: 9_000)?.text == "About 2 elephants")
    }
}
