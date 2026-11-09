import Foundation
import Testing
@testable import AppCore

struct MedicationScheduleTests {
    /// A calendar with a spring-forward day (US: 8 March 2026).
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    @Test func dailyIncludesEveryDay() {
        for offset in 0..<10 {
            let date = calendar.date(byAdding: .day, value: offset, to: day(2026, 3, 1)) ?? Date()
            #expect(MedicationSchedule.daily.includes(date, calendar: calendar))
        }
        #expect(!MedicationSchedule.daily.isLessThanDaily)
    }

    @Test func weeklyFallsOnOneWeekdayOnly() {
        // 9 November 2026 is a Monday (weekday 2).
        let schedule = MedicationSchedule.weekly(onWeekdayOf: day(2026, 11, 9), calendar: calendar)
        #expect(schedule.weekdays == [2])
        #expect(schedule.isWeekly && schedule.isLessThanDaily)
        let due = (0..<28).compactMap { calendar.date(byAdding: .day, value: $0, to: day(2026, 11, 9)) }
            .filter { schedule.includes($0, calendar: calendar) }
        #expect(due.count == 4)
        #expect(due.allSatisfy { calendar.component(.weekday, from: $0) == 2 })
        #expect(schedule.summary(calendar: calendar) == "Weekly on Monday")
    }

    @Test func everyThreeDaysCountsCalendarDaysAcrossDST() {
        // Anchored before the 8 March clock change; 24-hour arithmetic would drift by an hour.
        let schedule = MedicationSchedule.every(3, from: day(2026, 3, 6))
        #expect(schedule.includes(day(2026, 3, 6), calendar: calendar))
        #expect(!schedule.includes(day(2026, 3, 7), calendar: calendar))
        #expect(schedule.includes(day(2026, 3, 9), calendar: calendar))
        #expect(schedule.includes(day(2026, 3, 12), calendar: calendar))
        // Nothing before the start day.
        #expect(!schedule.includes(day(2026, 3, 3), calendar: calendar))
        #expect(schedule.summary(calendar: calendar) == "Every 3 days")
        #expect(MedicationSchedule.every(2, from: day(2026, 3, 6)).summary(calendar: calendar) == "Every other day")
    }

    @Test func nextDayFindsTheComingDose() throws {
        let schedule = MedicationSchedule.weekly(on: 6) // Friday
        let next = try #require(schedule.nextDay(onOrAfter: day(2026, 11, 9), calendar: calendar))
        #expect(calendar.component(.weekday, from: next) == 6)
        #expect(calendar.dateComponents([.day], from: calendar.startOfDay(for: day(2026, 11, 9)), to: next).day == 4)
        #expect(MedicationSchedule(kind: .weekdays, weekdays: []).nextDay(onOrAfter: day(2026, 11, 9), calendar: calendar) == nil)
    }

