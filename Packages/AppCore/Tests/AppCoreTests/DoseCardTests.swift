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

    // "monohydrate" is a salt form of many medicines, not a creatine alias.
    @Test("A medicine whose name carries a supplement word is still a medicine", arguments: [
        "Doxycycline Monohydrate", "Doxycycline monohydrate 100 mg", "Acetaminophen/Caffeine", "Aspirin + Caffeine",
        "Paracetamol and caffeine", "Butalbital/Acetaminophen/Caffeine", "Ibuprofen with caffeine", "Sertraline, magnesium",
        "Melatonin + sertraline", "Testosterone cypionate",
    ])
    func medicinesWithSupplementWords(name: String) {
        #expect(!DoseCard.isSupplement(name))
    }

    @Test("Creatine and melatonin are in both tables and stay supplements", arguments: [
        "Creatine monohydrate", "Melatonin 1 mg", "Caffeine pills", "Whey protein", "Creatine + melatonin",
        "Magnesium and melatonin", "Testosterone booster",
    ])
    func supplementsInBothTables(name: String) {
        #expect(DoseCard.isSupplement(name))
    }

    @Test("A dose joins two hours before its own time, never before its floor hour")
    func leadBeforeTheDose() {
        let day = time(0)
        // Morning medication at 08:00: two hours before is 06:00, the floor.
        #expect(DoseCard.showFrom(name: "Sertraline", day: day, minutes: 8 * 60, calendar: calendar) == time(6))
        // At 07:00: 05:00 would be before the floor, so 06:00.
        #expect(DoseCard.showFrom(name: "Sertraline", day: day, minutes: 7 * 60, calendar: calendar) == time(6))
        // Evening medication at 21:30: from 19:30, not all day.
        #expect(DoseCard.showFrom(name: "Sertraline", day: day, minutes: 21 * 60 + 30, calendar: calendar) == time(19, 30))
        #expect(!DoseCard.shows(name: "Sertraline", day: day, minutes: 21 * 60 + 30, at: time(12), calendar: calendar))
        #expect(DoseCard.shows(name: "Sertraline", day: day, minutes: 21 * 60 + 30, at: time(19, 30), calendar: calendar))
        // Creatine set for 08:00 still waits for noon; set for 18:00 it joins at 16:00.
        #expect(DoseCard.showFrom(name: "Creatine", day: day, minutes: 8 * 60, calendar: calendar) == time(12))
        #expect(DoseCard.showFrom(name: "Creatine", day: day, minutes: 13 * 60, calendar: calendar) == time(12))
        #expect(DoseCard.showFrom(name: "Creatine", day: day, minutes: 18 * 60, calendar: calendar) == time(16))
        // The versions without a dose time keep giving the floor hours.
        #expect(DoseCard.showFrom(name: "Sertraline", day: day, calendar: calendar) == time(6))
        #expect(DoseCard.shows(name: "Sertraline", day: day, at: time(6), calendar: calendar))
    }

    @Test("A card the user swiped away comes back only when a new dose joins")
    func dismissedCardStaysAway() {
        let today = "2026-11-16"
        // Nothing to take: no card.
        #expect(!DoseCard.mayStart(remaining: [], dayKey: today, last: nil))
        // First card of the day, or yesterday's log.
        #expect(DoseCard.mayStart(remaining: ["a"], dayKey: today, last: nil))
        #expect(DoseCard.mayStart(remaining: ["a"], dayKey: today, last: DoseCard.CardLog(day: "2026-11-15", offered: ["a"])))
        // Started today with "a", not ended by the app, and gone: it was dismissed.
        let dismissed = DoseCard.CardLog(day: today, offered: ["a"])
        #expect(!DoseCard.mayStart(remaining: ["a"], dayKey: today, last: dismissed))
        // The evening dose joins: the card may come back.
        #expect(DoseCard.mayStart(remaining: ["a", "b"], dayKey: today, last: dismissed))
        #expect(DoseCard.mayStart(remaining: ["b"], dayKey: today, last: dismissed))
        // The app ended it (all taken); a dose unticked later brings it back.
        #expect(DoseCard.mayStart(remaining: ["a"], dayKey: today, last: DoseCard.CardLog(day: today, offered: ["a"], endedByApp: true)))
    }
}
