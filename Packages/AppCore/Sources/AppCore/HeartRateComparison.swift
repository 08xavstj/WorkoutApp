import Foundation

/// Compares two heart-rate recordings of the same workout (e.g. AirPods vs. Garmin).
public enum HeartRateComparison {
    public struct Summary: Sendable, Equatable {
        public var average: Double
        public var maximum: Double
        public var minimum: Double
        public var samples: Int
    }

    public struct Result: Sendable, Equatable {
        /// Minutes where both sources had a reading.
        public var overlappingMinutes: Int
        /// Average absolute difference per minute, bpm.
        public var meanAbsoluteDifference: Double
        /// Average of (a - b), bpm. Positive = source A reads higher.
        public var bias: Double
        /// Pearson correlation of the per-minute values (1 = they move together).
        public var correlation: Double?
    }

    public static func summary(_ samples: [HeartRateSample]) -> Summary? {
        let values = samples.map(\.bpm).filter { $0.isFinite && $0 > 0 }
        guard !values.isEmpty else { return nil }
        return Summary(
            average: values.reduce(0, +) / Double(values.count),
            maximum: values.max() ?? 0,
            minimum: values.min() ?? 0,
            samples: values.count
        )
    }

    /// Averages each source per minute, then compares the minutes both have.
    public static func compare(_ a: [HeartRateSample], _ b: [HeartRateSample]) -> Result? {
        let minutesA = perMinute(a)
        let minutesB = perMinute(b)
        let shared = Set(minutesA.keys).intersection(minutesB.keys).sorted()
        guard !shared.isEmpty else { return nil }
        let pairs = shared.map { (minutesA[$0]!, minutesB[$0]!) }
        let n = Double(pairs.count)
        let differences = pairs.map { $0.0 - $0.1 }
        let mad = differences.map(abs).reduce(0, +) / n
        let bias = differences.reduce(0, +) / n

        var correlation: Double?
        if pairs.count >= 3 {
            let meanA = pairs.map(\.0).reduce(0, +) / n
            let meanB = pairs.map(\.1).reduce(0, +) / n
            let covariance = pairs.map { ($0.0 - meanA) * ($0.1 - meanB) }.reduce(0, +)
            let varianceA = pairs.map { ($0.0 - meanA) * ($0.0 - meanA) }.reduce(0, +)
            let varianceB = pairs.map { ($0.1 - meanB) * ($0.1 - meanB) }.reduce(0, +)
            if varianceA > 0, varianceB > 0 {
                correlation = covariance / (varianceA * varianceB).squareRoot()
            }
        }
        return Result(overlappingMinutes: pairs.count, meanAbsoluteDifference: mad, bias: bias, correlation: correlation)
    }

    static func perMinute(_ samples: [HeartRateSample]) -> [Int: Double] {
        var sums: [Int: (Double, Int)] = [:]
        for sample in samples where sample.bpm.isFinite && sample.bpm > 0 {
            let minute = Int((sample.date.timeIntervalSince1970 / 60).rounded(.down))
            let current = sums[minute] ?? (0, 0)
            sums[minute] = (current.0 + sample.bpm, current.1 + 1)
        }
        return sums.mapValues { $0.0 / Double($0.1) }
    }
}
