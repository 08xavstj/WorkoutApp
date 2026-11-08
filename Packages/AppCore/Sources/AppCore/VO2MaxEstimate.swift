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
///   rather than measured.
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
    }

    public struct Result: Sendable, Equatable {
        public var method: Method
        /// mL/kg/min.
        public var value: Double
        /// A typical error either side, mL/kg/min.
        public var error: Double
        public var range: ClosedRange<Double> { max(10, value - error)...(value + error) }
    }

    // MARK: Heart-rate ratio (Uth 2004)

    /// 15.3 × HRmax / HRrest (Uth 2004).
    public static let uthFactor = 15.3

    /// - Parameters:
    ///   - restingHeartRate: awake resting heart rate (Apple Health's resting
    ///     value, not sleeping heart rate, which runs lower and would inflate it).
    ///   - measuredMax: true when the max came from a test or a hard effort,
    ///     false when it's age-predicted (wider error).
    public static func heartRateRatio(maxHeartRate: Double, restingHeartRate: Double, measuredMax: Bool) -> Result? {
        guard (30...110).contains(restingHeartRate), maxHeartRate > restingHeartRate + 40, maxHeartRate <= 230 else { return nil }
        let value = uthFactor * maxHeartRate / restingHeartRate
        // ±12% with a measured max, ±15% with a predicted one: an app reading
        // of the validation studies' spread, not a published interval.
        let error = value * (measuredMax ? 0.12 : 0.15)
        return Result(method: .heartRateRatio, value: value, error: error)
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
