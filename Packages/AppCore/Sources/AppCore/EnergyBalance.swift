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
///
/// Two things make this go wrong in real life, and both are handled:
/// - Days that weren't fully logged. Missing food makes intake look low, and
///   so maintenance too; under-recording is the main error in food logs
///   (Burrows et al., Nutrients 2019). Days well below your usual logged
///   intake are treated as partly logged and left out.
/// - Water weight from creatine. Starting creatine adds roughly 1 kg of
///   water in muscle over the first weeks: within about a week with a 20 g
///   loading phase, or about 4 weeks at 3-5 g a day, which fills muscle just
///   as fully (Hultman et al., J Appl Physiol 1996; Kreider et al., JISSN
///   2017). That gain isn't fat or muscle tissue, so it's taken out of the
///   weight trend.
public enum AdaptiveTDEE {
    public static let kcalPerKg = 7700.0
    /// Fully logged days needed in the window.
    public static let minimumLoggedDays = 14
    /// A day under this share of your usual (median) logged intake counts as partly logged.
    public static let partialDayFraction = 0.7
    /// Typical water gain from starting creatine, kg.
    public static let creatineWaterKg = 1.0

    public struct Result: Sendable, Equatable {
        /// Calories a day that would keep your weight steady.
        public var maintenance: Double
        public var averageIntake: Double
        /// kg per week (negative = losing), after any creatine adjustment.
        public var weeklyChangeKg: Double
        public var loggedDays: Int
        public var weighIns: Int
        /// Days with some food logged that were left out as partly logged.
        public var partialDaysSkipped: Int = 0
        /// Water weight from creatine taken out of the trend in this window, kg.
        public var creatineWaterRemovedKg: Double = 0
    }

    /// Why there's no estimate yet, for the app to explain.
    public struct Progress: Sendable, Equatable {
        public var fullyLoggedDays: Int
        public var partialDays: Int
        public var weighIns: Int
        public var daysNeeded: Int { max(0, minimumLoggedDays - fullyLoggedDays) }
    }

    /// A day under this share of estimated expenditure counts as partly logged
    /// (catches stretches where most days are partial, which the median can't).
    public static let partialOfExpenditure = 0.5

    /// Days with a meaningful amount logged, split into full and partial.
    static func split(_ intake: [DayValue], start: Date, expectedExpenditure: Double? = nil) -> (full: [DayValue], partial: Int) {
        let candidates = intake.filter { $0.date >= start && $0.value >= 800 }
        guard !candidates.isEmpty else { return ([], 0) }
        let sorted = candidates.map(\.value).sorted()
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
        let floor = max(partialDayFraction * median, (expectedExpenditure ?? 0) * partialOfExpenditure)
        let full = candidates.filter { $0.value >= floor }
        return (full, candidates.count - full.count)
    }

    /// Creatine water at `date`, kg: ramps up over 4 weeks (1 week if loading).
    static func creatineWater(at date: Date, start: Date, loading: Bool) -> Double {
        let days = date.timeIntervalSince(start) / 86_400
        guard days > 0 else { return 0 }
        let rampDays = loading ? 7.0 : 28.0
        return creatineWaterKg * min(1, days / rampDays)
    }

    public static func progress(intake: [DayValue], weights: [DayValue], now: Date = .now, window: Int = 28,
                                expectedExpenditure: Double? = nil) -> Progress {
        let start = now.addingTimeInterval(-Double(window) * 86_400)
        let (full, partial) = split(intake, start: start, expectedExpenditure: expectedExpenditure)
        return Progress(fullyLoggedDays: full.count, partialDays: partial, weighIns: weights.filter { $0.date >= start }.count)
    }

    /// - Parameters:
    ///   - intake: calories eaten per day.
    ///   - weights: weigh-ins in kg.
    ///   - window: days to look back.
    ///   - creatineStart: when the user started taking creatine, if they do.
    ///   - creatineLoading: whether they started with a 20 g/day loading phase.
    ///   - expectedExpenditure: the app's rough estimate of calories burned a day, used to spot partly logged days.
    public static func estimate(intake: [DayValue], weights: [DayValue], now: Date = .now, window: Int = 28,
                                creatineStart: Date? = nil, creatineLoading: Bool = false,
                                expectedExpenditure: Double? = nil) -> Result? {
        let start = now.addingTimeInterval(-Double(window) * 86_400)
        let (logged, partial) = split(intake, start: start, expectedExpenditure: expectedExpenditure)
        var recentWeights = weights.filter { $0.date >= start }
        var removed = 0.0
        if let creatineStart {
            let water = recentWeights.map { creatineWater(at: $0.date, start: creatineStart, loading: creatineLoading) }
            removed = (water.max() ?? 0) - (water.min() ?? 0)
            recentWeights = zip(recentWeights, water).map { DayValue(date: $0.date, value: $0.value - $1) }
        }
        guard logged.count >= minimumLoggedDays, let change = WeightTrend.weeklyChange(recentWeights) else { return nil }
        let average = logged.map(\.value).reduce(0, +) / Double(logged.count)
        let maintenance = average - change / 7 * kcalPerKg
        guard (1200...5500).contains(maintenance) else { return nil }
        return Result(maintenance: maintenance, averageIntake: average, weeklyChangeKg: change,
                      loggedDays: logged.count, weighIns: recentWeights.count,
                      partialDaysSkipped: partial, creatineWaterRemovedKg: removed)
    }
}
