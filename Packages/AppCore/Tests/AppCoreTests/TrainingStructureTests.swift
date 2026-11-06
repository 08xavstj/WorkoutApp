import Foundation
import Testing
@testable import AppCore

struct TrainingBlockTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Monday 2 November 2026, 00:00 UTC.
    var monday: Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 2))! }

    func days(_ offset: Int) -> Date { utc.date(byAdding: .day, value: offset, to: monday)! }

    @Test func lengthFollowsTheGoal() {
        #expect(TrainingBlock.length(for: .strength) == 5)
        #expect(TrainingBlock.length(for: .balanced) == 5)
        #expect(TrainingBlock.length(for: .muscle) == 6)
        #expect(TrainingBlock.length(for: .endurance) == 4)
    }

    @Test func strengthRampsThenDeloads() {
        let weeks = TrainingBlock.schedule(style: .strength)
        #expect(weeks.map(\.setMultiplier) == [1.0, 1.1, 1.2, 1.25, 0.6])
        #expect(weeks.map(\.targetRIR) == [3, 2, 1, 1, 3])
        #expect(weeks.map(\.isDeload) == [false, false, false, false, true])
        #expect(weeks[2].targetRPE == 9)
        #expect(weeks[2].label == "Block week 3 of 5 · 1 in reserve")
        #expect(weeks[4].label == "Deload week (5 of 5) · 3 in reserve")
        // The note says when today's plan backs off from the block target.
        #expect(weeks[2].note(plannedRPE: 9) == weeks[2].note)
        #expect(weeks[2].note(plannedRPE: 6.5).hasSuffix("Today eased to 3-4 in reserve."))
    }

    @Test func muscleRampsHigherAndLonger() {
        let weeks = TrainingBlock.schedule(style: .muscle)
        #expect(weeks.map(\.setMultiplier) == [1.0, 1.1, 1.2, 1.3, 1.4, 0.6])
        #expect(weeks.map(\.targetRIR) == [3, 2, 1, 1, 1, 3])
        #expect(weeks.last?.isDeload == true)
    }

    @Test func enduranceKeepsSteadyWeeks() {
        let weeks = TrainingBlock.schedule(style: .endurance)
        #expect(weeks.map(\.setMultiplier) == [1, 1, 1, 1])
        #expect(weeks.allSatisfy { $0.targetRIR == 3 && !$0.isDeload })
    }

    @Test func scaledSetsStayBetweenTwoAndFive() {
        #expect(TrainingBlock.scaledSets(4, multiplier: 1.25) == 5)
        #expect(TrainingBlock.scaledSets(3, multiplier: 1.1) == 3)
        #expect(TrainingBlock.scaledSets(3, multiplier: 1.2) == 4)
        #expect(TrainingBlock.scaledSets(4, multiplier: 1.4) == 5) // capped
        #expect(TrainingBlock.scaledSets(4, multiplier: 0.6) == 2) // deload: about half
        #expect(TrainingBlock.scaledSets(3, multiplier: 0.6) == 2)
        #expect(TrainingBlock.scaledSets(2, multiplier: 0.6) == 2) // never under two
    }

    @Test func nextWeekAdvancesHoldsOnLowHRVAndEnds() {
        let block = TrainingBlock(start: monday, style: .strength)
        let week1 = block.week
        #expect(week1.week == 1 && week1.length == 5)
        let week2 = block.nextWeek(after: week1)
        #expect(week2?.week == 2)
        #expect(week2?.setMultiplier == 1.1)
        // HRV below normal: the ramp holds and the week is marked.
        let held = block.nextWeek(after: week1, hrvBelowNormal: true)
        #expect(held?.week == 1)
        #expect(held?.isHeld == true)
        #expect(held?.note.contains("HRV") == true)
        // ... unless the next week is the deload, which low HRV suits.
        let week4 = TrainingBlock.weekState(4, style: .strength, length: 5)
        let deload = block.nextWeek(after: week4, hrvBelowNormal: true)
        #expect(deload?.isDeload == true)
        #expect(deload?.isHeld == false)
        #expect(block.nextWeek(after: deload!) == nil)
    }

    @Test func advancesOnceACalendarWeek() {
        let block = TrainingBlock(start: monday, style: .strength)
        // Same week: nothing changes.
        #expect(block.advanced(to: days(3), calendar: utc) == block)
        // Next Monday: week 2.
        let second = block.advanced(to: days(7), calendar: utc)
        #expect(second.week.week == 2)
        #expect(second.weekStart == days(7))
        #expect(second.start == monday)
        // Next Monday with HRV below normal: still week 1, one held week.
        let held = block.advanced(to: days(8), hrvBelowNormal: true, calendar: utc)
        #expect(held.week.week == 1)
        #expect(held.week.isHeld)
        #expect(held.heldWeeks == 1)
        #expect(held.weekStart == days(7))
        // Called again in that same week: unchanged.
        #expect(held.advanced(to: days(10), hrvBelowNormal: false, calendar: utc) == held)
    }

    @Test func restartsAfterAGapOrWhenFinished() {
        let block = TrainingBlock(start: monday, style: .strength)
        let afterGap = block.advanced(to: days(14), calendar: utc)
        #expect(afterGap.week.week == 1)
        #expect(afterGap.start == days(14))
        #expect(afterGap.heldWeeks == 0)
        var last = block
        last.week = TrainingBlock.weekState(5, style: .strength, length: 5)
        last.weekStart = days(28)
        let fresh = last.advanced(to: days(35), style: .muscle, calendar: utc)
        #expect(fresh.week.week == 1)
        #expect(fresh.style == .muscle)
        #expect(fresh.length == 6)
        #expect(fresh.start == days(35))
    }

    @Test func coachLineIsOneSentence() {
        var block = TrainingBlock(start: monday, style: .balanced)
        #expect(block.coachLine == "Training block: week 1 of 5, RIR 3.")
        block.week = TrainingBlock.weekState(5, style: .balanced, length: 5)
        #expect(block.coachLine.contains("planned easier week"))
    }
}

