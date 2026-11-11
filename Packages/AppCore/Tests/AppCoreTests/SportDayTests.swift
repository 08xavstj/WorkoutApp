import Foundation
import Testing
@testable import AppCore

/// Soccer, a run or a walk never take the place of a planned lift.
struct SportDayTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let today = Date(timeIntervalSince1970: 1_800_000_000)

    func yesterday(strain: Double, lifted: Bool?, planned: WorkoutFocus? = nil) -> TrainingDayPlanner.PastDay {
        TrainingDayPlanner.PastDay(date: today.addingTimeInterval(-86_400), plannedFocus: planned, strain: strain, trained: lifted)
    }

    func guidance(_ planned: WorkoutFocus?, _ past: [TrainingDayPlanner.PastDay], low: Bool = false) -> TrainingDayPlanner.Guidance {
        TrainingDayPlanner.guidance(plannedToday: planned, past: past, lowRecovery: low, usualTrainingStrain: 65, calendar: calendar)
    }

    @Test func hardSoccerOnARestDayKeepsTomorrowsLift() {
        let result = guidance(.upper, [yesterday(strain: 70, lifted: false)])
        #expect(result.kind == .training)
        #expect(result.focus == .upper)
        #expect(!result.reason.contains("legs"))
    }

    @Test func aLegSessionAfterSportGetsALegsNote() {
        let result = guidance(.lower, [yesterday(strain: 70, lifted: false)])
        #expect(result.kind == .training)
        #expect(result.reason.contains("legs are still heavy"))
    }

    @Test func aHardExtraLiftStillMakesTomorrowEasy() {
        #expect(guidance(.upper, [yesterday(strain: 70, lifted: true)]).kind == .easyTraining)
        // Unknown (older callers): as before.
        #expect(guidance(.upper, [yesterday(strain: 70, lifted: nil)]).kind == .easyTraining)
    }

    @Test func lowRecoveryAfterSportStillRests() {
        #expect(guidance(.upper, [yesterday(strain: 70, lifted: false)], low: true).kind == .recovery)
    }

    @Test func soccerOnALiftDayLeavesTheLiftToMakeUp() {
        // Upper was planned yesterday; soccer instead. Today (a rest day) offers it.
        let result = guidance(nil, [yesterday(strain: 70, lifted: false, planned: .upper)])
        #expect(result.kind == .makeUp)
        #expect(result.focus == .upper)
    }

    @Test func flexibleWeekTrainsAfterSport() {
        let progress = WeeklyPlan.Progress(target: 3, done: 1, daysLeft: 5, trainedToday: false)
        let afterSport = TrainingDayPlanner.flexibleGuidance(week: progress, nextFocus: .pull, past: [yesterday(strain: 70, lifted: false)],
                                                             lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(afterSport.kind == .training)
        #expect(afterSport.focus == .pull)
        let afterLift = TrainingDayPlanner.flexibleGuidance(week: progress, nextFocus: .pull, past: [yesterday(strain: 70, lifted: true)],
                                                            lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(afterLift.kind == .rest)
    }

    @Test func fixedWeekQueueKeepsTheLiftAfterSport() throws {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let plan = WeeklyPlan(weekStart: monday, plannedDays: [
            PlannedDay(weekday: 3, time: 18 * 60, focus: .upper, minutes: 60),
            PlannedDay(weekday: 5, time: 18 * 60, focus: .lower, minutes: 60),
        ])
        // Monday (a rest day) had soccer; Tuesday's Upper is still on.
        let tuesday = calendar.date(byAdding: .hour, value: 24 + 8, to: monday)!
        let week = try #require(AdaptiveWeek.make(plan: plan, done: [], now: tuesday, calendar: calendar))
        #expect(week.today?.focus == .upper)
        let past = [TrainingDayPlanner.PastDay(date: monday, plannedFocus: nil, strain: 70, trained: false)]
        let result = TrainingDayPlanner.adaptiveGuidance(week: week, past: past, lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(result.kind == .training)
        #expect(result.focus == .upper)
    }
}

struct RepGoalTests {
    let range = 6...10

    @Test func onPlanKeepsTheReps() {
        #expect(RepGoal.next(repsDone: 8, repsLeft: 2, targetRIR: 2, range: range) == 8)
    }

    @Test func moreLeftRaisesTheGoalAtMostTwo() {
        #expect(RepGoal.next(repsDone: 8, repsLeft: 3, targetRIR: 2, range: range) == 9)
        #expect(RepGoal.next(repsDone: 8, repsLeft: 4, targetRIR: 1, range: range) == 10)
        // "4+" from a 0-reserve plan would be +4: capped at +2.
        #expect(RepGoal.next(repsDone: 7, repsLeft: 4, targetRIR: 0, range: range) == 9)
    }

    @Test func lessLeftLowersTheGoal() {
        #expect(RepGoal.next(repsDone: 8, repsLeft: 0, targetRIR: 2, range: range) == 6)
        #expect(RepGoal.next(repsDone: 8, repsLeft: 1, targetRIR: 2, range: range) == 7)
    }

    @Test func halfARepIsNoChange() {
        #expect(RepGoal.next(repsDone: 8, repsLeft: 2, targetRIR: 2.5, range: range) == 8)
        #expect(RepGoal.next(repsDone: 8, repsLeft: 3, targetRIR: 2.5, range: range) == 8)
    }

    @Test func staysNearThePlannedRange() {
        #expect(RepGoal.next(repsDone: 12, repsLeft: 4, targetRIR: 1, range: range) == 12)
        #expect(RepGoal.next(repsDone: 4, repsLeft: 0, targetRIR: 3, range: range) == 4)
        #expect(RepGoal.next(repsDone: 3, repsLeft: 0, targetRIR: 3, range: 3...5) == 1)
    }

    @Test func notesSayWhy() {
        #expect(RepGoal.note(goal: 9, previous: 8, repsLeft: 4) == "Next set goal 9 reps: you had 4+ left")
        #expect(RepGoal.note(goal: 6, previous: 8, repsLeft: 0) == "Next set goal 6 reps: you hit your limit")
        #expect(RepGoal.note(goal: 7, previous: 8, repsLeft: 1) == "Next set goal 7 reps: that set was harder than planned")
        #expect(RepGoal.note(goal: 8, previous: 8, repsLeft: 2) == nil)
    }
}
