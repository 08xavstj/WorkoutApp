import Foundation
import Testing
@testable import AppCore

// The Watch's "Intervals" card (`IntervalGlance`, docs/research/next-features-2026-11.md W4).

private let calendar = SimFixtures.calendar
/// Monday 5 January 2026.
private let monday = SimFixtures.monday

private func at(_ dayOffset: Int, _ hour: Int = 9) -> Date {
    calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour), to: monday)!
}

@Suite("Intervals card on the Watch")
struct IntervalGlanceTests {
    /// Written Monday 09:00 for Thursday; the week ends next Monday.
    func session(day: Date? = at(3, 0), updated: Date = at(0), done: Bool = false, waitsOn: Date? = nil) -> IntervalGlance.Session {
        IntervalGlance.Session(updated: updated, title: "4 × 4 min · Bike", symbol: "figure.indoor.cycle", minutes: 40,
                               day: day, weekEnd: at(7, 0), done: done, waitsOn: waitsOn)
    }

    func state(_ session: IntervalGlance.Session?, _ now: Date) -> IntervalGlance.State {
        IntervalGlance.state(of: session, at: now, calendar: calendar)
    }

    @Test func laterThenTodayThenGone() {
        let written = session(updated: at(2))
        #expect(state(written, at(2)) == .later(written, day: at(3, 0)))
        #expect(state(written, at(3, 7)) == .today(written))
        #expect(state(written, at(4)) == .none)
    }

    @Test func doneWaitsAndNothingFromThePhone() {
        #expect(state(session(done: true), at(0, 10)) == .done)
        let waits = session(updated: at(3, 8), waitsOn: at(3, 0))
        #expect(state(waits, at(3, 9)) == .waits(waits))
        #expect(state(nil, at(0)) == .none)
        // Too old to trust: written Monday, read on Wednesday (carry is one day).
        #expect(state(session(), at(2)) == .none)
        let anyDay = session(day: nil)
        #expect(state(anyDay, at(0, 12)) == .anyDay(anyDay))
        let anyDayWaits = session(day: nil, waitsOn: at(0, 0))
        #expect(state(anyDayWaits, at(0, 12)) == .waits(anyDayWaits))
    }

    @Test func offeredOnItsDayFromTheMorning() {
        let written = session(updated: at(2, 20))
        let windows = IntervalGlance.relevantWindows(of: written, after: at(2, 21), calendar: calendar)
        #expect(windows == [DateInterval(start: at(3, IntervalGlance.relevanceStartHour), end: at(4, 0))])
        // During the day, still offered until midnight.
        #expect(IntervalGlance.relevantWindows(of: written, after: at(3, 12), calendar: calendar).first?.end == at(4, 0))
    }

    @Test func notOfferedWhenDoneWaitingFlexibleOrStale() {
        #expect(IntervalGlance.relevantWindows(of: session(updated: at(2), done: true), after: at(2), calendar: calendar).isEmpty)
        #expect(IntervalGlance.relevantWindows(of: session(updated: at(3, 7), waitsOn: at(3, 0)), after: at(3, 8), calendar: calendar).isEmpty)
        #expect(IntervalGlance.relevantWindows(of: session(day: nil), after: at(0), calendar: calendar).isEmpty)
        // Written Monday for Thursday: by Thursday the data is too old, so nothing yet.
        #expect(IntervalGlance.relevantWindows(of: session(), after: at(0), calendar: calendar).isEmpty)
        #expect(IntervalGlance.relevantWindows(of: nil, after: at(0), calendar: calendar).isEmpty)
    }

    @Test func changeDatesCoverTheDayAndTrust() {
        let dates = IntervalGlance.changeDates(of: session(updated: at(2)), after: at(2), calendar: calendar)
        // Thursday 00:00 (its day), Friday 00:00 (its end, and when Wednesday's data stops being trusted).
        // The week's end is past the 48-hour horizon.
        #expect(dates == [at(3, 0), at(4, 0)])
    }

    @Test func wordsSayWhatAndWhen() {
        let today = IntervalGlance.lines(for: .today(session()))
        #expect(today.eyebrow == "Intervals today")
        #expect(today.title == "4 × 4 min · Bike")
        #expect(IntervalGlance.lines(for: .none).title == "--")
        #expect(IntervalGlance.lines(for: .done).title == "Done this week")
        #expect(IntervalGlance.lines(for: .waits(session())).title == "Not today")
    }
}
