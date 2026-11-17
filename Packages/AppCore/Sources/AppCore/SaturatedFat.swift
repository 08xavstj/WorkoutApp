import Foundation

/// Saturated fat as a share of the week's energy, from the food log
/// (docs/research/evidence-audit-2026-11.md, Gaps, item 3).
///
/// - Target: under 10% of energy. WHO 2023 guideline on saturated and trans
///   fatty acids: "no more than 10% of total energy intake coming from
///   saturated fatty acids", replaced by polyunsaturated or plant
///   monounsaturated fats or by fibre-rich carbohydrates (whole grains,
///   vegetables, fruit, pulses). Read at who.int (news item 17 July 2023).
/// - Effect: cutting saturated fat for at least 2 years lowered combined
///   cardiovascular events by 17% (RR 0.83), with little or no effect on
///   all-cause mortality (RR 0.96) (Hooper et al., Cochrane 2020, CD011737,
///   PMID 32827219, abstract read). GRADE moderate: about 1 event avoided for
///   every 56 people without heart disease who cut it for about 4 years.
/// - Judged over the week, never the day (a single day says little, and
///   daily pass/fail food targets go with disordered eating in
///   cross-sectional work: `healthy-living-2026-11.md`, section 5).
/// - Nothing at all when the food app sends no saturated fat: a missing value
///   must not read as zero.
public enum SaturatedFat {
    /// WHO 2023: under 10% of energy.
    public static let limitShare = 10.0
    /// "A little over" up to this share (app's choice: within about one
    /// tablespoon of butter a day of the line at a typical intake).
    public static let closeShare = 12.0
    /// kcal per gram of fat (Atwater factor).
    public static let kcalPerGram = 9.0
    /// Logged days needed in the week (the same 4 as `Micronutrients.assess`).
    public static let minimumDays = 4
    /// A food app that exports saturated fat for some foods only would read
    /// low: it must be on this share of logged days (as `NutrientCoverage`).
    public static let minimumCoverage = 0.8
    /// A day counts as logged from this much energy (as `nutrientAverages`).
    public static let loggedDayKcal = 800.0

    public enum Status: String, Sendable, Equatable {
        case under, close, over
    }

    public struct Day: Sendable, Equatable {
        public var date: Date
        public var energyKcal: Double
        /// Grams; nil when the food app sent none that day.
        public var saturatedGrams: Double?

        public init(date: Date, energyKcal: Double, saturatedGrams: Double?) {
            self.date = date
            self.energyKcal = energyKcal
            self.saturatedGrams = saturatedGrams
        }
    }

    public struct Week: Sendable, Equatable {
        /// Percent of energy, 0-100.
        public var share: Double
        /// Daily average grams over the days used.
        public var gramsPerDay: Double
        public var days: Int
        public var status: Status

        /// "9% of energy"
        public var shareText: String { "\(Int(share.rounded()))% of energy" }

        /// One plain line: where it sits and, if over, what to swap.
        public var line: String {
            switch status {
            case .under: "Under the 10% line this week."
            case .close: "A little over the 10% line this week. Swapping some butter, cheese or fatty meat for olive oil, nuts or fish brings it under."
            case .over: "Over the 10% line this week. Swapping butter, cheese, fatty meat and pastries for olive oil, nuts, fish, beans or whole grains brings it down."
            }
        }
    }

    /// The week's share: saturated-fat energy over all energy, summed over
    /// logged days that carry a saturated-fat value. Nil with fewer than
    /// `minimumDays` such days or when the food app leaves it out on more
    /// than a fifth of logged days.
    public static func week(_ days: [Day]) -> Week? {
        let logged = days.filter { $0.energyKcal >= loggedDayKcal }
        let withFat = logged.filter { $0.saturatedGrams != nil }
        guard withFat.count >= minimumDays,
              Double(withFat.count) >= Double(logged.count) * minimumCoverage else { return nil }
        let energy = withFat.map(\.energyKcal).reduce(0, +)
        let grams = withFat.compactMap(\.saturatedGrams).reduce(0, +)
        guard energy > 0 else { return nil }
        let share = grams * kcalPerGram / energy * 100
        let status: Status = share < limitShare ? .under : (share < closeShare ? .close : .over)
        return Week(share: share, gramsPerDay: grams / Double(withFat.count), days: withFat.count, status: status)
    }
}
