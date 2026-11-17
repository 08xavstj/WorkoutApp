import Foundation
import Testing
@testable import AppCore

struct LiveWorkoutRulesTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Watch ticks

    /// Watch out of reach, plan 3 × 8. Two queued ratings each moved set 3's
    /// goal on the phone (8 → 7 → 6); the wrist still showed 8 and that's
    /// what was lifted, so the unedited tick logs 8, not the phone's 6.
    @Test func twoQueuedGoalChangesStillLogWhatTheWristShowed() {
        #expect(LiveWorkoutRules.tickedValue(phone: 6, watch: 8, watchBase: 8, edited: false, autoregulatedFromAny: [7, 8]) == 8)
        // Only the latest change known (as before): the phone's goal was logged.
        #expect(LiveWorkoutRules.tickedValue(phone: 6, watch: 8, watchBase: 8, edited: false, autoregulatedFrom: 7) == 6)
        // The Watch had already seen the first change: 7 was shown and lifted.
        #expect(LiveWorkoutRules.tickedValue(phone: 6, watch: 7, watchBase: 7, edited: false, autoregulatedFromAny: [7, 8]) == 7)
        // No set-by-set change at all: the phone's value may be a newer edit.
        #expect(LiveWorkoutRules.tickedValue(phone: 10, watch: 8, watchBase: 8, edited: false, autoregulatedFromAny: []) == 10)
    }

    // MARK: Pauses

    @Test func pausedTimeStaysOffTheClock() {
        let pause = start.addingTimeInterval(600)
        // Paused at 10:00: the clock stands still.
        #expect(LiveWorkoutRules.elapsed(start: start, now: pause.addingTimeInterval(120), pausedFinished: 0, pausedSince: pause) == 600)
        // Resumed after 2 minutes: it carries on from where it stopped.
        #expect(LiveWorkoutRules.elapsed(start: start, now: start.addingTimeInterval(900), pausedFinished: 120, pausedSince: nil) == 780)
        #expect(LiveWorkoutRules.pausedSeconds(finished: 120, pausedSince: pause, now: pause.addingTimeInterval(30)) == 150)
        // Never below zero, whatever the clocks say.
        #expect(LiveWorkoutRules.elapsed(start: start, now: start.addingTimeInterval(10), pausedFinished: 60, pausedSince: nil) == 0)
        #expect(LiveWorkoutRules.pausedSeconds(finished: 0, pausedSince: pause, now: pause.addingTimeInterval(-5)) == 0)
    }

    // MARK: Supersets

    @Test func warmUpTickStaysOnItsOwnLift() {
        // A1 has a ramp set, A2 none. A1's warm-up ticked: no round done yet, A1's first working set is next.
        let a1 = LiveWorkoutRules.SupersetHalf(order: 0, roundsDone: 0, hasOpenSet: true)
        let a2 = LiveWorkoutRules.SupersetHalf(order: 1, roundsDone: 0, hasOpenSet: true)
        #expect(!LiveWorkoutRules.partnerIsNext(ticked: a1, partner: a2))
    }

    @Test func supersetAlternatesByRounds() {
        func half(_ order: Int, _ rounds: Int, open: Bool = true, stage: Bool = false) -> LiveWorkoutRules.SupersetHalf {
            LiveWorkoutRules.SupersetHalf(order: order, roundsDone: rounds, hasOpenSet: open, nextIsStage: stage)
        }
        // A1 set 1 done: A2 next. A2 set 1 done: back to A1.
        #expect(LiveWorkoutRules.partnerIsNext(ticked: half(0, 1), partner: half(1, 0)))
        #expect(LiveWorkoutRules.partnerIsNext(ticked: half(1, 1), partner: half(0, 1)))
        // Only A2 has a ramp set: its warm-up ticked after A1's set 1 keeps A2 up.
        #expect(!LiveWorkoutRules.partnerIsNext(ticked: half(1, 0), partner: half(0, 1)))
        // A drop stage of the set just done comes before the partner.
        #expect(!LiveWorkoutRules.partnerIsNext(ticked: half(0, 1, stage: true), partner: half(1, 0)))
        // The partner is finished: stay. This lift is finished: the partner's sets are next.
        #expect(!LiveWorkoutRules.partnerIsNext(ticked: half(0, 3), partner: half(1, 2, open: false)))
        #expect(LiveWorkoutRules.partnerIsNext(ticked: half(1, 2, open: false), partner: half(0, 2)))
    }

    // MARK: Weights changed by hand

    @Test func typedWeightCarriesToTheSetsStillAtTheOldOne() {
        typealias Slot = LiveWorkoutRules.WeightSlot
        // A first-time lift: every set at 0. The weight typed on set 1 fills the rest.
        let fresh = [Slot(weightKg: 0), Slot(weightKg: 0), Slot(weightKg: 0)]
        #expect(LiveWorkoutRules.indicesTakingWeight(changed: 0, oldKg: 0, in: fresh) == [1, 2])
        // Warm-ups, ticked sets, drop stages and a set at another weight stay as they are.
        let mixed = [Slot(weightKg: 40, isWarmup: true), Slot(weightKg: 60, isCompleted: true), Slot(weightKg: 60),
                     Slot(weightKg: 60), Slot(weightKg: 65), Slot(weightKg: 60, isStage: true)]
        #expect(LiveWorkoutRules.indicesTakingWeight(changed: 2, oldKg: 60, in: mixed) == [3])
        // Earlier sets never change, and a warm-up's or a stage's weight carries nowhere.
        #expect(LiveWorkoutRules.indicesTakingWeight(changed: 3, oldKg: 60, in: mixed).isEmpty)
        #expect(LiveWorkoutRules.indicesTakingWeight(changed: 0, oldKg: 60, in: mixed).isEmpty)
        #expect(LiveWorkoutRules.indicesTakingWeight(changed: 5, oldKg: 60, in: mixed).isEmpty)
        #expect(LiveWorkoutRules.indicesTakingWeight(changed: 9, oldKg: 60, in: mixed).isEmpty)
    }

    // MARK: A set in words

    @Test func aSetWithNoWeightNeverReadsZero() {
        #expect(LiveWorkoutRules.setText(weight: "60 kg", reps: 8, isBodyweight: false) == "60 kg × 8")
        #expect(LiveWorkoutRules.setText(weight: "20 kg per hand", reps: 10, isBodyweight: false) == "20 kg per hand × 10")
        #expect(LiveWorkoutRules.setText(weight: nil, reps: 8, isBodyweight: true) == "Bodyweight × 8")
        // A loaded lift whose weight isn't in yet: just the reps.
        #expect(LiveWorkoutRules.setText(weight: nil, reps: 8, isBodyweight: false) == "8 reps")
        #expect(LiveWorkoutRules.setText(weight: nil, reps: 1, isBodyweight: false) == "1 rep")
        #expect(LiveWorkoutRules.isBodyweight(exerciseID: "Pullups"))
        #expect(!LiveWorkoutRules.isBodyweight(exerciseID: "Barbell_Bench_Press_-_Medium_Grip"))
        // Outside the catalog nothing is known about its load.
        #expect(!LiveWorkoutRules.isBodyweight(exerciseID: "Some_Library_Lift"))
    }

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
