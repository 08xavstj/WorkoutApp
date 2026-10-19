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

    @Test func oneDayIsKeptButNotReliable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let check = HomeBloodPressure.weekCheck([.init(date: now, systolic: 132, diastolic: 84)], asOf: now)
        #expect(check.readingsUsed == 1)
        #expect(!check.isReliable)
        #expect(check.category == .stage1)
    }
}
