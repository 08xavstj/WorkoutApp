import Foundation
import Testing
@testable import AppCore

struct ActivityCalendarTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func activity(_ id: String, _ kind: ActivityKind, _ start: Date, minutes: Double = 45, linked: Set<String> = []) -> ActivityCalendar.Activity {
        ActivityCalendar.Activity(id: id, kind: kind, title: kind.title, start: start,
                                  end: start.addingTimeInterval(minutes * 60), linkedWorkoutIDs: linked)
    }

    @Test func monthGridStartsOnTheFirstWeekday() {
        // 1 November 2026 is a Sunday: six blanks before it with Monday first.
        let cells = ActivityCalendar.monthGrid(containing: date(2026, 11, 18), calendar: calendar)
        #expect(cells.count % 7 == 0)
        #expect(cells.prefix(6).allSatisfy { $0 == nil })
        #expect(cells[6] == calendar.startOfDay(for: date(2026, 11, 1)))
        #expect(cells.compactMap { $0 }.count == 30)
        #expect(ActivityCalendar.weekdaySymbols(calendar: calendar).count == 7)
    }

    @Test func monthGridWithSundayFirst() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let cells = ActivityCalendar.monthGrid(containing: date(2026, 11, 18), calendar: sunday)
        #expect(cells.first == sunday.startOfDay(for: date(2026, 11, 1)))
        // February 2026 starts on a Sunday and has 28 days: exactly four rows.
        #expect(ActivityCalendar.monthGrid(containing: date(2026, 2, 10), calendar: sunday).count == 28)
    }

    @Test func monthGridAcrossDaylightSaving() {
        // October 2026 has the change back to winter time (25 Oct) in Zurich.
        let days = ActivityCalendar.monthGrid(containing: date(2026, 10, 5), calendar: calendar).compactMap { $0 }
        #expect(days.count == 31)
        #expect(Set(days).count == 31)
    }

    @Test func activitiesGroupByStartDayInTimeOrder() {
        let evening = activity("run", .run, date(2026, 11, 3, 18))
        let morning = activity("lift", .lifting, date(2026, 11, 3, 7))
        let lateNight = activity("walk", .walk, date(2026, 11, 3, 23), minutes: 90) // ends on the 4th
        let days = ActivityCalendar.days([evening, lateNight, morning], calendar: calendar)
        let day = days[calendar.startOfDay(for: date(2026, 11, 3))]
        #expect(day?.activities.map(\.id) == ["lift", "run", "walk"])
        #expect(day?.kinds == [.lifting, .run, .walk])
        #expect(days[calendar.startOfDay(for: date(2026, 11, 4))] == nil)
        #expect(abs((day?.minutes ?? 0) - 180) < 0.01)
    }

    @Test func kindsAreListedOnce() {
        let start = date(2026, 11, 5, 8)
        let days = ActivityCalendar.days([activity("a", .run, start), activity("b", .run, start.addingTimeInterval(7200)),
                                          activity("c", .sport, start.addingTimeInterval(9000))], calendar: calendar)
        #expect(days.values.first?.kinds == [.run, .sport])
    }

    @Test func linkedAndOverlappingWatchStrengthWorkoutsAreNotListedTwice() {
        let start = date(2026, 11, 6, 18)
        let session = activity("session", .lifting, start, minutes: 60, linked: ["watch-1"])
        let linked = activity("watch-1", .lifting, start, minutes: 60)
        let overlapping = activity("garmin", .lifting, start.addingTimeInterval(5 * 60), minutes: 50)
        let later = activity("other-strength", .lifting, start.addingTimeInterval(3 * 3600), minutes: 40)
        let run = activity("run", .run, start.addingTimeInterval(10 * 60), minutes: 30) // a run during it stays
        let merged = ActivityCalendar.merged(lifting: [session], health: [linked, overlapping, later, run])
        #expect(merged.map(\.id) == ["session", "run", "other-strength"])
    }

    @Test func emptyInputsGiveEmptyResults() {
        #expect(ActivityCalendar.merged(lifting: [], health: []).isEmpty)
        #expect(ActivityCalendar.days([], calendar: calendar).isEmpty)
        let summary = ActivityCalendar.summary([:], month: date(2026, 11, 1), calendar: calendar)
        #expect(summary.sessions == 0 && summary.activeDays == 0 && summary.byKind.isEmpty)
    }

    @Test func monthSummaryCountsOnlyThatMonth() {
        let all = [
            activity("1", .run, date(2026, 11, 2)), activity("2", .run, date(2026, 11, 4)),
            activity("3", .lifting, date(2026, 11, 4, 18)), activity("4", .ride, date(2026, 10, 30)),
        ]
        let summary = ActivityCalendar.summary(ActivityCalendar.days(all, calendar: calendar), month: date(2026, 11, 20), calendar: calendar)
        #expect(summary.sessions == 3)
        #expect(summary.activeDays == 2)
        #expect(summary.byKind.map(\.kind) == [.run, .lifting])
        #expect(abs(summary.minutes - 135) < 0.01)
    }

    @Test func tensileActivitiesMapToKinds() {
        #expect(ActivityKind.of(.treadmill) == .run)
        #expect(ActivityKind.of(.hiking) == .walk)
        #expect(ActivityKind.of(.indoorCycle) == .ride)
        #expect(ActivityKind.of(.squash) == .sport)
        #expect(ActivityKind.of(.snowboarding) == .snow)
        #expect(ActivityKind.of(.rower) == .otherCardio)
    }
}