struct BlockPlannerTests {
    let planner = WorkoutPlanner(gym: .commercialPounds)

    @Test func blockSetsTheEffortAndRecoveryStillBacksOff() {
        let week3 = TrainingBlock.weekState(3, style: .balanced, length: 5) // RIR 1
        #expect(WorkoutPlanner.targetRPE(recovery: 90, block: week3) == 9)
        #expect(WorkoutPlanner.targetRPE(recovery: 50, block: week3) == 8.5)
        #expect(WorkoutPlanner.targetRPE(recovery: 20, block: week3) == 7.5)
        let deload = TrainingBlock.weekState(5, style: .balanced, length: 5) // RIR 3
        #expect(WorkoutPlanner.targetRPE(recovery: 90, block: deload) == 7)
        #expect(WorkoutPlanner.targetRPE(recovery: 20, block: deload) == 6) // floor
        // No block: the old rule, unchanged.
        #expect(WorkoutPlanner.targetRPE(recovery: 90, block: nil) == 8)
    }

    @Test func blockScalesSetsAndTheDeloadHalvesThem() {
        // 120 minutes is a long session: seven exercises, four sets each (`WorkoutPlanner.baseSets`);
        // `fill` then adds a fifth set to the first two compound lifts and an eighth exercise
        // (a second horizontal press, 2 sets) to reach 85% of the time.
        let base = planner.plan(focus: .push, minutes: 120, recovery: 90, history: [:])
        #expect(base.exercises.map(\.sets) == [5, 5, 4, 4, 4, 4, 4, 2])
        #expect(base.exercises.last?.exerciseID == "Leverage_Chest_Press")
        #expect(base.blockWeek == nil)
        let week4 = TrainingBlock.weekState(4, style: .balanced, length: 5) // ×1.25, RIR 1
        let ramped = planner.plan(focus: .push, minutes: 120, recovery: 90, history: [:], block: week4)
        #expect(ramped.exercises.map(\.sets) == [5, 5, 5, 5, 5, 5, 5])
        #expect(ramped.targetRPE == 9)
        #expect(ramped.blockWeek == week4)
        let deload = TrainingBlock.weekState(5, style: .balanced, length: 5)
        let easy = planner.plan(focus: .push, minutes: 120, recovery: 90, history: [:], block: deload)
        #expect(easy.exercises.map(\.sets) == [2, 2, 2, 2, 2, 2, 2])
        #expect(easy.targetRPE == 7)
    }
}

