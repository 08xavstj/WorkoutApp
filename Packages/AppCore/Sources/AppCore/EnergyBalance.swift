import Foundation

/// A dated measurement (weight, intake...).
public struct DayValue: Sendable, Equatable {
    public var date: Date
    public var value: Double
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Smoothed body-weight trend. Daily weight swings 1-2 kg with water, salt and
/// food, so the trend uses an exponentially weighted moving average (10% of
/// each new weigh-in per day, as in The Hacker's Diet), adjusted for gaps.
public enum WeightTrend {
    public static let dailySmoothing = 0.1

    /// Trend value at each weigh-in, oldest first.
    public static func smooth(_ weights: [DayValue]) -> [DayValue] {
        let sorted = weights.sorted { $0.date < $1.date }
        guard var trend = sorted.first?.value, var last = sorted.first?.date else { return [] }
        var result: [DayValue] = []
        for point in sorted {
            let days = max(1, point.date.timeIntervalSince(last) / 86_400)
            let alpha = 1 - pow(1 - dailySmoothing, days)
            if !result.isEmpty { trend += alpha * (point.value - trend) }
            result.append(DayValue(date: point.date, value: trend))
            last = point.date
        }
        return result
    }

    /// Change per week from a least-squares line through the weigh-ins (the
    /// line already averages out daily noise, and unlike the smoothed trend it
    /// doesn't lag), or nil with fewer than 4 weigh-ins spanning 10+ days.
    public static func weeklyChange(_ weights: [DayValue]) -> Double? {
        let trend = weights.sorted { $0.date < $1.date }
        guard trend.count >= 4, let first = trend.first?.date, let last = trend.last?.date,
              last.timeIntervalSince(first) >= 10 * 86_400 else { return nil }
        let xs = trend.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = trend.map(\.value)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let denominator = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard denominator > 0 else { return nil }
        return numerator / denominator * 7
    }
}

/// Your real maintenance calories from what you ate and how your weight
/// changed (energy balance). Wrist trackers miss energy burned by more than
/// 30% on average (Germini et al., JMIR 2022); intake and weight trend avoid
/// that. About 7,700 kcal per kg of weight change is the standard approximation
/// (Hall et al., Lancet 2011, notes it's best over weeks, not days).
public enum AdaptiveTDEE {
    public static let kcalPerKg = 7700.0

    public struct Result: Sendable, Equatable {
        /// Calories a day that would keep your weight steady.
        public var maintenance: Double
        public var averageIntake: Double
        /// kg per week (negative = losing).
        public var weeklyChangeKg: Double
        public var loggedDays: Int
        public var weighIns: Int
    }

    /// - Parameters:
    ///   - intake: calories eaten per day (days with under 800 kcal are treated as not fully logged).
    ///   - weights: weigh-ins in kg.
    ///   - window: days to look back.
    public static func estimate(intake: [DayValue], weights: [DayValue], now: Date = .now, window: Int = 28) -> Result? {
        let start = now.addingTimeInterval(-Double(window) * 86_400)
        let logged = intake.filter { $0.date >= start && $0.value >= 800 }
        let recentWeights = weights.filter { $0.date >= start }
        guard logged.count >= 14, let change = WeightTrend.weeklyChange(recentWeights) else { return nil }
        let average = logged.map(\.value).reduce(0, +) / Double(logged.count)
        let maintenance = average - change / 7 * kcalPerKg
        guard (1200...5500).contains(maintenance) else { return nil }
        return Result(maintenance: maintenance, averageIntake: average, weeklyChangeKg: change,
                      loggedDays: logged.count, weighIns: recentWeights.count)
    }
}
