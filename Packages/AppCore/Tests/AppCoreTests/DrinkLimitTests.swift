import Foundation
import Testing
@testable import AppCore

struct DrinkLimitTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Tuesday 17 November 2026, 21:00 UTC.
    var now: Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 21))! }

    /// 28 evenings ending tonight; `drinks(back)` is the count `back` evenings ago, nil when not logged.
    func evenings(_ drinks: (Int) -> Int?) -> [EveningCheckIn] {
        (0..<28).compactMap { back in
            guard let count = drinks(back) else { return nil }
            var evening = EveningCheckIn(day: utc.startOfDay(for: utc.date(byAdding: .day, value: -back, to: now)!))
            evening.drinks = count
            return evening
        }
    }

    @Test func offeredFromThreeAWeekOnly() {
        #expect(DrinkLimit.offerFromWeeklyAverage == 3)
        // Two a week (Friday and Saturday): nothing to cut down to, no control.
        let light = DrinkLimit.history(evenings: evenings { [3, 4].contains($0 % 7) ? 1 : 0 }, now: now, calendar: utc)
        #expect(light.weeklyAverage == 2)
        #expect(!DrinkLimit.isOffered(history: light, limit: nil))
        // Three a week: offered.
        let three = DrinkLimit.history(evenings: evenings { [2, 3, 4].contains($0 % 7) ? 1 : 0 }, now: now, calendar: utc)
        #expect(three.weeklyAverage == 3)
        #expect(DrinkLimit.isOffered(history: three, limit: nil))
        // Once set it stays, so it can be changed or removed.
        #expect(DrinkLimit.isOffered(history: light, limit: 2))
    }

    /// Evenings not logged don't count as dry ones, and too few means no average.
    @Test func theAverageIsOverLoggedEveningsOnly() {
        // Logged only on drinking evenings: five a week, one drink each, 20 evenings in all.
        let sparse = DrinkLimit.history(evenings: evenings { $0 % 7 < 5 ? 1 : nil }, now: now, calendar: utc)
        #expect(sparse.nightsLogged == 20)
        #expect(sparse.weeklyAverage == 7)
        let thin = DrinkLimit.history(evenings: evenings { $0 < 10 ? 2 : nil }, now: now, calendar: utc)
        #expect(thin.weeklyAverage == nil)
        #expect(!DrinkLimit.isOffered(history: thin, limit: nil))
    }

    @Test func theStepperStartsOneUnderTheAverageAndNeverUnderTheLowLine() {
        func history(_ perWeek: Double) -> DrinkLimit.History {
            DrinkLimit.History(weeklyTotals: [perWeek, perWeek, perWeek, perWeek], nightsLogged: 28, totalDrinks: perWeek * 4)
        }
        #expect(DrinkLimit.suggested(history: history(9)) == 8)
        #expect(DrinkLimit.suggested(history: history(5.5)) == 4)
        #expect(DrinkLimit.suggested(history: history(3)) == 2)
        #expect(DrinkLimit.suggested(history: history(30)) == 21)
    }

    @Test func theCountIsShownAgainstTheLimitWithoutAVerdict() {
        #expect(DrinkLimit.line(drinks: 3, limit: 4) == "3 of up to 4 in the last 7 nights")
        #expect(DrinkLimit.line(drinks: 5.5, limit: 4) == "5.5 of up to 4 in the last 7 nights")
        #expect(DrinkLimit.eveningLine(drinks: 2, limit: 4) == "With tonight: 2 of up to 4 in the last 7 nights.")
        for text in [DrinkLimit.line(drinks: 9, limit: 4), DrinkLimit.clinicianLine] {
            #expect(!text.lowercased().contains("over"))
            #expect(!text.lowercased().contains("missed"))
        }
    }

    /// The clinician line needs four known weeks, all in the top tier.
    @Test func theClinicianLineNeedsFourWeeksInTheTopTier() {
        let heavy = DrinkLimit.history(evenings: evenings { _ in 1 }, now: now, calendar: utc)
        #expect(heavy.weeklyTotals == [7, 7, 7, 7])
        #expect(DrinkLimit.staysInTopTier(heavy))
        // One week at six (the oldest) breaks the run.
        let dip = DrinkLimit.history(evenings: evenings { $0 == 25 ? 0 : 1 }, now: now, calendar: utc)
        #expect(dip.weeklyTotals.first == 6)
        #expect(!DrinkLimit.staysInTopTier(dip))
        // A week with only three evenings logged is unknown, so the run isn't shown.
        let gap = DrinkLimit.history(evenings: evenings { (7..<11).contains($0) ? nil : 2 }, now: now, calendar: utc)
        #expect(gap.weeklyTotals[2] == nil)
        #expect(!DrinkLimit.staysInTopTier(gap))
    }

    /// A drinks limit is one of the measurable weekly changes, starting from the owner's own.
    @Test func theLimitIsAlsoAWeeklyChange() {
        var context = WeeklyChangeSuggestions.Context()
        context.drinkLimit = 4
        let change = WeeklyChangeSuggestions.measurable(context).first { $0.kind == .drinksLimit }
        #expect(change?.target == 4)
        #expect(change?.title == "Up to 4 drinks this week")
    }
}
