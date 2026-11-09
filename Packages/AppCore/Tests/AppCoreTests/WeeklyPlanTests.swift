import Foundation
import Testing
@testable import AppCore

struct WeeklyPlanTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1 // Sunday-first, to prove the Monday start doesn't depend on it.
        return calendar
    }

    /// Monday 2 November 2026, 00:00 UTC.
    var monday: Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 2))! }

    func day(_ offset: Int, hour: Int = 18) -> Date {
        utc.date(byAdding: .hour, value: hour, to: utc.date(byAdding: .day, value: offset, to: monday)!)!
    }

    @Test func weekStartsOnMondayWhateverTheCalendarSays() {
        #expect(WeeklyPlan.weekStart(containing: monday, calendar: utc) == monday)
        #expect(WeeklyPlan.weekStart(containing: day(3, hour: 9), calendar: utc) == monday)   // Thursday
        #expect(WeeklyPlan.weekStart(containing: day(6, hour: 23), calendar: utc) == monday)  // Sunday
        #expect(WeeklyPlan.weekStart(containing: day(7, hour: 1), calendar: utc) == utc.date(byAdding: .day, value: 7, to: monday))
        #expect(WeeklyPlan.weekdayOrder == [2, 3, 4, 5, 6, 7, 1])
        #expect(WeeklyPlan.order(1) == 6)
    }

    @Test func sortsDaysMondayFirstAndMatchesDoneDays() {
        let plan = WeeklyPlan(weekStart: monday, plannedDays: [
            PlannedDay(weekday: 1, time: 600, focus: .legs, minutes: 45),   // Sunday
            PlannedDay(weekday: 3, time: 1080, focus: .push, minutes: 45),  // Tuesday
            PlannedDay(weekday: 6, time: 1080, focus: .pull, minutes: 45),  // Friday
        ])
        #expect(plan.sortedDays.map(\.weekday) == [3, 6, 1])
        // Tuesday 18:00 and Sunday 10:00 of that week.
        #expect(plan.start(of: plan.sortedDays[0], calendar: utc) == day(1, hour: 18))
        #expect(plan.start(of: plan.sortedDays[2], calendar: utc) == day(6, hour: 10))
        // Trained Tuesday and Wednesday (unplanned), plus a session the week before that doesn't count.
        let trained = [day(1), day(2), day(-3)]
        #expect(plan.doneWeekdays(trainingDays: trained, calendar: utc) == [3, 4])
        let record = WeekRecord.make(plan: plan, trainingDays: trained + [day(1, hour: 20)], calendar: utc)
        #expect(record.planned == 3)
        #expect(record.done == 2) // two sessions on Tuesday are one training day
    }

    @Test func threeOfFourKeepsAWeekAndSmallPlansForgiveOne() {
        // 3/4 rounded up, but never more than planned − 1 for small plans.
        #expect(Consistency.sessionsNeeded(planned: 1) == 1)
        #expect(Consistency.sessionsNeeded(planned: 2) == 1)
        #expect(Consistency.sessionsNeeded(planned: 3) == 2)
        #expect(Consistency.sessionsNeeded(planned: 4) == 3)
        #expect(Consistency.sessionsNeeded(planned: 5) == 4)
        #expect(Consistency.sessionsNeeded(planned: 6) == 5)
        #expect(Consistency.weekKept(planned: 4, done: 3))
        #expect(!Consistency.weekKept(planned: 4, done: 2))
        #expect(!Consistency.weekKept(planned: 0, done: 3))
    }

    @Test func scoreIsKeptWeeksOverPlannedWeeksInTheLastFour() {
        func week(_ back: Int, planned: Int, done: Int) -> WeekRecord {
            WeekRecord(weekStart: utc.date(byAdding: .day, value: -7 * back, to: monday)!, planned: planned, done: done)
        }
        let now = day(2, hour: 12) // Wednesday of the current week
        let records = [
            week(5, planned: 3, done: 0), // outside the window
            week(3, planned: 3, done: 3),
            week(2, planned: 3, done: 2), // kept: 2 of 3
            week(1, planned: 4, done: 1), // not kept
            week(0, planned: 3, done: 1), // in progress and not yet kept: not counted
        ]
        let result = Consistency.score(records: records, now: now, calendar: utc)
        #expect(result.keptWeeks == 2)
        #expect(result.plannedWeeks == 3)
        #expect(abs(result.score - 2.0 / 3.0) < 1e-9)
        #expect(result.label == "2 of 3 weeks")
        // After a week that wasn't kept: what to do, with no "broken" or "lost".
        let note = result.note ?? ""
        #expect(note.contains("this week counts"))
        #expect(!note.lowercased().contains("broken"))
        #expect(!note.lowercased().contains("streak"))

        // The current week counts once it is already kept.
        let kept = Consistency.score(records: Array(records.dropLast()) + [week(0, planned: 3, done: 2)], now: now, calendar: utc)
        #expect(kept.keptWeeks == 3)
        #expect(kept.plannedWeeks == 4)
        #expect(kept.label == "3 of 4 weeks")
    }

    @Test func labelsAreGentleWhenThereIsLittleHistory() {
        let empty = Consistency.score(records: [], now: monday, calendar: utc)
        #expect(empty.plannedWeeks == 0)
        #expect(empty.score == 0)
        #expect(empty.label == "Getting going")
        let one = Consistency.score(records: [WeekRecord(weekStart: utc.date(byAdding: .day, value: -7, to: monday)!, planned: 3, done: 3)],
                                    now: monday, calendar: utc)
        #expect(one.keptWeeks == 1)
        #expect(one.label == "Getting going")
        #expect(one.note == nil)
    }

    @Test func identityWeeksCountBackFromLastWeekOnly() {
        func week(_ back: Int, done: Int) -> WeekRecord {
            WeekRecord(weekStart: utc.date(byAdding: .day, value: -7 * back, to: monday)!, planned: 3, done: done)
        }
        let records = [week(4, done: 1), week(3, done: 2), week(2, done: 3), week(1, done: 2), week(0, done: 0)]
        #expect(Consistency.weeksTrainingAtLeast(2, records: records, now: monday, calendar: utc) == 3)
        #expect(Consistency.weeksTrainingAtLeast(3, records: records, now: monday, calendar: utc) == 0)
        #expect(Consistency.weeksTrainingAtLeast(2, records: [], now: monday, calendar: utc) == 0)
    }

    @Test func restartHalvesThePlanAndKeepsTheWordingKind() {
        let last = WeeklyPlan(weekStart: monday, plannedDays: [
            PlannedDay(weekday: 2, time: 1080, focus: .push, minutes: 60, ifThen: "If late, 15 minutes"),
            PlannedDay(weekday: 3, time: 1080, focus: .pull, minutes: 60),
            PlannedDay(weekday: 5, time: 1080, focus: .legs, minutes: 60),
            PlannedDay(weekday: 6, time: 1080, focus: .upper, minutes: 60),
        ])
        #expect(RestartPlan.make(daysOff: 6, lastPlan: last) == nil)
        let restart = RestartPlan.make(daysOff: 7, lastPlan: last)!
        #expect(restart.plannedDays.map(\.weekday) == [2, 6]) // first and last, spread out
        #expect(restart.plannedDays.allSatisfy { $0.minutes == 15 }) // short version first week
        #expect(restart.plannedDays[0].ifThen == "If late, 15 minutes")
        #expect(restart.message.contains("Little fitness is lost in two weeks"))
        for word in ["missed", "behind", "lost your", "broken", "should"] {
            #expect(!restart.message.lowercased().contains(word))
        }
        // Never below two days; no earlier plan gives two short full-body sessions.
        let two = RestartPlan.make(daysOff: 10, lastPlan: WeeklyPlan(weekStart: monday, plannedDays: Array(last.plannedDays.prefix(2))))!
        #expect(two.plannedDays.count == 2)
        let fresh = RestartPlan.make(daysOff: 14, lastPlan: nil)!
        #expect(fresh.plannedDays.count == 2)
        #expect(fresh.plannedDays.allSatisfy { $0.focus == .fullBody && $0.minutes == 15 })
        // Strength goals get the 85-90% note.
        let strength = RestartPlan.make(daysOff: 8, lastPlan: last, goals: Goals(focuses: [.strength]))!
        #expect(strength.message.contains("85-90%"))
        #expect(!RestartPlan.make(daysOff: 8, lastPlan: last, goals: Goals(focuses: [.health]))!.message.contains("85-90%"))
    }

    @Test func daysOffCountsWholeDays() {
        #expect(RestartPlan.daysOff(lastTrained: nil, now: monday, calendar: utc) == nil)
        #expect(RestartPlan.daysOff(lastTrained: day(-7, hour: 23), now: day(0, hour: 6), calendar: utc) == 7)
        #expect(RestartPlan.daysOff(lastTrained: day(0, hour: 6), now: day(0, hour: 22), calendar: utc) == 0)
        #expect(RestartPlan.daysOffThreshold == 7)
    }

    @Test func defaultsFollowTheGoalAndRotateFromTheRestedFocus() {
        #expect(WeeklyPlan.suggestedDayCount(goals: nil) == 3)
        #expect(WeeklyPlan.suggestedDayCount(goals: Goals(focuses: [.health])) == 3)
        #expect(WeeklyPlan.suggestedDayCount(goals: Goals(focuses: [.muscle])) == 4)
        #expect(WeeklyPlan.suggestedDayCount(goals: Goals(focuses: [.strength, .endurance])) == 4)
        // New plans train every muscle at least twice a week (audit 2026-11 §6): full body for
        // 1-2 days, upper/lower/full for 3, upper/lower twice for 4, U/L + PPL for 5, PPL twice for 6.
        #expect(WeeklyPlan.focusRotation(start: .pull, count: 3) == [.upper, .lower, .fullBody])
        #expect(WeeklyPlan.focusRotation(start: .legs, count: 3) == [.lower, .upper, .fullBody])
        #expect(WeeklyPlan.focusRotation(start: .push, count: 5) == [.upper, .lower, .push, .pull, .legs])
        #expect(WeeklyPlan.focusRotation(start: .push, count: 2) == [.fullBody, .fullBody])
        #expect(WeeklyPlan.focusRotation(start: .pull, count: 6) == [.pull, .legs, .push, .pull, .legs, .push])
        #expect(WeeklyPlan.focusRotation(start: .legs, count: 4) == [.lower, .upper, .lower, .upper])
        #expect(WeeklyPlan.suggestedWeekdays(count: 3) == [2, 4, 6])
        #expect(WeeklyPlan.suggestedWeekdays(count: 6).count == 6)
        #expect(WeeklyPlan.dayRange == 2...6)
        #expect(WeeklyPlan.ifThenSuggestions.count == 3)
    }

    @Test func plansRoundTripThroughJSON() throws {
        let plan = WeeklyPlan(weekStart: monday, plannedDays: [
            PlannedDay(weekday: 3, time: 1080, focus: .push, minutes: 45, ifThen: "If I'm late, the 15-minute version"),
        ], changes: ["Bed by 11", "Protein at breakfast"])
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(WeeklyPlan.self, from: data)
        #expect(decoded == plan)
        #expect(decoded.plannedDays[0].shortVersionMinutes == 15)
        #expect(decoded.mode == .fixedDays)
        #expect(decoded.sessionsPerWeek == nil)
        // Flexible plans keep their mode and quota.
        let flexible = WeeklyPlan(weekStart: monday, plannedDays: plan.plannedDays, mode: .flexible, sessionsPerWeek: 4)
        let back = try JSONDecoder().decode(WeeklyPlan.self, from: try JSONEncoder().encode(flexible))
        #expect(back == flexible)
        #expect(back.isFlexible)
        #expect(back.sessionTarget == 4)
    }

    @Test func plansSavedBeforeModesDecodeAsFixedDays() throws {
        let json = """
        {"weekStart": 0, "plannedDays": [{"weekday": 3, "time": 1080, "focus": "push", "minutes": 45, "shortVersionMinutes": 15}], "changes": ["Bed by 11"]}
        """
        let plan = try JSONDecoder().decode(WeeklyPlan.self, from: Data(json.utf8))
        #expect(plan.mode == .fixedDays)
        #expect(!plan.isFlexible)
        #expect(plan.sessionsPerWeek == nil)
        #expect(plan.sessionTarget == 1)
        #expect(plan.plannedDays.count == 1)
        #expect(plan.changes == ["Bed by 11"])
        #expect(plan.nextFlexibleSession(done: 0) == nil)
    }

    @Test func flexibleWeekCountsSessionsAgainstTheQuotaNotWeekdays() {
        // Two session templates (Tue, Fri) but a quota of 4, trained Mon, Wed, Thu.
        let plan = WeeklyPlan(weekStart: monday, plannedDays: [
            PlannedDay(weekday: 3, time: 1080, focus: .push, minutes: 45),
            PlannedDay(weekday: 6, time: 1080, focus: .pull, minutes: 45),
        ], mode: .flexible, sessionsPerWeek: 4)
        let trained = [day(0), day(2), day(3), day(-2)]
        let record = WeekRecord.make(plan: plan, trainingDays: trained, calendar: utc)
        #expect(record.planned == 4)
        #expect(record.done == 3) // none on the template weekdays, all counted
        #expect(Consistency.weekKept(planned: record.planned, done: record.done))
        // Progress as of Thursday evening: 3 of 4 done, 4 days left (Thu-Sun), trained today.
        let progress = plan.progress(trainingDays: trained, now: day(3, hour: 20), calendar: utc)
        #expect(progress == WeeklyPlan.Progress(target: 4, done: 3, daysLeft: 4, trainedToday: true))
        #expect(progress.remaining == 1)
        #expect(progress.slack == 2)
        #expect(progress.label == "3 of 4 done · 4 days left")
        #expect(WeeklyPlan.daysLeft(now: monday, calendar: utc) == 7)
        #expect(WeeklyPlan.daysLeft(now: day(6), calendar: utc) == 1)
        // The next session is the first template not yet done, by count; the last one repeats past the templates.
        #expect(plan.nextFlexibleSession(done: 0)?.focus == .push)
        #expect(plan.nextFlexibleSession(done: 1)?.focus == .pull)
        #expect(plan.nextFlexibleSession(done: 3)?.focus == .pull)
        #expect(plan.nextFlexibleSession(done: 4) == nil)
        // Without a quota the templates set it.
        let counted = WeeklyPlan(weekStart: monday, plannedDays: plan.plannedDays, mode: .flexible)
        #expect(counted.sessionTarget == 2)
    }

    @Test func plannedDaysSavedBeforeTheShortVersionStillDecode() throws {
        let json = #"{"weekday":2,"time":1080,"focus":"push","minutes":45}"#
        let day = try JSONDecoder().decode(PlannedDay.self, from: Data(json.utf8))
        #expect(day.shortVersionMinutes == 15)
        #expect(day.focus == .push)
    }
}
