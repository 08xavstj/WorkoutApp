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
