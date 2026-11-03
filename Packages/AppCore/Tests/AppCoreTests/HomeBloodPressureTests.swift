import Foundation
import Testing
@testable import AppCore

struct HomeBloodPressureTests {
    @Test(arguments: [
        (118.0, 76.0, HomeBloodPressure.Category.normal),
        (124, 78, .elevated),
        (128, 82, .stage1),
        (134, 70, .stage1),
        (142, 85, .stage2),
        (120, 92, .stage2),
        (185, 100, .severe),
    ])
    func categories(systolic: Double, diastolic: Double, expected: HomeBloodPressure.Category) {
        #expect(HomeBloodPressure.category(systolic: systolic, diastolic: diastolic) == expected)
    }

    @Test func weekCheckLeavesOutDayOne() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2027, month: 3, day: 7, hour: 20))!
        var readings: [HomeBloodPressure.Reading] = []
        for daysAgo in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            // Day 1 (6 days ago) reads high; the rest are 122/78.
            let systolic = daysAgo == 6 ? 150.0 : 122
            // Two morning readings (8:00, 8:06) and two evening ones (20:00, 20:06).
            for hours in [-12.0, -11.9, 0, 0.1] {
                readings.append(.init(date: day.addingTimeInterval(hours * 3600), systolic: systolic, diastolic: 78))
            }
        }
        let check = HomeBloodPressure.weekCheck(readings, asOf: today, calendar: calendar)
        #expect(check.days == 7)
        #expect(check.readingsUsed == 24)
        #expect(check.isReliable)
        #expect(abs((check.systolic ?? 0) - 122) < 0.001)
        #expect(check.category == .elevated)
    }

    @Test func repeatEveryThreeOrSixMonths() {
        // 3-6-monthly repeat of the home protocol (ESH 2021; ACC/AHA): 3 months when elevated or high, 6 when normal.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let ended = calendar.date(from: DateComponents(year: 2027, month: 3, day: 7, hour: 20))!
        #expect(HomeBloodPressure.repeatMonths(after: .normal) == 6)
        #expect(HomeBloodPressure.repeatMonths(after: nil) == 6)
        #expect(HomeBloodPressure.repeatMonths(after: .elevated) == 3)
        #expect(HomeBloodPressure.repeatMonths(after: .stage1) == 3)
        #expect(HomeBloodPressure.repeatMonths(after: .stage2) == 3)
        #expect(HomeBloodPressure.nextCheckDue(lastCheck: ended, category: .normal, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2027, month: 9, day: 7))!)
        #expect(HomeBloodPressure.nextCheckDue(lastCheck: ended, category: .elevated, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2027, month: 6, day: 7))!)
        #expect(!HomeBloodPressure.isCheckDue(lastCheck: ended, category: .normal, now: ended.addingTimeInterval(100 * 86_400), calendar: calendar))
        #expect(HomeBloodPressure.isCheckDue(lastCheck: ended, category: .elevated, now: ended.addingTimeInterval(100 * 86_400), calendar: calendar))
    }

    @Test func lastCompletedCheckNeedsAFullWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let end = calendar.date(from: DateComponents(year: 2027, month: 3, day: 7, hour: 20))!
        var readings: [HomeBloodPressure.Reading] = []
        for daysAgo in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: end)!
            for hours in [-12.0, 0] {
                readings.append(.init(date: day.addingTimeInterval(hours * 3600), systolic: 124, diastolic: 78))
            }
        }
        // 14 readings, 12 used after day 1 is dropped: a completed check ending on 7 March.
        let completed = try #require(HomeBloodPressure.lastCompletedCheck(readings, calendar: calendar))
        #expect(completed.ended == calendar.startOfDay(for: end))
        #expect(completed.check.category == .elevated)
        // Two readings alone aren't a check.
        #expect(HomeBloodPressure.lastCompletedCheck(Array(readings.prefix(2)), calendar: calendar) == nil)
    }

    @Test func oneDayIsKeptButNotReliable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let check = HomeBloodPressure.weekCheck([.init(date: now, systolic: 132, diastolic: 84)], asOf: now)
        #expect(check.readingsUsed == 1)
        #expect(!check.isReliable)
        #expect(check.category == .stage1)
    }
}