    @Test func weekdaySummaryFollowsTheWeekOrder() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let schedule = MedicationSchedule(kind: .weekdays, weekdays: [1, 2, 4])
        #expect(schedule.summary(calendar: mondayFirst) == "Mon, Wed, Sun")
        #expect(MedicationSchedule.weekOrder(calendar: mondayFirst).first == 2)
        #expect(MedicationSchedule(kind: .weekdays, weekdays: Set(1...7)).summary(calendar: calendar) == "Every day")
    }

    @Test func decodesOldAndPartialJSON() throws {
        let partial = try JSONDecoder().decode(MedicationSchedule.self, from: Data(#"{"kind":"weekdays","weekdays":[3]}"#.utf8))
        #expect(partial.kind == .weekdays && partial.weekdays == [3])
        let empty = try JSONDecoder().decode(MedicationSchedule.self, from: Data("{}".utf8))
        #expect(empty.kind == .daily)
        let unknown = try JSONDecoder().decode(MedicationSchedule.self, from: Data(#"{"kind":"monthly"}"#.utf8))
        #expect(unknown.kind == .daily)
        let original = MedicationSchedule.every(4, from: day(2026, 1, 2))
        let roundTrip = try JSONDecoder().decode(MedicationSchedule.self, from: JSONEncoder().encode(original))
        #expect(roundTrip == original)
    }

    @Test(arguments: [
        ("Ozempic", true), ("ozempic 0.5 mg", true), ("Mounjaro 5mg", true), ("Zepbound", true),
        ("Trulicity", true), ("Wegovy", true), ("semaglutide", true),
        ("Rybelsus", false), ("Wegovy pill", false), ("Semaglutide tablets", false),
        ("Victoza", false), ("Saxenda", false), ("Metformin", false), ("Creatine", false),
    ])
    func weeklyGLP1sAreRecognised(name: String, weekly: Bool) {
        #expect((MedicationKnowledge.usualSchedule(for: name) == .weekdays) == weekly)
    }
}

struct DrugLabelSearchTests {
    @Test func searchesTheWholeNameFirst() {
        #expect(DrugLabelSearch.terms(for: "Vitamin D3") == ["vitamin d3", "vitamin"])
        #expect(DrugLabelSearch.terms(for: "Metoprolol succinate 25 mg") == ["metoprolol succinate", "metoprolol"])
        #expect(DrugLabelSearch.terms(for: "Lipitor 20mg") == ["lipitor"])
        #expect(DrugLabelSearch.terms(for: "ozempic 0.5mg") == ["ozempic"])
        #expect(DrugLabelSearch.terms(for: "5 mg").isEmpty)
    }

    @Test func aLabelMustNameTheDrug() {
        // The old first-word search showed this for "Vitamin D3".
        #expect(!DrugLabelSearch.matches(term: "vitamin", labelNames: ["Vitamin D3 and Calcium", "Centrum Silver"]))
        #expect(!DrugLabelSearch.matches(term: "vitamin d3", labelNames: ["Vitamin C"]))
        #expect(DrugLabelSearch.matches(term: "vitamin d3", labelNames: ["VITAMIN D3"]))
        #expect(DrugLabelSearch.matches(term: "lipitor", labelNames: ["LIPITOR", "ATORVASTATIN CALCIUM"]))
        #expect(DrugLabelSearch.matches(term: "metoprolol", labelNames: ["METOPROLOL SUCCINATE"]))
        #expect(DrugLabelSearch.matches(term: "metoprolol succinate", labelNames: ["Metoprolol"]))
        #expect(!DrugLabelSearch.matches(term: "metoprolol", labelNames: ["HYDROCHLOROTHIAZIDE AND METOPROLOL"]))
        #expect(!DrugLabelSearch.matches(term: "", labelNames: ["Anything"]))
    }
}

struct CycleRecoveryTests {
    @Test func notesTheLutealWindowOnly() throws {
        let note = try #require(CycleRecovery.contributor(sex: .female, daysSinceLastPeriod: 15))
        #expect(note.effect == .neutral && note.weight == 0)
        #expect(note.explanation.contains("Schmalenberger"))
        #expect(note.explanation.contains("Weak evidence"))
        #expect(CycleRecovery.contributor(sex: .female, daysSinceLastPeriod: 3) == nil)
        #expect(CycleRecovery.contributor(sex: .female, daysSinceLastPeriod: 30) == nil)
        #expect(CycleRecovery.contributor(sex: .female, daysSinceLastPeriod: nil) == nil)
        #expect(CycleRecovery.contributor(sex: .male, daysSinceLastPeriod: 15) == nil)
    }
}

struct GripAdviceUnitTests {
    @Test func poundsUsersReadPounds() {
        let text = GripStrength.advice(.belowAverage, age: 30, sex: .male, inPounds: true)
        #expect(text.contains("lb"))
        #expect(!text.contains("kg"))
        #expect(text.contains("11 lb less"))
        #expect(GripStrength.advice(.belowCutoff, age: 30, sex: .female, inPounds: true).contains("Under 35 lb"))
        #expect(GripStrength.advice(.average, age: 30, sex: .male).contains("kg"))
    }
}
