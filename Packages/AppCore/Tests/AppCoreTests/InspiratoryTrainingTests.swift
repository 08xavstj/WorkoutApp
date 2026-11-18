import Foundation
import Testing
@testable import AppCore

struct InspiratoryTrainingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Two readings morning and evening for `days` days ending `endDaysAgo` before `now`.
    func week(systolic: Double, days: Int = 7, endDaysAgo: Int = 0, now: Date) -> [HomeBloodPressure.Reading] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).flatMap { offset -> [HomeBloodPressure.Reading] in
            let day = calendar.date(byAdding: .day, value: -(offset + endDaysAgo), to: today)!
            return [7.5, 7.55, 20.0, 20.05].map { hours in
                .init(date: day.addingTimeInterval(hours * 3600), systolic: systolic, diastolic: 78)
            }
        }
    }

    var now: Date { calendar.date(from: DateComponents(year: 2027, month: 3, day: 7, hour: 21))! }

    @Test func offeredAtOrAboveTheThreshold() {
        #expect(InspiratoryTraining.eligibility(week(systolic: 120, now: now), now: now, calendar: calendar).isOffered)
        #expect(InspiratoryTraining.eligibility(week(systolic: 131, now: now), now: now, calendar: calendar).isOffered)
    }

    @Test func neverBelowTheThreshold() {
        let result = InspiratoryTraining.eligibility(week(systolic: 119, now: now), now: now, calendar: calendar)
        #expect(!result.isOffered)
        guard case .belowThreshold(let systolic, _) = result else {
            Issue.record("expected below threshold")
            return
        }
        #expect(systolic == 119)
    }

    @Test func neverWithoutAReliableAverage() {
        #expect(InspiratoryTraining.eligibility([], now: now, calendar: calendar) == .noAverage)
        // Two days of readings: under the 12 a home average needs.
        let short = week(systolic: 140, days: 2, now: now)
        #expect(InspiratoryTraining.eligibility(short, now: now, calendar: calendar) == .noAverage)
    }

    @Test func aWeekStillFillingDoesNotHideTheLastFullOne() {
        // A full week at 128 ending 20 days ago, then two new readings today.
        var readings = week(systolic: 128, endDaysAgo: 20, now: now)
        readings += week(systolic: 110, days: 1, now: now).prefix(2)
        let result = InspiratoryTraining.eligibility(readings, now: now, calendar: calendar)
        #expect(result.isOffered)
    }

    @Test func aNewerNormalWeekWins() {
        var readings = week(systolic: 128, endDaysAgo: 30, now: now)
        readings += week(systolic: 116, now: now)
        #expect(!InspiratoryTraining.eligibility(readings, now: now, calendar: calendar).isOffered)
    }

    @Test func averagesOverAYearOldDontCount() {
        let readings = week(systolic: 135, endDaysAgo: 400, now: now)
        #expect(InspiratoryTraining.eligibility(readings, now: now, calendar: calendar) == .noAverage)
    }

    @Test func log() {
        let today = calendar.startOfDay(for: now)
        let sessions = (0..<9).map { offset in
            InspiratoryTraining.Session(date: calendar.date(byAdding: .day, value: -offset, to: today)!.addingTimeInterval(8 * 3600),
                                        breaths: offset == 2 ? 18 : 30)
        }
        #expect(InspiratoryTraining.fullDaysThisWeek(sessions, now: now, calendar: calendar) == 6)
        #expect(InspiratoryTraining.doneToday(sessions, now: now, calendar: calendar))
        #expect(InspiratoryTraining.fullDays(sessions, calendar: calendar) == 8)
        #expect(!InspiratoryTraining.doneToday([], now: now, calendar: calendar))
    }
}
