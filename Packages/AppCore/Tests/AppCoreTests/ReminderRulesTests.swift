import Foundation
import Testing
@testable import AppCore

struct ReminderRulesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// November 2026: the 16th is a Monday.
    private func time(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: Weigh-in line

    @Test func theWeighInLineIsNotAddedEveryDay() {
        let morning = 8 * 60
        // Never carried: due.
        #expect(ReminderRules.weighInLineDue(lastCarried: nil, morningMinutes: morning, now: time(day: 16, 7), calendar: calendar))
        // On today's reminder, which hasn't fired: it stays there.
        #expect(ReminderRules.weighInLineDue(lastCarried: time(day: 16, 0), morningMinutes: morning, now: time(day: 16, 7), calendar: calendar))
        // Today's reminder has fired: not on tomorrow's too.
        #expect(!ReminderRules.weighInLineDue(lastCarried: time(day: 16, 0), morningMinutes: morning, now: time(day: 16, 9), calendar: calendar))
        #expect(!ReminderRules.weighInLineDue(lastCarried: time(day: 16, 0), morningMinutes: morning, now: time(day: 17, 7), calendar: calendar))
        #expect(!ReminderRules.weighInLineDue(lastCarried: time(day: 16, 0), morningMinutes: morning, now: time(day: 22, 23), calendar: calendar))
        // A week later: again.
        #expect(ReminderRules.weighInLineDue(lastCarried: time(day: 16, 0), morningMinutes: morning, now: time(day: 23, 7), calendar: calendar))
        // Set on tomorrow's reminder (today's was done): still pending, so it stays.
        #expect(ReminderRules.weighInLineDue(lastCarried: time(day: 17, 0), morningMinutes: morning, now: time(day: 16, 20), calendar: calendar))
    }

    // MARK: Weekly review

    @Test func theReviewReminderIsTheNextMondays() {
        // Wednesday: the next two Mondays at 08:00.
        #expect(ReminderRules.weeklyReviewFireDates(now: time(day: 18, 12), minutes: 8 * 60, lastOpened: nil, calendar: calendar)
                == [time(day: 23, 8), time(day: 30, 8)])
        // Monday before 08:00: today's first.
        #expect(ReminderRules.weeklyReviewFireDates(now: time(day: 16, 7), minutes: 8 * 60, lastOpened: nil, calendar: calendar)
                == [time(day: 16, 8), time(day: 23, 8)])
        // Monday after 08:00: next week's.
        #expect(ReminderRules.weeklyReviewFireDates(now: time(day: 16, 9), minutes: 8 * 60, lastOpened: nil, calendar: calendar).first
                == time(day: 23, 8))
    }

    @Test func aReviewAlreadyOpenedThatMondayIsNotRemindedAbout() {
        // Opened at 07:10 on Monday: no 08:00 reminder that day, next Monday's stands.
        let dates = ReminderRules.weeklyReviewFireDates(now: time(day: 16, 7, 15), minutes: 8 * 60, lastOpened: time(day: 16, 7, 10),
                                                        calendar: calendar)
        #expect(dates == [time(day: 23, 8), time(day: 30, 8)])
        // Opened last week: this Monday's reminder still comes.
        #expect(ReminderRules.weeklyReviewFireDates(now: time(day: 16, 7), minutes: 8 * 60, lastOpened: time(day: 10, 9), calendar: calendar).first
                == time(day: 16, 8))
        // An evening review time, opened at lunch: skipped.
        #expect(ReminderRules.weeklyReviewFireDates(now: time(day: 16, 13), minutes: 18 * 60, lastOpened: time(day: 16, 12, 30), calendar: calendar).first
                == time(day: 23, 18))
    }

    // MARK: Workout reminders

    @Test func remindersThatNeverFiredLeaveTheLog() {
        let now = time(day: 18, 12)
        let log = ["2026-11-16": time(day: 16, 17, 30), "2026-11-18": time(day: 18, 17, 30), "2026-11-20": time(day: 20, 17, 30)]
        // Reminders turned off (nothing rescheduled): Wednesday's and Friday's never go out, so they aren't kept.
        #expect(WorkoutReminderRules.logAfterReschedule(log, scheduled: [:], now: now) == ["2026-11-16": time(day: 16, 17, 30)])
        // Rescheduled as they were: all three stay.
        let pending = ["2026-11-18": time(day: 18, 17, 30), "2026-11-20": time(day: 20, 17, 30)]
        #expect(WorkoutReminderRules.logAfterReschedule(log, scheduled: pending, now: now) == log)
    }

    @Test func todaysFiredReminderStaysInTheLog() {
        // Opened at 18:00, after today's 17:30 reminder: nothing left to schedule today, but it did go out.
        let now = time(day: 18, 18)
        let log = ["2026-11-18": time(day: 18, 17, 30)]
        let after = WorkoutReminderRules.logAfterReschedule(log, scheduled: ["2026-11-20": time(day: 20, 17, 30)], now: now)
        #expect(after["2026-11-18"] == time(day: 18, 17, 30))
        #expect(after.count == 2)
    }

    @Test func twoIgnoredInARowAreCounted() {
        let log = ["2026-11-16": time(day: 16, 17, 30), "2026-11-18": time(day: 18, 17, 30), "2026-11-20": time(day: 20, 17, 30)]
        let now = time(day: 21, 9)
        #expect(WorkoutReminderRules.ignoredInARow(log: log, answered: [], todayKey: "2026-11-21", now: now) == 3)
        // Trained (or tapped) on Wednesday: only Friday's is ignored.
        #expect(WorkoutReminderRules.ignoredInARow(log: log, answered: ["2026-11-18"], todayKey: "2026-11-21", now: now) == 1)
        #expect(WorkoutReminderRules.ignoredInARow(log: log, answered: ["2026-11-20"], todayKey: "2026-11-21", now: now) == 0)
        // Today's own reminder isn't judged yet.
        #expect(WorkoutReminderRules.ignoredInARow(log: log, answered: ["2026-11-18"], todayKey: "2026-11-20", now: time(day: 20, 18)) == 0)
        #expect(WorkoutReminderRules.ignoredInARow(log: [:], answered: [], todayKey: "2026-11-21", now: now) == 0)
    }

    @Test func theLogKeepsOnlyTheNewestEntries() {
        var log: [String: Date] = [:]
        for day in 1...28 { log[String(format: "2026-10-%02d", day)] = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 17))! }
        var scheduled: [String: Date] = [:]
        for day in 16...22 { scheduled[String(format: "2026-11-%02d", day)] = time(day: day, 17) }
        let after = WorkoutReminderRules.logAfterReschedule(log, scheduled: scheduled, now: time(day: 15, 12))
        #expect(after.count == WorkoutReminderRules.keptEntries)
        #expect(after["2026-11-22"] != nil)
        #expect(after["2026-10-01"] == nil)
    }
}
