import Foundation

/// Daily recovery 0-100: last night's HRV and resting heart rate compared with
/// your own recent baseline, plus how well you slept.
///
/// Each input becomes a z-score (how many "normal days" away from your average).
/// HRV above baseline is good; resting heart rate above baseline is bad.
///
/// HRV counts twice: the 7-day rolling average of ln HRV against your normal
/// range (baseline mean ± 0.5 SD, the "smallest worthwhile change"), which is
/// the method validated for guiding training (Plews et al. 2012-2013;
/// Javaloyes et al., IJSPP 2019), and last night's value, so a bad night
/// still shows.
public struct RecoveryCalculator: Sendable {
    public var baselineDays: Int = 30
    public var minimumBaselineDays: Int = 4
    public var hrvTrendWeight: Double = 0.35
    public var hrvWeight: Double = 0.20
    public var restingHeartRateWeight: Double = 0.25
    public var sleepWeight: Double = 0.20

    public init() {}

    public enum Status: String, Sendable {
        case low, moderate, high
    }

    /// The 7-day HRV average and where it sits against your normal range.
    public struct HRVTrend: Sendable, Equatable {
        public enum Status: String, Sendable { case below, within, above }
        public var average: Double
        public var normalRange: ClosedRange<Double>
        public var status: Status
        /// Day-to-day swing over the last 7 nights (coefficient of variation of ln HRV, %).
        public var variation: Double?
        public var nights: Int
    }

    public struct Result: Sendable, Equatable {
        public var score: Int
        public var hrvTrend: HRVTrend?
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
        var trend: HRVTrend?

        // 7-day rolling ln HRV (tonight + up to 6 previous nights).
        let lastWeek = ([today] + history.sorted { $0.date > $1.date }.prefix(6))
            .compactMap(\.hrvMilliseconds).filter { $0 > 0 }.map { log($0) }
        if lastWeek.count >= 3, let mean = base.meanLogHRV, let sd = base.sdLogHRV, calibrated {
            let rolling = lastWeek.reduce(0, +) / Double(lastWeek.count)
            let swc = 0.5 * max(sd, 0.05)
            let status: HRVTrend.Status = rolling < mean - swc ? .below : (rolling > mean + swc ? .above : .within)
            let (_, weekSD) = Self.meanAndSD(lastWeek)
            trend = HRVTrend(
                average: exp(rolling),
                normalRange: exp(mean - swc)...exp(mean + swc),
                status: status,
                variation: weekSD.map { $0 / rolling * 100 },
                nights: lastWeek.count
            )
            let z = (rolling - mean) / max(sd, 0.10)
            combined += hrvTrendWeight * Self.clampZ(z)
            weightUsed += hrvTrendWeight
        }

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
            hrvTrend: trend,
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
