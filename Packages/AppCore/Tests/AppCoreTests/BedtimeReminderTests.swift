import Foundation
import Testing
@testable import AppCore

struct BedtimeReminderTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func at(_ hour: Int, _ minute: Int, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func thirtyMinutesBeforeTheWindowForThreeNights() {
        let fires = BedtimeReminder.fireDates(windowStart: at(22, 30), now: at(18, 0), calendar: calendar)
        #expect(fires == [at(22, 0), at(22, 0, day: 21), at(22, 0, day: 22)])
    }

    @Test func tonightAlreadyPastStartsTomorrow() {
        let fires = BedtimeReminder.fireDates(windowStart: at(22, 30), now: at(22, 10), calendar: calendar)
        #expect(fires.first == at(22, 0, day: 21))
        #expect(fires.count == BedtimeReminder.nightsAhead)
    }

    @Test func textNamesTheWindowAndWhy() {
        let text = BedtimeReminder.content(windowText: "22:30–23:00", startText: "22:30",
                                           reason: "8 h need, up at 6:30", sleepWindow: false)
        #expect(text.title == "In bed by 22:30–23:00")
        #expect(text.body.contains("up at 6:30"))
    }

    @Test func sleepWindowSaysWhenSleepy() {
        let text = BedtimeReminder.content(windowText: "23:45–00:15", startText: "23:45",
                                           reason: "6 h 45 min sleep window, up at 6:30 every day", sleepWindow: true)
        #expect(text.title.contains("when sleepy"))
    }
}
