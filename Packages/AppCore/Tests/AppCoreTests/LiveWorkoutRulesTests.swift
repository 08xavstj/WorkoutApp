import Foundation
import Testing
@testable import AppCore

struct LiveWorkoutRulesTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Watch ticks

    @Test func editedOnTheWristWins() {
        #expect(LiveWorkoutRules.tickedValue(phone: 60, watch: 65, watchBase: 60, edited: true, autoregulatedFrom: nil) == 65)
    }

    @Test func untouchedValueKeepsAPhoneEdit() {
        // The phone was changed to 62.5 by hand after the Watch's snapshot: keep it.
        #expect(LiveWorkoutRules.tickedValue(phone: 62.5, watch: 60, watchBase: 60, edited: false, autoregulatedFrom: nil) == 62.5)
    }

    @Test func untouchedValueBeatsAnUnseenAutoregulation() {
        // Set 1's queued tick moved set 2 from 60 to 62.5 on the phone; the wrist
        // lifted the 60 it showed, so set 2 logs 60.
        #expect(LiveWorkoutRules.tickedValue(phone: 62.5, watch: 60, watchBase: 60, edited: false, autoregulatedFrom: 60) == 60)
    }

    @Test func autoregulationTheWatchSawStays() {
        // The Watch's snapshot already had the 62.5: nothing to undo.
        #expect(LiveWorkoutRules.tickedValue(phone: 62.5, watch: 62.5, watchBase: 62.5, edited: false, autoregulatedFrom: 60) == 62.5)
    }

    @Test func olderWatchesWithoutFlagsKeepTheOldRule() {
        #expect(LiveWorkoutRules.tickedValue(phone: 60, watch: 65, watchBase: nil, edited: nil, autoregulatedFrom: nil) == 65)
        #expect(LiveWorkoutRules.tickedValue(phone: 60, watch: 0, watchBase: nil, edited: nil, autoregulatedFrom: nil) == 60)
    }

    @Test func tickTimeIsWhenTheWatchSentIt() {
        let now = start.addingTimeInterval(1800)
        let sent = start.addingTimeInterval(600)
        #expect(LiveWorkoutRules.completedAt(sentAt: sent, sessionStart: start, now: now) == sent)
        #expect(LiveWorkoutRules.completedAt(sentAt: start.addingTimeInterval(-60), sessionStart: start, now: now) == start)
        #expect(LiveWorkoutRules.completedAt(sentAt: now.addingTimeInterval(30), sessionStart: start, now: now) == now)
    }

    @Test func lateTickGetsOnlyTheRestLeft() {
        let now = start.addingTimeInterval(1000)
        #expect(LiveWorkoutRules.remainingRest(seconds: 120, sentAt: now.addingTimeInterval(-30), now: now) == 90)
        #expect(LiveWorkoutRules.remainingRest(seconds: 120, sentAt: now.addingTimeInterval(-300), now: now) == nil)
        #expect(LiveWorkoutRules.remainingRest(seconds: 120, sentAt: now, now: now) == 120)
    }

    // MARK: Ending

    @Test func forgottenAfterFourHoursWithoutATick() {
        let lastTick = start.addingTimeInterval(3600)
        #expect(!LiveWorkoutRules.isForgotten(start: start, lastTick: lastTick, now: lastTick.addingTimeInterval(3 * 3600)))
        #expect(LiveWorkoutRules.isForgotten(start: start, lastTick: lastTick, now: lastTick.addingTimeInterval(4 * 3600)))
        #expect(LiveWorkoutRules.isForgotten(start: start, lastTick: nil, now: start.addingTimeInterval(5 * 3600)))
    }

    @Test func watchFinishSetsTheEnd() {
        let now = start.addingTimeInterval(5 * 3600)
        let finished = start.addingTimeInterval(3600)
        #expect(LiveWorkoutRules.endDate(start: start, watchFinishedAt: finished, lastTick: start.addingTimeInterval(3000), now: now) == finished)
        // A set logged on the phone after the Watch finished: the end moves to it.
        let later = start.addingTimeInterval(4000)
        #expect(LiveWorkoutRules.endDate(start: start, watchFinishedAt: finished, lastTick: later, now: now) == later)
        #expect(LiveWorkoutRules.endDate(start: start, watchFinishedAt: nil, lastTick: later, now: now) == now)
    }

    // MARK: Orders and typing

    @Test func addedExerciseNeverReusesARemovedOrder() {
        #expect(LiveWorkoutRules.nextOrder(existing: [0, 1], highestUsed: 3) == 4)
        #expect(LiveWorkoutRules.nextOrder(existing: [0, 1, 2], highestUsed: nil) == 3)
        #expect(LiveWorkoutRules.nextOrder(existing: [], highestUsed: nil) == 0)
    }

    @Test func typedNumbersAcceptCommaOrPoint() {
        #expect(LiveWorkoutRules.parseNumber("62.5") == 62.5)
        #expect(LiveWorkoutRules.parseNumber(" 62,5 ") == 62.5)
        #expect(LiveWorkoutRules.parseNumber("") == nil)
        #expect(LiveWorkoutRules.parseNumber("abc") == nil)
        #expect(LiveWorkoutRules.parseNumber("-5") == 0)
    }

    // MARK: Prefill

    @Test func addedExerciseStartsFromLastTime() {
        let history = ExerciseHistory(bestEstimatedOneRepMax: 80, lastWeight: 60, lastReps: 8, lastRPE: 8,
                                      lastDate: start, lastSets: 4)
        #expect(LiveWorkoutRules.prefill(history: history) == .init(sets: 4, weight: 60, reps: 8))
        #expect(LiveWorkoutRules.prefill(history: history, sets: 3) == .init(sets: 3, weight: 60, reps: 8))
        #expect(LiveWorkoutRules.prefill(history: nil) == .init(sets: 1, weight: 0, reps: 0))
        #expect(LiveWorkoutRules.prefill(history: nil, sets: 3) == .init(sets: 3, weight: 0, reps: 0))
    }

    // MARK: Bodyweight

    @Test func pullUpLoadCountsBodyMass() {
        #expect(BodyweightLoad.load(exerciseID: "Pullups", loggedKg: 10, bodyMassKg: 80) == 90)
        #expect(BodyweightLoad.load(exerciseID: "Pullups", loggedKg: 0, bodyMassKg: nil) == 0)
        // A push-up moves only part of the body: no body mass added.
        #expect(BodyweightLoad.load(exerciseID: "Pushups", loggedKg: 0, bodyMassKg: 80) == 0)
    }
}

