import Foundation
import Testing
@testable import AppCore

struct PersonalBaselineTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    var today: Date { calendar.date(from: DateComponents(year: 2027, month: 3, day: 1))! }

    /// One value per day, `daysAgo` days before today.
    func day(_ daysAgo: Int, _ value: Double) -> DayValue {
        DayValue(date: calendar.date(byAdding: .day, value: -daysAgo, to: today)!, value: value)
    }

    @Test func bandLeavesOutTheLastWeek() throws {
        // 30 older days alternating 58/62, then a recent week at 80.
        let older = (7..<37).map { day($0, $0.isMultiple(of: 2) ? 58 : 62) }
        let recent = (0..<7).map { day($0, 80) }
        let band = try #require(PersonalBaseline.band(older + recent, asOf: today, calendar: calendar))
        #expect(abs(band.mean - 60) < 0.001)
        #expect(band.count == 30)
        #expect(band.sd > 1.9 && band.sd < 2.1)
        #expect(PersonalBaseline.position(80, in: band) == .above)
        #expect(PersonalBaseline.position(60, in: band) == .within)
        #expect(abs((PersonalBaseline.percentFromNormal(66, band: band) ?? 0) - 10) < 0.001)
    }

    @Test func needsFourteenDays() {
        let points = (7..<20).map { day($0, 60) }
        #expect(PersonalBaseline.band(points, asOf: today, calendar: calendar) == nil)
        // 13 in the window: one more reading, which joins after a week.
        #expect(PersonalBaseline.daysUntilReady(points, asOf: today, calendar: calendar) == 8)
    }

    @Test func recentReadingsCountOnceTheyAge() {
        // 10 old readings plus a full recent week: the 4th oldest recent one
        // (6, 5, 4, 3 days ago) completes the baseline in 4 days.
        let points = (7..<17).map { day($0, 60) } + (0..<7).map { day($0, 60) }
        #expect(PersonalBaseline.daysUntilReady(points, asOf: today, calendar: calendar) == 4)
        #expect(PersonalBaseline.daysUntilReady([], asOf: today, calendar: calendar) == 21)
    }

    @Test func rollingAverageUsesTheLastSevenDays() {
        let points = (0..<10).reversed().map { day($0, Double(10 - $0)) } // 1...10
        let rolling = PersonalBaseline.rollingAverage(points, calendar: calendar)
        #expect(rolling.first?.value == 1)
        // Last point averages days 4...10.
        #expect(abs((rolling.last?.value ?? 0) - 7) < 0.001)
    }

    @Test func recentAverageCanLeaveOutToday() {
        let points = (0..<7).map { day($0, $0 == 0 ? 100 : 10) }
        #expect(PersonalBaseline.recentAverage(points, excludingToday: true, asOf: today, calendar: calendar) == 10)
        let withToday = PersonalBaseline.recentAverage(points, asOf: today, calendar: calendar) ?? 0
        #expect(abs(withToday - 160.0 / 7) < 0.001)
    }
}
