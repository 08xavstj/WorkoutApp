import Foundation

/// VO₂ max estimates that need no exercise test, for people whose Apple Watch
/// gives no reading (it only measures VO₂ max on outdoor walks, runs and
/// hikes, so lifting never produces one). Both are rough: shown next to the
/// watch value, never instead of a measured one, and labelled as estimates.
///
/// - **Heart-rate ratio** (Uth, Sørensen, Overgaard & Pedersen, Eur J Appl
///   Physiol 2004;91:111-115): VO₂ max ≈ 15.3 × HRmax / HRrest. Validated in
///   well-trained men aged 21-51; in mixed groups the error is large, about
///   ±10-15% (later validation studies), and worse when max HR is age-predicted
///   rather than measured. The paper itself says other groups "await direct
///   validation". Two guards follow from that (`heartRateRatio(…age:sex:)`):
///   the result is capped at the FRIEND 95th percentile for the age and sex
///   (a resting rate of 30 otherwise reads 95 mL/kg/min), and for women the
///   factor is 14.5 (Uth, Int J Sports Med 2005, 27 trained women; read from
///   the abstract, full text not checked) at half weight in the combined
///   value, because one small study of trained women is thin support for an
///   untrained 52 kg woman reading 46.
/// - **Activity model** (Jackson, Blair, Mahar, Wier, Ross & Stuteville, Med
///   Sci Sports Exerc 1990;22:863-870, the NASA/Johnson Space Center
///   non-exercise model): from age, sex, BMI (or body fat) and a 0-7
///   physical-activity rating (PA-R) for the last month. The PA-R scale names
///   weight lifting as "modest" activity (levels 2-3) and only vigorous
///   aerobic-type exercise reaches 4-7, so lifting counts here, in line with
///   the evidence that lifting raises VO₂ max only a little (Ozaki et al., Eur
///   Rev Aging Phys Act 2013). Standard error about 5 mL/kg/min.
public enum VO2MaxEstimate {
    public enum Method: String, Sendable, Equatable {
        case heartRateRatio
        case activity
        /// The mean of the two (`combined`).
        case combined
    }

    public struct Result: Sendable, Equatable {
        public var method: Method
        /// mL/kg/min.
        public var value: Double
        /// A typical error either side, mL/kg/min.
        public var error: Double
        /// Its share in `combined` (1 = a full vote). Under 1 for the
        /// heart-rate ratio in women (`womenHeartRateRatioWeight`).
        public var weight: Double = 1
        /// True when the formula's raw value was above the plausible ceiling
        /// and `value` is the ceiling instead (`heartRateRatioCeiling`).
        public var isCapped: Bool = false
        public var range: ClosedRange<Double> { max(10, value - error)...(value + error) }
    }

    // MARK: Heart-rate ratio (Uth 2004)

    /// 15.3 × HRmax / HRrest (Uth 2004, well-trained men).
    public static let uthFactor = 15.3
    /// The factor found in 27 trained women: 14.5 against 15.3 in men (Uth,
    /// Int J Sports Med 2005;26:763-767; the figure is from the abstract, the
    /// full text and page numbers weren't checked).
    public static let uthFactorWomen = 14.5
    /// The heart-rate ratio's share in `combined` for women. The app's choice:
    /// the women's factor rests on one study of 27 trained women, and nobody
    /// has validated the method in untrained women (Uth 2004: other groups
    /// "await direct validation"), so it gets half a vote beside the activity
    /// model, whose equation has a sex term fitted on men and women together
    /// (Jackson 1990).
    public static let womenHeartRateRatioWeight = 0.5

    /// The highest value the heart-rate ratio may return: the 95th percentile
    /// for the age and sex in the FRIEND table (`VO2Norms`, Kaminsky 2015),
    /// the highest percentile it has. Without an age or sex, the table's
    /// highest 95th percentile (men in their 20s, 66.3). The formula has no
    /// ceiling of its own: 15.3 × 187 / 30 is 95 mL/kg/min, an elite
    /// endurance athlete's figure, from nothing but a low resting pulse. An
    /// estimate with ±15% error can't place anyone above the top of the
    /// table (app choice).
    public static func heartRateRatioCeiling(age: Int?, sex: BiologicalSex?) -> Double {
        if let age, let sex, let top = VO2Norms.cutPoints(age: age, sex: sex).last { return top }
        let tops = (sex.map { [$0] } ?? BiologicalSex.allCases).compactMap { VO2Norms.cutPoints(age: 25, sex: $0).last }
        return tops.max() ?? 66.3
    }

