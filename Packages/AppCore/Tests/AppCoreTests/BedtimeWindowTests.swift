import Foundation
import Testing
@testable import AppCore

struct BedtimeWindowTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2027-01-10 (a Sunday) at `hour`:`minute` UTC.
    func date(day: Int = 10, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    func makeDebt(_ nightlyHours: [Double]) -> SleepDebt.Result? {
        SleepDebt.compute(nightlyHours: nightlyHours, needHours: 8)
    }

    @Test func worksBackFromWakeNeedAndRepayment() throws {
        // Need 8 h, 40 min to repay, up at 6:30 → 21:50–22:20 (the roadmap's example).
        var debt = try #require(makeDebt([6, 6, 6, 6, 6]))
        debt.extraMinutesPerNight = 40
        let window = try #require(BedtimeWindow.compute(
            sleepNeedHours: 8, sleepDebt: debt, usualWakeMinutes: 6 * 60 + 30, regularity: 85,
            now: date(hour: 20), calendar: calendar))
        #expect(window.wake == date(day: 11, hour: 6, minute: 30))
        #expect(window.start == date(hour: 21, minute: 50))
        #expect(window.end == date(hour: 22, minute: 20))
        #expect(window.repaymentMinutes == 40)
        #expect(window.regularityNote == nil)
        #expect(window.reason.contains("8 h need"))
        #expect(window.reason.contains("40 min of debt"))
        #expect(window.line.contains("in bed by"))
    }

    @Test func repaymentIsCappedAtAnHour() throws {
        // Two weeks of 6 h nights: the debt plan asks for 60 min, never more (Kitamura 2016).
        let window = try #require(BedtimeWindow.compute(
            sleepNeedHours: 8, sleepDebt: makeDebt(Array(repeating: 6, count: 14)), usualWakeMinutes: 7 * 60, regularity: nil,
            now: date(hour: 20), calendar: calendar))
        #expect(window.repaymentMinutes == 60)
        #expect(window.start == date(hour: 22))
    }

    @Test func noDebtMeansNoRepayment() throws {
        let window = try #require(BedtimeWindow.compute(
            sleepNeedHours: 7.5, sleepDebt: makeDebt([8, 8, 8, 8, 8]), usualWakeMinutes: 7 * 60, regularity: 80,
            now: date(hour: 20), calendar: calendar))
        #expect(window.repaymentMinutes == 0)
        #expect(window.start == date(hour: 23, minute: 30))
        #expect(!window.reason.contains("debt"))
    }

    @Test func earlySessionBringsWakeForward() throws {
        // Usual wake 7:30, session at 6:30 → up at 5:30, in bed by 21:30.
        let window = try #require(BedtimeWindow.compute(
            sleepNeedHours: 8, sleepDebt: nil, usualWakeMinutes: 7 * 60 + 30, regularity: nil,
            plannedSessionStart: date(day: 11, hour: 6, minute: 30), now: date(hour: 20), calendar: calendar))
        #expect(window.wake == date(day: 11, hour: 5, minute: 30))
        #expect(window.wakeForSession)
        #expect(window.start == date(hour: 21, minute: 30))
    }

    @Test func lateSessionLeavesWakeAlone() throws {
        let window = try #require(BedtimeWindow.compute(
            sleepNeedHours: 8, sleepDebt: nil, usualWakeMinutes: 7 * 60, regularity: nil,
            plannedSessionStart: date(day: 11, hour: 18), now: date(hour: 20), calendar: calendar))
        #expect(window.wake == date(day: 11, hour: 7))
        #expect(!window.wakeForSession)
    }

    @Test func afterMidnightStillTargetsThisMorning() throws {
        // At 1 am the next 7:00 is 6 h away, so the window is for tonight, already passed.
        let window = try #require(BedtimeWindow.compute(
            sleepNeedHours: 8, sleepDebt: nil, usualWakeMinutes: 7 * 60, regularity: nil,
            now: date(day: 11, hour: 1), calendar: calendar))
        #expect(window.wake == date(day: 11, hour: 7))
        #expect(window.start == date(hour: 23))
    }

    @Test func lowRegularityAddsTheNote() throws {
        let window = try #require(BedtimeWindow.compute(
            sleepNeedHours: 8, sleepDebt: nil, usualWakeMinutes: 7 * 60, regularity: 65,
            now: date(hour: 20), calendar: calendar))
        #expect(window.regularityNote != nil)
    }

    @Test func needsAWakeTime() {
        #expect(BedtimeWindow.compute(sleepNeedHours: 8, sleepDebt: nil, usualWakeMinutes: nil, regularity: nil,
                                      now: date(hour: 20), calendar: calendar) == nil)
    }

    @Test func usualWakeIsTheMedian() {
        let wakes = [date(day: 8, hour: 6, minute: 50), date(day: 9, hour: 7, minute: 10), date(day: 10, hour: 9, minute: 30)]
        #expect(BedtimeWindow.usualWakeMinutes(wakes, calendar: calendar) == 7 * 60 + 10)
        #expect(BedtimeWindow.usualWakeMinutes([], calendar: calendar) == nil)
    }
}
