import Foundation

/// Daily recovery 0-100: last night's HRV and resting heart rate compared with
/// your own recent baseline, plus how well you slept.
///
/// Each input becomes a z-score (how many "normal days" away from your average).
/// HRV above baseline is good; resting heart rate above baseline is bad.
public struct RecoveryCalculator: Sendable {
    public var baselineDays: Int = 30
    public var minimumBaselineDays: Int = 4
    public var hrvWeight: Double = 0.55
    public var restingHeartRateWeight: Double = 0.25
    public var sleepWeight: Double = 0.20

    public init() {}

    public enum Status: String, Sendable {
        case low, moderate, high
    }

    public struct Result: Sendable, Equatable {
        public var score: Int
        public var status: Status
        /// Percent difference from baseline, e.g. +8 means 8% above normal.
        public var hrvChangePercent: Double?
        public var restingHeartRateChange: Double?
        public var baselineHRV: Double?
        public var baselineRestingHeartRate: Double?
        /// False until there are enough nights to build a baseline.
        public var isCalibrated: Bool
    }

    public struct Baseline: Sendable, Equatable {
        public var meanLogHRV: Double?
        public var sdLogHRV: Double?
        public var meanRHR: Double?
        public var sdRHR: Double?
        public var nights: Int
    }

    public func baseline(from history: [DailyVitals]) -> Baseline {
        let recent = history.sorted { $0.date > $1.date }.prefix(baselineDays)
        let logHRV = recent.compactMap(\.hrvMilliseconds).filter { $0 > 0 }.map { log($0) }
        let rhr = recent.compactMap(\.restingHeartRate).filter { $0 > 0 }
        let (meanH, sdH) = Self.meanAndSD(logHRV)
        let (meanR, sdR) = Self.meanAndSD(rhr)
        return Baseline(meanLogHRV: meanH, sdLogHRV: sdH, meanRHR: meanR, sdRHR: sdR, nights: max(logHRV.count, rhr.count))
    }

    /// - Parameters:
    ///   - today: last night's vitals.
    ///   - history: previous nights, not including `today`.
    ///   - sleepScore: 0-100 from `SleepCalculator`, if available.
    public func score(today: DailyVitals, history: [DailyVitals], sleepScore: Int?) -> Result? {
        let base = baseline(from: history)
        let calibrated = base.nights >= minimumBaselineDays

        var combined = 0.0
        var weightUsed = 0.0
        var hrvChange: Double?
        var rhrChange: Double?

        if let hrv = today.hrvMilliseconds, hrv > 0, let mean = base.meanLogHRV, let sd = base.sdLogHRV, calibrated {
            // Floor the SD so a very steady baseline doesn't make small changes look huge.
            let z = (log(hrv) - mean) / max(sd, 0.10)
            combined += hrvWeight * Self.clampZ(z)
            weightUsed += hrvWeight
            hrvChange = (hrv / exp(mean) - 1) * 100
        }
        if let rhr = today.restingHeartRate, rhr > 0, let mean = base.meanRHR, let sd = base.sdRHR, calibrated {
            let z = (rhr - mean) / max(sd, 1.5)
            combined -= restingHeartRateWeight * Self.clampZ(z)
            weightUsed += restingHeartRateWeight
            rhrChange = rhr - mean
        }
        if let sleepScore {
            let z = (Double(sleepScore) - 75) / 12
            combined += sleepWeight * Self.clampZ(z)
            weightUsed += sleepWeight
        }
        guard weightUsed > 0 else { return nil }

        // Rescale so missing inputs don't drag the score toward 50.
        let normalized = combined / weightUsed
        let logistic = 1 / (1 + exp(-(1.5 * normalized + 0.3)))
        let score = min(99, max(1, Int((logistic * 100).rounded())))

        return Result(
            score: score,
            status: Self.status(for: score),
            hrvChangePercent: hrvChange,
            restingHeartRateChange: rhrChange,
            baselineHRV: base.meanLogHRV.map { exp($0) },
            baselineRestingHeartRate: base.meanRHR,
            isCalibrated: calibrated
        )
    }

    public static func status(for score: Int) -> Status {
        switch score {
        case ..<34: .low
        case 34..<67: .moderate
        default: .high
        }
    }

    static func clampZ(_ z: Double) -> Double { min(3, max(-3, z)) }

    static func meanAndSD(_ values: [Double]) -> (Double?, Double?) {
        guard !values.isEmpty else { return (nil, nil) }
        let mean = values.reduce(0, +) / Double(values.count)
        guard values.count > 1 else { return (mean, nil) }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)
        return (mean, sqrt(variance))
    }
}