    /// - Parameters:
    ///   - restingHeartRate: awake resting heart rate (Apple Health's resting
    ///     value, not sleeping heart rate, which runs lower and would inflate it).
    ///   - measuredMax: true when the max came from a test or a hard effort,
    ///     false when it's age-predicted (wider error).
    /// The men's factor, capped at the table's highest 95th percentile. Prefer
    /// `heartRateRatio(maxHeartRate:restingHeartRate:measuredMax:age:sex:)`,
    /// which uses the person's own ceiling and the women's factor.
    public static func heartRateRatio(maxHeartRate: Double, restingHeartRate: Double, measuredMax: Bool) -> Result? {
        heartRateRatio(maxHeartRate: maxHeartRate, restingHeartRate: restingHeartRate, measuredMax: measuredMax,
                       age: nil, sex: nil)
    }

    /// The heart-rate ratio for a person: 15.3 × HRmax / HRrest for men (Uth
    /// 2004), 14.5 for women at half weight (Uth 2005; see
    /// `womenHeartRateRatioWeight`), never above the FRIEND 95th percentile
    /// for the age and sex (`heartRateRatioCeiling`; `isCapped` says when).
    public static func heartRateRatio(maxHeartRate: Double, restingHeartRate: Double, measuredMax: Bool,
                                      age: Int?, sex: BiologicalSex?) -> Result? {
        guard (30...110).contains(restingHeartRate), maxHeartRate > restingHeartRate + 40, maxHeartRate <= 230 else { return nil }
        let raw = (sex == .female ? uthFactorWomen : uthFactor) * maxHeartRate / restingHeartRate
        let ceiling = heartRateRatioCeiling(age: age, sex: sex)
        let value = min(raw, ceiling)
        // ±12% with a measured max, ±15% with a predicted one: an app reading
        // of the validation studies' spread, not a published interval.
        let error = value * (measuredMax ? 0.12 : 0.15)
        return Result(method: .heartRateRatio, value: value, error: error,
                      weight: sex == .female ? womenHeartRateRatioWeight : 1, isCapped: raw > ceiling)
    }

    // MARK: Activity model (Jackson 1990)

    /// The 0-7 PA-R level from a typical week (Jackson 1990's scale).
    /// - Parameters:
    ///   - vigorousMinutes: minutes a week at vigorous heart rate, from any
    ///     workout, lifting included ("heavy physical exercise" on the scale).
    ///   - moderateMinutes: minutes a week at moderate heart rate.
    ///   - liftingMinutes: minutes a week of logged lifting ("weight lifting"
    ///     is named as modest activity on the scale).
    public static func activityRating(vigorousMinutes: Double, moderateMinutes: Double, liftingMinutes: Double) -> Int {
        // Levels 4-7: regular heavy exercise, < 30, 30-60, 60-180, > 180 min a week.
        switch vigorousMinutes {
        case 180...: return 7
        case 60..<180: return 6
        case 30..<60: return 5
        // At least 10 minutes a week to count as "regular" (app choice).
        case 10..<30: return 4
        default: break
        }
        // Levels 2-3: modest activity (including weight lifting), 10-60 or > 60 min a week.
        let modest = moderateMinutes + liftingMinutes
        if modest > 60 { return 3 }
        if modest >= 10 { return 2 }
        // 1: occasional light activity; 0 would mean avoiding exertion entirely,
        // which a person with logged data rarely does.
        return 1
    }

    /// Days the scale asks about: "the last month" (Jackson 1990).
    public static let activityRatingDays = 28

    /// The 0-7 PA-R level from the last month, the period Jackson's scale
    /// asks about, with lifting kept where the scale puts it.
    ///
    /// The older entry point reads one week of heart rate and lets vigorous
    /// heart rate inside a lifting session count as "heavy physical exercise",
    /// so one hard session moved the level, and the estimate, by 3 mL/kg/min
    /// (47.5 ↔ 50.4). On the scale, levels 4-7 are running, swimming, cycling,
    /// rowing or comparable vigorous aerobic exercise, and weight lifting is
    /// named under "modest" activity at levels 2-3 (Jackson 1990's PA-R; the
    /// wording here is from the file's notes and memory, not re-read).
    /// - Parameters:
    ///   - aerobicVigorousMinutes: minutes at vigorous heart rate over the
    ///     period, **outside** lifting sessions (runs, rides, matches).
    ///   - aerobicModerateMinutes: minutes at moderate heart rate over the
    ///     period, outside lifting sessions.
    ///   - liftingMinutes: minutes of logged lifting over the period; they
    ///     count toward levels 2-3 only.
    ///   - days: the length of the period (28 by default); the totals are
    ///     turned into weekly averages.
    public static func activityRating(aerobicVigorousMinutes: Double, aerobicModerateMinutes: Double,
                                      liftingMinutes: Double, overDays days: Int = activityRatingDays) -> Int {
        let weeks = Double(max(1, days)) / 7
        return activityRating(vigorousMinutes: max(0, aerobicVigorousMinutes) / weeks,
                              moderateMinutes: max(0, aerobicModerateMinutes) / weeks,
                              liftingMinutes: max(0, liftingMinutes) / weeks)
    }