struct LiveSwapTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func swapOptionsShareTheMovementAndFollowTheFilters() {
        var planner = WorkoutPlanner(gym: .commercialPounds)
        let bench = "Barbell_Bench_Press_-_Medium_Grip"
        let all = LiveSwap.options(for: bench, planner: planner)
        #expect(!all.isEmpty)
        #expect(!all.contains { $0.id == bench })
        #expect(all.allSatisfy { ExerciseCatalog.slot(for: $0.id) == .horizontalPress })
        // Never again, and already in the session, are left out.
        let first = all[0].id
        planner.exerciseFilter = ExerciseFilter(neverAgain: [first])
        #expect(!LiveSwap.options(for: bench, planner: planner).contains { $0.id == first })
        #expect(!LiveSwap.options(for: bench, planner: WorkoutPlanner(gym: .commercialPounds), excluding: [first])
            .contains { $0.id == first })
    }

    @Test func swapOptionsOnlyWhatTheGymHas() {
        let planner = WorkoutPlanner(gym: .homeDumbbells)
        let options = LiveSwap.options(for: "Barbell_Bench_Press_-_Medium_Grip", planner: planner)
        #expect(options.allSatisfy { $0.requires.allSatisfy { planner.gym.has($0) } })
    }

    @Test func swappedInLiftKeepsTheSetCountAndUsesHistory() throws {
        let planner = WorkoutPlanner(gym: .commercialPounds)
        let choice = try #require(ExerciseCatalog.exercise(id: "Dumbbell_Bench_Press"))
        let history = ["Dumbbell_Bench_Press": ExerciseHistory(bestEstimatedOneRepMax: 80, lastWeight: 60, lastReps: 8,
                                                                lastRPE: 7, lastDate: now)]
        let planned = try #require(LiveSwap.prescription(for: choice, planner: planner, sets: 4, sessionRPE: 7.5, history: history))
        #expect(planned.sets == 4)
        #expect(planned.exerciseID == "Dumbbell_Bench_Press")
        #expect((planned.load ?? 0) > 0)
    }

    @Test func libraryExerciseStartsFromLastTime() {
        let history = ExerciseHistory(bestEstimatedOneRepMax: 40, lastWeight: 30, lastReps: 12, lastRPE: 8,
                                      lastDate: now, lastSets: 3)
        let planned = LiveSwap.prefilled(exerciseID: "Some_Library_Lift", name: "Some Lift", history: history, rpe: 8)
        #expect(planned.sets == 3)
        #expect(planned.load == 30)
        #expect(planned.repsToday == 12)
        let fresh = LiveSwap.prefilled(exerciseID: "Some_Library_Lift", name: "Some Lift", history: nil, rpe: 8)
        #expect(fresh.sets == 1)
        #expect(fresh.load == nil)
        #expect(fresh.repsToday == 0)
    }
}
