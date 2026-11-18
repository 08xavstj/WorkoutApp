import Foundation

// The numbers behind the share images (cardio, lifting, weekly summary):
// what goes on a card and how it is rounded. Spec §5a B1, B3, B4 and §6 of
// docs/research/competitor-features-2026-11.md. Sharing a summary is a form
// of reporting progress to others, which raised goal attainment in a
// meta-analysis of 138 studies (Harkin et al., Psychol Bull 2016, d = 0.40);
// social features themselves show no consistent activity gain (Tong &
// Laranjo, npj Digit Med 2018), so cards are private by default and made
// only when the user taps Share.

public nonisolated enum ShareCards {
    // MARK: Image size

    /// 1080 × 1350 px (4:5, the portrait size social feeds show uncropped):
    /// spec §6 "Cardio card ... 1080×1350 PNG". Laid out in points at 3x.
    public static let cardPointSize = (width: 360.0, height: 450.0)
    public static let renderScale = 3.0
    /// Charts: 1080 × 1080 (spec §6 "Chart image").
    public static let chartPointSize = (width: 360.0, height: 360.0)

    // MARK: Calories

    /// Calories are off on cards unless switched on, and then shown as a
    /// range: no wrist device had energy-expenditure error under 20% and some
    /// reached 93% (Shcherbina et al., J Pers Med 2017), with large
    /// differences by activity (O'Driscoll et al., Br J Sports Med 2020).
    public static let calorieUncertainty = 0.20

    /// ±20%, to the nearest 10 kcal; nil for no energy.
    public static func calorieRange(_ kcal: Double?) -> ClosedRange<Int>? {
        guard let kcal, kcal.isFinite, kcal >= 1 else { return nil }
        let low = Int((kcal * (1 - calorieUncertainty) / 10).rounded()) * 10
        let high = Int((kcal * (1 + calorieUncertainty) / 10).rounded()) * 10
        return max(0, low)...max(low, high)
    }

    /// "≈ 360–540 kcal".
    public static func calorieText(_ kcal: Double?) -> String? {
        calorieRange(kcal).map { "≈ \($0.lowerBound.formatted())–\($0.upperBound.formatted()) kcal" }
    }

    // MARK: Cardio

    /// Splits shown on a card: at most this many, so the card stays legible.
    /// The app's choice (spec B1: "the best 3–5 splits").
    public static let maximumSplits = 5

    /// Whole splits only (a short last piece's pace is noise), all of them
    /// when they fit, else the fastest `maximumSplits`; in route order.
    public static func topSplits(_ splits: [CardioRoute.Split], maximum: Int = maximumSplits) -> [CardioRoute.Split] {
        let whole = splits.filter { !$0.isPartial && $0.speed > 0 }
        guard whole.count > maximum else { return whole }
        let fastest = whole.sorted { $0.speed > $1.speed }.prefix(maximum).map(\.index)
        return whole.filter { fastest.contains($0.index) }
    }

    /// Share of the measured zone time in each zone (sums to 1), or nil with none.
    public static func zoneFractions(_ minutes: [Double]) -> [Double]? {
        let clean = minutes.map { $0.isFinite ? max(0, $0) : 0 }
        let total = clean.reduce(0, +)
        guard total > 0 else { return nil }
        return clean.map { $0 / total }
    }

    /// The distance a card shows: rounded to 0.1 km/mi when the route was
    /// trimmed (spec rule 4), else to 0.01 as on screen.
    public static func distanceText(meters: Double, miles: Bool, trimmed: Bool) -> String {
        trimmed ? RoutePrivacy.roundedDistanceText(meters: meters, miles: miles)
            : CardioSummary.distanceText(meters: meters, miles: miles)
    }

    /// Average pace or speed from the distance the card shows, so pace × time
    /// can't be used to work back to the exact distance on a trimmed route.
    public static func shownDistanceMeters(_ meters: Double, miles: Bool, trimmed: Bool) -> Double {
        guard trimmed else { return meters }
        let unit = miles ? CardioSummary.metersPerMile : 1000
        return RoutePrivacy.roundedDistance(meters: meters, unitMeters: unit) * unit
    }

    // MARK: Lifting

    /// Exercises listed on the lifting card (the app's choice, for legibility).
    public static let maximumExercises = 5

    /// The `maximum` exercises with the most volume (for bodyweight work,
    /// reps), kept in session order; exercises with a record always make it.
    public static func topExercises(_ results: [WorkoutSummary.ExerciseResult], withRecords: Set<Int> = [],
                                    maximum: Int = maximumExercises) -> [WorkoutSummary.ExerciseResult] {
        guard results.count > maximum else { return results }
        let ranked = results.sorted { a, b in
            let aRecord = withRecords.contains(a.index), bRecord = withRecords.contains(b.index)
            if aRecord != bRecord { return aRecord }
            if a.volumeKg != b.volumeKg { return a.volumeKg > b.volumeKg }
            return a.reps > b.reps
        }
        let chosen = Set(ranked.prefix(maximum).map(\.index))
        return results.filter { chosen.contains($0.index) }
    }

    /// Hard sets this session gave each muscle, as the summary counts them
    /// (`WorkoutSummary.MuscleLine.sessionSets`), shaded in three steps.
    public enum MuscleShade: Sendable, Equatable {
        case none, some, worked
    }

    /// Two hard sets or more is "worked"; under that a muscle only helped.
    /// The app's choice for a picture of one session; the weekly 10–20
    /// sets evidence is per week (Schoenfeld et al., J Sports Sci 2017).
    public static let workedSets = 2.0

    public static func shade(sets: Double) -> MuscleShade {
        guard sets.isFinite, sets > 0 else { return .none }
        return sets >= workedSets ? .worked : .some
    }
}

