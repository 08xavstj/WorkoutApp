import Foundation
import Testing
@testable import AppCore

@Suite("Doses card: medications from 06:00, supplements from noon")
struct DoseCardTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: hour, minute: minute))!
    }

    @Test("Creatine and research-table supplements count as supplements", arguments: [
        "Creatine", "Creatine monohydrate 5 g", "Creapure", "Ashwagandha KSM-66", "Vitamin D3", "Magnesium glycinate", "Fish oil",
    ])
    func supplements(name: String) {
        #expect(DoseCard.isSupplement(name))
    }

    @Test("Medications and unknown names are never held back to noon", arguments: [
        "Sertraline", "Spironolactone", "Lisinopril 10 mg", "Something new", "",
    ])
    func medications(name: String) {
        #expect(!DoseCard.isSupplement(name))
    }

    @Test("A medication shows from 06:00, not from midnight")
    func medicationHours() {
        let day = time(0)
        #expect(!DoseCard.shows(name: "Sertraline", day: day, at: time(0, 5), calendar: calendar))
        #expect(!DoseCard.shows(name: "Sertraline", day: day, at: time(5, 59), calendar: calendar))
        #expect(DoseCard.shows(name: "Sertraline", day: day, at: time(6), calendar: calendar))
        #expect(DoseCard.shows(name: "Sertraline", day: day, at: time(23), calendar: calendar))
    }

    @Test("Creatine shows from noon")
    func creatineHours() {
        let day = time(9)
        #expect(!DoseCard.shows(name: "Creatine", day: day, at: time(6), calendar: calendar))
        #expect(!DoseCard.shows(name: "Creatine", day: day, at: time(11, 59), calendar: calendar))
        #expect(DoseCard.shows(name: "Creatine", day: day, at: time(12), calendar: calendar))
        #expect(DoseCard.showFrom(name: "Creatine", day: day, calendar: calendar) == time(12))
    }
}
