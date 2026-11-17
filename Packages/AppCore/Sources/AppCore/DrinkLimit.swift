import Foundation

/// A weekly drink limit the owner sets himself, shown against the count.
///
/// The evidence is moderate and the effect small: personalised digital tools
/// cut drinking by about 23 g of alcohol a week (roughly 3 UK units) across
/// 57 trials, and goal setting was among the techniques tied to larger
/// effects (Kaner et al., Cochrane Database Syst Rev 2017); the best-tested
/// app's primary result was not significant (Oldham et al., EClinicalMedicine
/// 2024). So this is one number and the count beside it, for someone who
/// wants to cut down, and nothing for anyone else
/// (docs/research/healthy-living-2026-11.md §3 item 9). The owner's own
/// next-morning HRV and heart rate stay the feedback (`AlcoholEffect`).
///
/// An app is not the tool for dependence: when the count stays in the top
/// tier, one line points to a clinician (`clinicianLine`).
public enum DrinkLimit {
    /// The four-week average, drinks a week, from which a limit is offered:
    /// the first number past the low-risk tier in Canada's 2023 guidance
    /// (`AlcoholWeek.lowMax` is 2; CCSA 2023). Under it there is nothing to
    /// cut down to, so the control isn't shown.
    public static let offerFromWeeklyAverage = AlcoholWeek.lowMax + 1
    public static let weeks = 4
    /// Evenings logged in the four weeks before an average is worked out
    /// (app's choice: half of them). A logged zero counts.
    public static let minimumNightsLogged = 14
    /// The stepper's range, drinks a week (app's choice).
    public static let range = 0...21

    /// The last four weeks of logged evenings.
    public struct History: Sendable, Equatable {
        /// Totals of the four 7-night blocks, oldest first; nil for a block
        /// with fewer than `HealthFloors.drinksMinimumNights` evenings logged.
        public var weeklyTotals: [Double?]
        public var nightsLogged: Int
        public var totalDrinks: Double

        public init(weeklyTotals: [Double?], nightsLogged: Int, totalDrinks: Double) {
            self.weeklyTotals = weeklyTotals
            self.nightsLogged = nightsLogged
            self.totalDrinks = totalDrinks
        }

        /// Drinks a week over the evenings that were logged, so an evening
        /// that wasn't logged doesn't count as a dry one. Nil with too few.
        public var weeklyAverage: Double? {
            nightsLogged >= DrinkLimit.minimumNightsLogged ? totalDrinks / Double(nightsLogged) * 7 : nil
        }
    }

    /// - Parameter evenings: the evening check-ins on hand; those from the 28
    ///   evenings up to and including today's are used.
    public static func history(evenings: [EveningCheckIn], now: Date = .now, calendar: Calendar = .current) -> History {
        let today = calendar.startOfDay(for: now)
        var totals: [Double?] = []
        var logged = 0
        var drinks = 0.0
        for block in (0..<weeks).reversed() {
            let days = (0..<AlcoholWeek.nights).compactMap { calendar.date(byAdding: .day, value: -(block * AlcoholWeek.nights + $0), to: today) }
            let week = AlcoholWeek.total(evenings: evenings.filter { evening in days.contains { calendar.isDate($0, inSameDayAs: evening.day) } })
            totals.append(week.nightsLogged >= HealthFloors.drinksMinimumNights ? week.drinks : nil)
            logged += week.nightsLogged
            drinks += week.drinks
        }
        return History(weeklyTotals: totals, nightsLogged: logged, totalDrinks: drinks)
    }

    /// The control shows once the four-week average is three or more a week,
    /// and stays while a limit is set (so it can be changed or removed).
    public static func isOffered(history: History, limit: Double?) -> Bool {
        if limit != nil { return true }
        return (history.weeklyAverage ?? 0) >= offerFromWeeklyAverage
    }

    /// Where the stepper starts: one under the recent average, never under
    /// the low-risk line. App's choice; the limit is the owner's to set.
    public static func suggested(history: History) -> Int {
        let average = history.weeklyAverage ?? offerFromWeeklyAverage
        return min(range.upperBound, max(Int(AlcoholWeek.lowMax), Int(average.rounded(.down)) - 1))
    }

    /// "3 of up to 4 in the last 7 nights". Plain count, no verdict.
    public static func line(drinks: Double, limit: Double) -> String {
        "\(Longevity.one(drinks)) of up to \(Longevity.one(limit)) in the last \(AlcoholWeek.nights) nights"
    }

    /// For the evening check-in, where tonight's answer is part of the count.
    public static func eveningLine(drinks: Double, limit: Double) -> String {
        "With tonight: " + line(drinks: drinks, limit: limit) + "."
    }

    /// Every one of the four weeks is known and in the top tier of Canada's
    /// guidance (7 or more; `AlcoholWeek.Tier.high`).
    public static func staysInTopTier(_ history: History) -> Bool {
        history.weeklyTotals.count == weeks && history.weeklyTotals.allSatisfy { total in
            total.map { AlcoholWeek.tier(drinks: $0) == .high } ?? false
        }
    }

    /// One line, shown only when `staysInTopTier`.
    public static let clinicianLine = "Seven or more a week for four weeks running. Cutting down from here goes better with a doctor or an alcohol service than with an app."
}
