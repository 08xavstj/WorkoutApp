import Foundation

/// Training load trend: this week's average daily load compared with your
/// usual (the 3 weeks before it), on the strain scale.
///
/// This is a description, not an injury predictor. The acute:chronic ratio's
/// link with injury hasn't held up (Impellizzeri et al., IJSPP 2020; "Time to
/// dismiss the ACWR", Sports Med 2021), so the app only flags big jumps, which
/// are worth easing into (Gabbett, Br J Sports Med 2016).
///
/// "Usual" leaves out the current week ("uncoupled"). When the week being
/// judged is also inside the 4-week average, the ratio is pulled towards 1 and
/// can never pass 4 (Lolli et al., Br J Sports Med 2019); without it, "50% more
/// than usual" means exactly that. Plain averages are used rather than
/// exponentially weighted ones: neither has been shown to be better (Williams
/// et al. 2017 vs Sampson et al. 2017, Br J Sports Med), and averages are
/// easier to explain.
public struct TrainingLoadCalculator: Sendable {
    public var calculator = StrainCalculator()
    /// "Your usual": 80-130% of the previous 3 weeks' average.
    public var usualRatio: ClosedRange<Double> = 0.8...1.3
    /// More than 50% above usual counts as a big jump.
    public var spikeRatio = 1.5
    /// Days in the "this week" window.
    public static let acuteDays = 7

    public init() {}

    public enum Status: String, Sendable {
        case calibrating, lighter, steady, building, spike
    }

    public struct Result: Sendable, Equatable {
        /// 7-day average daily load, on the 0-100 strain scale.
        public var value: Double
        /// Your usual range on the same scale.
        public var usual: ClosedRange<Double>
        public var status: Status
        /// This week vs the weeks before it, e.g. 1.2 = 20% more.
        public var ratio: Double?
    }

    /// - Parameters:
    ///   - dailyLoads: one value per day, oldest first, ideally 28 days.
    ///     The last 7 are "this week"; the ones before are "usual" (at least 7).
    ///   - knownDays: how many of the most recent days were actually tracked
    ///     (e.g. days since the first logged lift). Days before that are
    ///     unknown, not rest: counting them as zero makes a new user's second
    ///     and third weeks read as a huge jump. Nil = every day is known.
    public func evaluate(dailyLoads: [Double], knownDays: Int? = nil) -> Result {
        let dailyLoads = knownDays.map { Array(dailyLoads.suffix(max(0, $0))) } ?? dailyLoads
        let recent = dailyLoads.suffix(Self.acuteDays)
        let earlier = dailyLoads.dropLast(Self.acuteDays)
        let acute = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
        let chronic = earlier.isEmpty ? 0 : earlier.reduce(0, +) / Double(earlier.count)
        let value = calculator.strain(forLoad: acute)
        guard dailyLoads.count >= 2 * Self.acuteDays, chronic > 0 else {
            return Result(value: value, usual: 0...0, status: .calibrating, ratio: nil)
        }
        let low = calculator.strain(forLoad: chronic * usualRatio.lowerBound)
        let high = calculator.strain(forLoad: chronic * usualRatio.upperBound)
        let ratio = acute / chronic
        let status: Status
        switch ratio {
        case ..<usualRatio.lowerBound: status = .lighter
        case ...usualRatio.upperBound: status = .steady
        case ...spikeRatio: status = .building
        default: status = .spike
        }
        return Result(value: value, usual: low...high, status: status, ratio: ratio)
    }
}

/// Simple descriptors used by the Biology tab.
public enum Biomarkers {
    public enum Trend: String, Sendable { case increasing, decreasing, stable }

    /// Direction of a series using a least-squares slope, relative to its mean.
    public static func trend(_ values: [Double], threshold: Double = 0.01) -> Trend {
        guard values.count >= 3 else { return .stable }
        let n = Double(values.count)
        let xs = values.indices.map(Double.init)
        let meanX = xs.reduce(0, +) / n
        let meanY = values.reduce(0, +) / n
        let numerator = zip(xs, values).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let denominator = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard denominator > 0, meanY != 0 else { return .stable }
        // Total change over the window as a share of the mean.
        let change = numerator / denominator * (n - 1) / abs(meanY)
        if change > threshold { return .increasing }
        if change < -threshold { return .decreasing }
        return .stable
    }

