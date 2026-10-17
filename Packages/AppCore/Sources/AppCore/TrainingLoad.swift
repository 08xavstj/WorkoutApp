import Foundation

/// Training load: how much you've done this week compared with what your body
/// is used to (acute 7-day vs. chronic 28-day load). Shown on the strain scale.
public struct TrainingLoadCalculator: Sendable {
    public var calculator = StrainCalculator()
    /// The "sweet spot" of the acute:chronic ratio.
    public var optimalRatio: ClosedRange<Double> = 0.8...1.3

    public init() {}

    public enum Status: String, Sendable {
        case calibrating, low, optimal, high
    }

    public struct Result: Sendable, Equatable {
        /// 7-day average daily load, on the 0-21 strain scale.
        public var value: Double
        public var optimal: ClosedRange<Double>
        public var status: Status
        public var acuteChronicRatio: Double?
    }

    /// - Parameter dailyLoads: one value per day, oldest first, ideally 28 days.
    public func evaluate(dailyLoads: [Double]) -> Result {
        let recent = dailyLoads.suffix(7)
        let acute = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
        let chronic = dailyLoads.isEmpty ? 0 : dailyLoads.reduce(0, +) / Double(dailyLoads.count)
        let value = calculator.strain(forLoad: acute)
        guard dailyLoads.count >= 14, chronic > 0 else {
            return Result(value: value, optimal: 0...0, status: .calibrating, acuteChronicRatio: nil)
        }
        let low = calculator.strain(forLoad: chronic * optimalRatio.lowerBound)
        let high = calculator.strain(forLoad: chronic * optimalRatio.upperBound)
        let ratio = acute / chronic
        let status: Status = ratio < optimalRatio.lowerBound ? .low : (ratio > optimalRatio.upperBound ? .high : .optimal)
        return Result(value: value, optimal: low...high, status: status, acuteChronicRatio: ratio)
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

    /// Rough VO2 max bands for adults, adjusted by age.
    public static func vo2MaxLabel(_ value: Double, age: Int, sex: BiologicalSex) -> String {
        let ageDrop = Double(max(0, age - 30)) * 0.3
        let base: [Double] = sex == .male ? [37, 42, 47, 52] : [31, 35, 40, 45]
        let cut = base.map { $0 - ageDrop }
        switch value {
        case ..<cut[0]: return "Poor"
        case ..<cut[1]: return "Fair"
        case ..<cut[2]: return "Good"
        case ..<cut[3]: return "Excellent"
        default: return "Superior"
        }
    }
}