struct SupersetTests {
    func exercise(_ id: String, sets: Int = 2, group: Int? = nil) -> PlannedExercise {
        var planned = PlannedExercise(exerciseID: id, name: id, sets: sets, reps: 6...8, rpe: 8, load: nil, loadKind: nil, note: nil)
        planned.supersetGroup = group
        return planned
    }

    @Test func pairsOnlyMovementsThatShareNoMuscle() {
        #expect(Supersets.canPair(.horizontalPress, .lateralRaise))
        #expect(Supersets.canPair(.horizontalPress, .horizontalRow)) // push with pull
        #expect(Supersets.canPair(.squat, .legCurl))                 // compound with a distant isolation
        #expect(Supersets.canPair(.squat, .horizontalPress))         // lower with upper
        #expect(!Supersets.canPair(.horizontalPress, .triceps))      // pressing uses the triceps
        #expect(!Supersets.canPair(.horizontalRow, .rearDelt))       // both load the upper back
        #expect(!Supersets.canPair(.squat, .hinge))
        #expect(!Supersets.canPair(.biceps, .biceps))
        // Strength style keeps big lifts as straight sets.
        #expect(!Supersets.canPair(.horizontalPress, .horizontalRow, style: .strength))
        #expect(Supersets.canPair(.lateralRaise, .triceps, style: .strength))
    }

    @Test func pairingMovesThePartnerNextToItsLift() {
        let paired = Supersets.pair(exercises: [
            exercise("Barbell_Squat"), exercise("Romanian_Deadlift"),
            exercise("Split_Squat_with_Dumbbells"), exercise("Seated_Leg_Curl"),
        ])
        #expect(paired.map(\.exerciseID) == ["Barbell_Squat", "Seated_Leg_Curl", "Romanian_Deadlift", "Split_Squat_with_Dumbbells"])
        #expect(paired.map(\.supersetGroup) == [1, 1, nil, nil])
        #expect(Supersets.label(for: 0, in: paired) == "A1")
        #expect(Supersets.label(for: 1, in: paired) == "A2")
        #expect(Supersets.label(for: 2, in: paired) == nil)
        #expect(Supersets.label(group: 2, position: 1) == "B1")
    }

    @Test func pairedSetsCountAtSixtyPercent() {
        let straight = [exercise("Barbell_Squat"), exercise("Seated_Leg_Curl")]
        let paired = [exercise("Barbell_Squat", group: 1), exercise("Seated_Leg_Curl", group: 1)]
        // One 2 min transition between the two exercises, then the sets.
        #expect(WorkoutPlanner.estimatedMinutes(straight) == 13) // 2 + 2×3.25 + 2×2.25
        #expect(WorkoutPlanner.estimatedMinutes(paired) == 9)    // 2 + 0.6 × 11 = 8.6
    }

    @Test func orphansLoseTheirGroup() {
        var exercises = [exercise("Barbell_Squat", group: 1), exercise("Romanian_Deadlift"), exercise("Seated_Leg_Curl", group: 2), exercise("Side_Lateral_Raise", group: 2)]
        Supersets.dropOrphans(&exercises)
        #expect(exercises.map(\.supersetGroup) == [nil, nil, 2, 2])
    }