    /// Jackson 1990 non-exercise model. Uses the body-fat version when body fat
    /// is known (SE 5.04), else the BMI version (SE 5.35).
    public static func activity(rating: Int, age: Int, sex: BiologicalSex, bmi: Double?, bodyFatPercent: Double?) -> Result? {
        guard (18...90).contains(age) else { return nil }
        let level = Double(min(7, max(0, rating)))
        let male: Double = sex == .male ? 1 : 0
        let value: Double
        let error: Double
        if let fat = bodyFatPercent, (3...60).contains(fat) {
            value = 50.513 + 1.589 * level - 0.289 * Double(age) - 0.552 * fat + 5.863 * male
            error = 5.04
        } else if let bmi, (15...50).contains(bmi) {
            value = 56.363 + 1.921 * level - 0.381 * Double(age) - 0.754 * bmi + 10.987 * male
            error = 5.35
        } else {
            return nil
        }
        guard value > 10 else { return nil }
        return Result(method: .activity, value: value, error: error)
    }

    // MARK: Combined

    /// The mean of the estimates there are, with their mean error, each
    /// weighted by its `weight` (1 except the heart-rate ratio in women). The
    /// two methods err in different ways (one on heart rate, one on activity
    /// and body size), so the mean is the steadier single number; its error is
    /// left at the methods' typical error rather than narrowed, because
    /// their errors aren't known to be independent (app choice).
    public static func combined(_ results: [Result]) -> Result? {
        guard !results.isEmpty else { return nil }
        if results.count == 1, let only = results.first { return only }
        let total = results.map { max(0, $0.weight) }.reduce(0, +)
        guard total > 0 else { return nil }
        return Result(method: .combined,
                      value: results.map { $0.value * max(0, $0.weight) }.reduce(0, +) / total,
                      error: results.map { $0.error * max(0, $0.weight) }.reduce(0, +) / total,
                      isCapped: results.contains(where: \.isCapped))
    }

    /// Plain words for a PA-R level, for the UI.
    public static func ratingText(_ rating: Int) -> String {
        switch rating {
        case 7: "over 3 h a week of hard exercise"
        case 6: "1-3 h a week of hard exercise"
        case 5: "30-60 min a week of hard exercise"
        case 4: "under 30 min a week of hard exercise"
        case 3: "over 1 h a week of moderate activity or lifting"
        case 2: "10-60 min a week of moderate activity or lifting"
        default: "light activity only"
        }
    }
}

/// Which VO₂ max the app scores with: the level (FRIEND percentile), the
/// Health and Fitness pages and the coach.
///
/// Apple Watch's VO₂ max ran low against lab tests: 6.1 mL/kg/min under on
/// average (95% CI 3.8-8.4), 13% mean absolute error, in 30 adults (Lambe et
/// al., PLOS ONE 2025;20:e0323741), and it only measures on outdoor walks,
/// runs and hikes. The app's no-test estimates (`VO2MaxEstimate`) are rough
/// too (about ±5 mL/kg/min), so neither is a lab number: the setting is the
/// user's choice, and the UI always says which one is in use.
public enum VO2Source: String, Sendable, Codable, CaseIterable, Identifiable {
    /// The app's estimate (heart rate and activity), else the watch.
    case estimate
    /// The watch's latest reading, else the estimate.
    case watch

    public var id: String { rawValue }

    /// Settings default (the user's request: the watch reads them low).
    public static let standard: VO2Source = .estimate

    public var title: String {
        switch self {
        case .estimate: "Tensile estimate"
        case .watch: "Apple Watch"
        }
    }

    /// The value to score with and whether it is the estimate; the other
    /// source stands in when the preferred one has nothing.
    public static func pick(watch: Double?, estimate: Double?, prefer: VO2Source) -> (value: Double, isEstimate: Bool)? {
        switch prefer {
        case .estimate:
            if let estimate { return (estimate, true) }
            return watch.map { ($0, false) }
        case .watch:
            if let watch { return (watch, false) }
            return estimate.map { ($0, true) }
        }
    }
}
