import Foundation

/// Quick-estimate meals (Claude's guess from a description or photo) and how
/// they're kept out of the measured-maintenance calculation.
///
/// AI estimates from food photos get calories and protein about as close as
/// dietitians but miss by more than 10% on most nutrients, mostly under
/// (O'Hara et al., Nutrients 2025); energy error reached 54% on complex
/// meals without context (docs/research/nutrition.md "how accurate"). So an
/// estimate is logged with an "estimate" flag and a ±30% band, and a day
/// made only of estimates is down-weighted in `AdaptiveTDEE` as a partial day.
public enum EstimatedIntake {
    /// The band shown with every estimate (nutrition.md suggests ±25%; ±30%
    /// is the conservative choice given the 54% errors on complex meals).
    public static let uncertaintyPercent = 30
    public static let caveat = "Estimate ±30%; logged in Cronometer counts as the record."
    /// Sanity limits for one meal; anything outside is rejected as a bad guess.
    public static let maximumMealKcal = 3000.0
    public static let maximumMacroGrams = 400.0

    /// What the server returns for one meal.
    public struct Estimate: Codable, Sendable, Equatable {
        public var summary: String
        public var calories: Double
        public var proteinGrams: Double
        public var carbsGrams: Double
        public var fatGrams: Double
        public var fibreGrams: Double
        /// "low", "medium" or "high": how sure the model was, mostly about portion size.
        public var confidence: String
        public var assumptions: String?

        public init(summary: String, calories: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double, fibreGrams: Double, confidence: String, assumptions: String? = nil) {
            self.summary = summary
            self.calories = calories
            self.proteinGrams = proteinGrams
            self.carbsGrams = carbsGrams
            self.fatGrams = fatGrams
            self.fibreGrams = fibreGrams
            self.confidence = confidence
            self.assumptions = assumptions
        }

        public var isPlausible: Bool {
            let macros = [proteinGrams, carbsGrams, fatGrams, fibreGrams]
            return calories > 0 && calories <= EstimatedIntake.maximumMealKcal
                && macros.allSatisfy { $0 >= 0 && $0 <= EstimatedIntake.maximumMacroGrams }
        }

        /// "about 650 kcal (455-845)"
        public var calorieRangeText: String {
            let spread = calories * Double(EstimatedIntake.uncertaintyPercent) / 100
            return "about \(Int(calories.rounded())) kcal (\(Int((calories - spread).rounded()))-\(Int((calories + spread).rounded())))"
        }
    }

    /// The calorie value an estimate-only day is given so `AdaptiveTDEE`'s
    /// partial-day rule skips it: 800 kcal is its lowest "logged" value and
    /// sits under the 70%-of-median floor for any realistic food log.
    public static let partialMarkerKcal = 800.0

    /// Marks days whose only food entries were estimates as partial days.
    ///
    /// Such a day keeps the 800 kcal marker, which `AdaptiveTDEE.split` then
    /// classes as partial (counted in `partialDaysSkipped`, left out of the
    /// maintenance estimate). When estimated days are at least half of the
    /// logged days the median would collapse onto the marker, so they're
    /// dropped instead (the maintenance estimate then waits for real logs).
    public static func downWeight(_ intake: [DayValue], estimatedOnlyDays: Set<Date>, calendar: Calendar = .current) -> [DayValue] {
        guard !estimatedOnlyDays.isEmpty else { return intake }
        let flagged = Set(estimatedOnlyDays.map { calendar.startOfDay(for: $0) })
        func isFlagged(_ day: DayValue) -> Bool { flagged.contains(calendar.startOfDay(for: day.date)) }
        let normal = intake.filter { !isFlagged($0) && $0.value >= partialMarkerKcal }
        let estimated = intake.filter { isFlagged($0) }
        guard estimated.count * 2 < normal.count else {
            return intake.filter { !isFlagged($0) }
        }
        return intake.map { day in
            isFlagged(day) ? DayValue(date: day.date, value: min(day.value, partialMarkerKcal)) : day
        }
    }
}
