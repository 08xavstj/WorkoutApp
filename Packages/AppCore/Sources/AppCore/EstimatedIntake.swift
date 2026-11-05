import Foundation

/// Keeps AI-estimated meals out of the measured-maintenance calculation.
///
/// Earlier versions of the app logged meals as AI guesses from a description
/// or photo, flagged as estimates in Apple Health. The app no longer writes
/// them, but the flagged samples are still there. AI estimates from food
/// photos get calories and protein about as close as dietitians but miss by
/// more than 10% on most nutrients, mostly under (O'Hara et al., Nutrients
/// 2025); energy error reached 54% on complex meals without context
/// (docs/research/nutrition.md "how accurate"). So a day made only of
/// estimates is down-weighted in `AdaptiveTDEE` as a partial day.
public enum EstimatedIntake {
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