    public static func restingHeartRateLabel(_ bpm: Double) -> String {
        switch bpm {
        case ..<55: "Excellent"
        case ..<65: "Good"
        case ..<75: "Average"
        default: "High"
        }
    }

    public static func bodyFatLabel(_ percent: Double, sex: BiologicalSex) -> String {
        let cutoffs: [Double] = sex == .male ? [6, 14, 18, 25] : [14, 21, 25, 32]
        switch percent {
        case ..<cutoffs[0]: return "Essential"
        case ..<cutoffs[1]: return "Athletic"
        case ..<cutoffs[2]: return "Fit"
        case ..<cutoffs[3]: return "Average"
        default: return "High"
        }
    }

    /// Median treadmill VO₂ max by age decade from the FRIEND registry
    /// (Kaminsky et al., Mayo Clin Proc 2015, Table 3): 20s, 30s, ... 70s.
    /// Read from `VO2Norms.friendTreadmill` (its 50th percentile column) so
    /// the medians, percentiles and fitness age share one table:
    /// men 48.0, 42.4, 37.8, 32.6, 28.2, 24.4; women 37.6, 30.2, 26.7, 23.4, 20.0, 18.3.
    static let friendMedians: [BiologicalSex: [Double]] = [
        .male: VO2Norms.column(3, sex: .male),
        .female: VO2Norms.column(3, sex: .female),
    ]

    /// Median VO₂ max for an age, interpolated between decade midpoints.
    public static func medianVO2Max(age: Int, sex: BiologicalSex) -> Double {
        let medians = friendMedians[sex] ?? friendMedians[.male]!
        let position = min(Double(medians.count - 1), max(0, (Double(age) - 25) / 10))
        let lower = Int(position.rounded(.down))
        let upper = min(medians.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return medians[lower] + (medians[upper] - medians[lower]) * fraction
    }

    /// "Fitness age": the age whose FRIEND median VO₂ max (`medianVO2Max`)
    /// matches yours, found by running the same median line backwards (the
    /// wearable fitness age of Nes et al., Med Sci Sports Exerc 2011, on the
    /// FRIEND reference so every VO₂ max screen uses one set of norms).
    /// Outside 25-75 the end decades' slopes are extended, and the result is
    /// clamped to 18-90. With `age`, a value at or above your own age's median
    /// never gives a fitness age above your age (the medians are flat under 25
    /// and over 75, where running the line backwards is ambiguous), and one
    /// below it never gives an age under yours.
    public static func fitnessAge(vo2Max: Double, age: Int? = nil, sex: BiologicalSex) -> Double {
        let medians = friendMedians[sex] ?? friendMedians[.male]!
        // Decade midpoints 25, 35, ... 75; medians fall with age.
        var found: Double
        if vo2Max >= medians[0] {
            let slope = (medians[0] - medians[1]) / 10
            found = 25 - (vo2Max - medians[0]) / slope
        } else if vo2Max <= medians[medians.count - 1] {
            let last = medians.count - 1
            let slope = (medians[last - 1] - medians[last]) / 10
            found = 25 + Double(last) * 10 + (medians[last] - vo2Max) / slope
        } else {
            found = 75
            for index in 0..<(medians.count - 1) where vo2Max <= medians[index] && vo2Max > medians[index + 1] {
                let fraction = (medians[index] - vo2Max) / (medians[index] - medians[index + 1])
                found = 25 + (Double(index) + fraction) * 10
            }
        }
        if let age {
            let own = medianVO2Max(age: age, sex: sex)
            found = vo2Max >= own ? min(found, Double(age)) : max(found, Double(age))
        }
        return min(90, max(18, found))
    }

    /// Body age's "about typical" floor, as a share of the median: from 95%
    /// to 100% of the median VO₂ max adds no years (`BodyAge`; app choice).
    /// It sits inside the FRIEND 25th-50th band ("Average") at every age.
    public static let goodVO2MaxFraction = 0.95

    /// VO₂ max compared with people your age and sex, named by the FRIEND
    /// percentile band it falls in (`VO2Norms.category`: Low, Below average,
    /// Average, Good, Excellent, Top 10%). Watch VO₂ max is an estimate.
    public static func vo2MaxLabel(_ value: Double, age: Int, sex: BiologicalSex) -> String {
        VO2Norms.category(vo2: value, age: age, sex: sex).name
    }
}