    @Test func shortSessionsPairBeforeDroppingExercises() {
        let planner = WorkoutPlanner(gym: .commercialPounds)
        // 20 minutes: sets go to two each, then squat pairs with the leg curl, then one exercise goes.
        let short = planner.plan(focus: .legs, minutes: 20, recovery: 70, history: [:])
        #expect(short.hasSupersets)
        #expect(short.exercises.count == 3)
        #expect(short.exercises.map(\.supersetGroup) == [1, 1, nil])
        #expect(short.exercises.map(\.exerciseID) == ["Barbell_Squat", "Seated_Leg_Curl", "Romanian_Deadlift"])
        #expect(WorkoutPlanner.estimatedMinutes(short.exercises) <= 20)
        #expect(short.estimatedMinutes == 17) // 2 transitions + 0.6 × 11 + 2 × 3.25
        // 45 minutes: trimming sets is enough, so no supersets.
        let usual = planner.plan(focus: .legs, minutes: 45, recovery: 70, history: [:])
        #expect(!usual.hasSupersets)
        #expect(usual.exercises.count == 5)
    }
}

struct WarmUpTests {
    let gym = GymProfile.commercialPounds

    @Test func rampRoundsToThePlates() {
        let sets = WarmUp.sets(workingLoad: 185, kind: .barbell, gym: gym)
        #expect(sets == [.init(load: 90, reps: 8), .init(load: 125, reps: 5), .init(load: 155, reps: 2)])
        #expect(WarmUp.summary(sets) == "90 × 8, 125 × 5, 155 × 2")
        #expect(WarmUp.sets(workingLoad: 185, kind: .barbell, gym: gym, role: .laterCompound) == [.init(load: 125, reps: 3)])
        #expect(WarmUp.sets(workingLoad: 185, kind: .barbell, gym: gym, role: .isolation).isEmpty)
    }

    @Test func lightLiftsSkipTheEmptyBarAndDuplicates() {
        // 50% of 95 lb rounds to the 45 lb bar, so the ramp starts at 70%.
        #expect(WarmUp.sets(workingLoad: 95, kind: .barbell, gym: gym) == [.init(load: 65, reps: 5), .init(load: 80, reps: 2)])
        // 30 lb dumbbells: 15, 20, 25.
        #expect(WarmUp.sets(workingLoad: 30, kind: .dumbbell, gym: gym).map(\.load) == [15, 20, 25])
        // 10 lb dumbbells: 5 × 8 only (70% and 85% both round to 5, then equal the working weight).
        #expect(WarmUp.sets(workingLoad: 10, kind: .dumbbell, gym: gym) == [.init(load: 5, reps: 8)])
        #expect(WarmUp.sets(workingLoad: 100, kind: nil, gym: gym).isEmpty)
    }

    @Test func plannerWarmsUpTheFirstCompoundFullyAndLaterOnesBriefly() {
        let planner = WorkoutPlanner(gym: gym)
        let bench = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)
        let press = ExerciseHistory(bestEstimatedOneRepMax: 70, lastWeight: 50, lastReps: 8, lastRPE: 8, lastDate: .now)
        let plan = planner.plan(focus: .push, minutes: 90, recovery: 80,
                                history: ["Barbell_Bench_Press_-_Medium_Grip": bench, "Dumbbell_Shoulder_Press": press])
        #expect(plan.exercises[0].load == 190)
        #expect(plan.exercises[0].warmUpSets == [.init(load: 95, reps: 8), .init(load: 130, reps: 5), .init(load: 160, reps: 2)])
        #expect(plan.exercises[1].exerciseID == "Dumbbell_Shoulder_Press")
        #expect(plan.exercises[1].load == 55)
        #expect(plan.exercises[1].warmUpSets == [.init(load: 35, reps: 3)])
        // Isolation work and lifts without a weight get none.
        #expect(plan.exercises[3].warmUpSets == nil)
        // Your own workouts get the same ramp.
        let items = [TemplateItem(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench Press", sets: 4, reps: 6...8, rpe: 8)]
        let planned = planner.prescribe(template: items, history: ["Barbell_Bench_Press_-_Medium_Grip": bench])
        #expect(planned.first?.warmUpSets?.map(\.load) == [95, 130, 160])
    }
}