// MARK: - Weekly summary

/// Last week on one card (spec B4): training days, cardio, active minutes
/// against the WHO band, strength days against the guideline, and, when
/// switched on, sleep regularity.
public nonisolated struct WeeklyShareSummary: Sendable, Equatable {
    public var weekStart: Date
    /// Days with a gym session or a strength workout (`WeekRecord.done`).
    public var trainingDays: Int
    public var cardioSessions: Int
    public var cardioMinutes: Int
    /// From heart rate over the week (`HealthFloors.Week`); nil when unknown.
    public var moderateMinutes: Int?
    public var vigorousMinutes: Int?
    public var strengthDays: Int?
    /// Sleep Regularity Index, 0-100.
    public var sleepRegularity: Int?

    public init(weekStart: Date, trainingDays: Int, cardioSessions: Int, cardioMinutes: Int, moderateMinutes: Int? = nil,
                vigorousMinutes: Int? = nil, strengthDays: Int? = nil, sleepRegularity: Int? = nil) {
        self.weekStart = weekStart
        self.trainingDays = trainingDays
        self.cardioSessions = cardioSessions
        self.cardioMinutes = cardioMinutes
        self.moderateMinutes = moderateMinutes
        self.vigorousMinutes = vigorousMinutes
        self.strengthDays = strengthDays
        self.sleepRegularity = sleepRegularity
    }

    public enum Band: Sendable, Equatable {
        case below, within, above
    }

    /// Moderate-equivalent minutes (vigorous count double, WHO 2020 via
    /// `IntensityMinutes`); nil without heart rate for the week.
    public var activeMinutes: Int? {
        guard let moderateMinutes, let vigorousMinutes else { return nil }
        return IntensityMinutes.Result(moderate: moderateMinutes, vigorous: vigorousMinutes).total
    }

    /// Against WHO's 150–300 minutes (Bull et al., Br J Sports Med 2020;
    /// `WeeklyActivityBand`). Above 300 is not "too much": risk kept falling
    /// to 300–600 (Lee et al., Circulation 2022), so the card says so.
    public var activeBand: Band? {
        guard let total = activeMinutes else { return nil }
        if total < WeeklyActivityBand.floorMinutes { return .below }
        return total <= WeeklyActivityBand.bestMinutes ? .within : .above
    }

    /// Strength days against WHO's 2 a week (`StrengthDays.weeklyTarget`).
    public var strengthMet: Bool? {
        strengthDays.map { $0 >= StrengthDays.weeklyTarget }
    }

    /// Fraction of the WHO bar to fill (0...1 over 0...`WeeklyActivityBand.scaleMinutes`).
    public var activeFraction: Double? {
        activeMinutes.map { min(1, Double($0) / Double(WeeklyActivityBand.scaleMinutes)) }
    }

    public var activeLine: String? {
        guard let total = activeMinutes, let band = activeBand else { return nil }
        let range = "\(WeeklyActivityBand.floorMinutes)–\(WeeklyActivityBand.bestMinutes)"
        switch band {
        case .below: return "\(total) of \(WeeklyActivityBand.floorMinutes) min (WHO \(range))"
        case .within: return "\(total) min, inside WHO's \(range)"
        case .above: return "\(total) min, past WHO's \(range)"
        }
    }

    public var strengthLine: String? {
        guard let days = strengthDays else { return nil }
        return "\(days) of \(StrengthDays.weeklyTarget) strength days"
    }

    /// "SRI 82 · 87+ is where risk was lowest" (Windred et al., Sleep 2024;
    /// `SleepRegularity.benefitIndex`).
    public var sleepLine: String? {
        sleepRegularity.map { "Sleep regularity \($0) of 100 · \(SleepRegularity.benefitIndex)+ went with the lowest risk" }
    }
}
