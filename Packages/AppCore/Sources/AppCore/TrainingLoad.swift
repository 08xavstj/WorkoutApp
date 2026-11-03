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

    /// - Parameter dailyLoads: one value per day, oldest first, ideally 28 days.
    ///   The last 7 are "this week"; the ones before are "usual" (at least 7).
    public func evaluate(dailyLoads: [Double]) -> Result {
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
    /// (Kaminsky et al., Mayo Clin Proc 2015): 20s, 30s, ... 70s.
    static let friendMedians: [BiologicalSex: [Double]] = [
        .male: [48.0, 42.4, 37.8, 32.6, 28.2, 24.4],
        .female: [37.6, 30.2, 26.7, 23.4, 20.0, 18.3],
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

    /// VO₂ max compared with people your age and sex: around the FRIEND
    /// median is "Good". The band widths (80/95/110/125% of the median) are
    /// the app's choice. Watch VO₂ max is an estimate.
    public static func vo2MaxLabel(_ value: Double, age: Int, sex: BiologicalSex) -> String {
        let median = medianVO2Max(age: age, sex: sex)
        let cut = [0.8, 0.95, 1.1, 1.25].map { $0 * median }
        switch value {
        case ..<cut[0]: return "Poor"
        case ..<cut[1]: return "Fair"
        case ..<cut[2]: return "Good"
        case ..<cut[3]: return "Excellent"
        default: return "Superior"
        }
    }
}
