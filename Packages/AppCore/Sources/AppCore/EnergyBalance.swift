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

    /// Fewest weigh-ins, and the shortest span in days, for the trend shown
    /// on the weight chart (app choice; a direction, not a measurement).
    public static let minimumWeighIns = 4
    public static let minimumSpanDays = 10.0

    /// Change per week from a least-squares line through the weigh-ins (the
    /// line already averages out daily noise, and unlike the smoothed trend it
    /// doesn't lag), or nil with fewer than 4 weigh-ins spanning 10+ days.
    public static func weeklyChange(_ weights: [DayValue]) -> Double? {
        weeklyChange(weights, minimumWeighIns: minimumWeighIns, minimumSpanDays: minimumSpanDays)
    }

    /// The same line with a stricter data requirement (`AdaptiveTDEE` asks for
    /// 8 weigh-ins over 14 days before it turns the slope into calories).
    public static func weeklyChange(_ weights: [DayValue], minimumWeighIns: Int, minimumSpanDays: Double) -> Double? {
        fit(weights, minimumWeighIns: minimumWeighIns, minimumSpanDays: minimumSpanDays)?.weeklyChange
    }

    /// The line's slope per week and its standard error per week (from the
    /// scatter of the weigh-ins around the line, n − 2 degrees of freedom;
    /// nil with fewer than 3 weigh-ins).
    static func fit(_ weights: [DayValue], minimumWeighIns: Int, minimumSpanDays: Double)
        -> (weeklyChange: Double, standardError: Double?)? {
        let trend = weights.sorted { $0.date < $1.date }
        guard trend.count >= max(2, minimumWeighIns), let first = trend.first?.date, let last = trend.last?.date,
              last.timeIntervalSince(first) >= minimumSpanDays * 86_400 else { return nil }
        let xs = trend.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = trend.map(\.value)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let denominator = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard denominator > 0 else { return nil }
        let slope = numerator / denominator
        var standardError: Double?
        if trend.count >= 3 {
            let intercept = meanY - slope * meanX
            let residuals = zip(xs, ys).map { x, y in (y - intercept - slope * x) * (y - intercept - slope * x) }.reduce(0, +)
            standardError = (residuals / Double(trend.count - 2) / denominator).squareRoot() * 7
        }
        return (slope * 7, standardError)
    }
}

/// Your real maintenance calories from what you ate and how your weight
/// changed (energy balance). Wrist trackers miss energy burned by more than
/// 30% on average (Germini et al., JMIR 2022); intake and weight trend avoid
/// that. About 7,700 kcal per kg of weight change is the standard approximation
/// (Hall et al., Lancet 2011, notes it's best over weeks, not days).
///
/// How much data it takes. Body weight answers a change in intake slowly
/// (half of the eventual change takes about a year; Hall et al., Lancet
/// 2011;378:826-837), while the scale moves 1-2 kg from day to day with
/// water, salt and food. A slope through a handful of weigh-ins is mostly
/// that noise, and each 0.1 kg a week of slope error is 110 kcal a day: from 4
/// weigh-ins over 10 days the same steady 80 kg read 2,329 or 3,497 kcal
/// (SD about ±600 kcal in a simulation). So an estimate needs at least
/// `minimumWeighIns` (8) spanning `minimumWeighInSpanDays` (14); both numbers
/// are the app's choice, Hall 2011 gives only "weeks". Even then it is
/// rough (about ±300 kcal at half a kilo of daily scatter), so the result
/// carries its own `uncertaintyKcal` for the UI to show; more weigh-ins
/// across the 28-day window narrow it.
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
    /// Weigh-ins needed in the window, and the days they must span (app
    /// choice; see the type's notes. Were 4 over 10 days).
    public static let minimumWeighIns = 8
    public static let minimumWeighInSpanDays = 14.0
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
        /// One standard error of `maintenance`, kcal a day, from the scatter
        /// of the weigh-ins around their trend line (the weight side only;
        /// food-log error comes on top). Nil when it can't be worked out.
        public var uncertaintyKcal: Double? = nil

        /// "about ±250 kcal", rounded to 50, for beside the maintenance figure.
        public var uncertaintyText: String? {
            guard let uncertaintyKcal, uncertaintyKcal.isFinite else { return nil }
            return "about ±\(Int(max(50, (uncertaintyKcal / 50).rounded() * 50))) kcal"
        }
    }

    /// Why there's no estimate yet, for the app to explain.
    public struct Progress: Sendable, Equatable {
        public var fullyLoggedDays: Int
        public var partialDays: Int
        public var weighIns: Int
        /// Days between the first and last weigh-in in the window.
        public var weighInSpanDays: Double = 0
        public var daysNeeded: Int { max(0, minimumLoggedDays - fullyLoggedDays) }
        /// Weigh-ins still missing (of `minimumWeighIns`).
        public var weighInsNeeded: Int { max(0, minimumWeighIns - weighIns) }
        /// Whole days the weigh-ins still have to span (of `minimumWeighInSpanDays`).
        public var spanDaysNeeded: Int { max(0, Int((minimumWeighInSpanDays - weighInSpanDays).rounded(.up))) }
        /// True when the food log and the weigh-ins are both enough.
        public var isComplete: Bool { daysNeeded == 0 && weighInsNeeded == 0 && spanDaysNeeded == 0 }

        /// What is still needed, in words: "Still needed: 3 more fully logged
        /// days of food (11 of 14; 2 partly logged days don't count) and 2
        /// more weigh-ins (6 of 8). Until then, maintenance comes from your
        /// watch." Nil when nothing is missing.
        public var stillNeeded: String? {
            var parts: [String] = []
            if daysNeeded > 0 {
                let skipped = partialDays > 0 ? "; \(partialDays) partly logged day\(partialDays == 1 ? " doesn't" : "s don't") count" : ""
                parts.append("\(daysNeeded) more fully logged day\(daysNeeded == 1 ? "" : "s") of food (\(fullyLoggedDays) of \(minimumLoggedDays)\(skipped))")
            }
            if weighInsNeeded > 0 {
                parts.append("\(weighInsNeeded) more weigh-in\(weighInsNeeded == 1 ? "" : "s") (\(weighIns) of \(minimumWeighIns))")
            } else if spanDaysNeeded > 0 {
                parts.append("weigh-ins over \(spanDaysNeeded) more day\(spanDaysNeeded == 1 ? "" : "s") (they have to span \(Int(minimumWeighInSpanDays)))")
            }
            guard !parts.isEmpty else { return nil }
            return "Still needed: " + parts.joined(separator: " and ") + ". Until then, maintenance comes from your watch."
        }
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
        let recent = weights.filter { $0.date >= start }.map(\.date)
        let span = (recent.max() ?? now).timeIntervalSince(recent.min() ?? now) / 86_400
        return Progress(fullyLoggedDays: full.count, partialDays: partial, weighIns: recent.count, weighInSpanDays: max(0, span))
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
        guard logged.count >= minimumLoggedDays,
              let trend = WeightTrend.fit(recentWeights, minimumWeighIns: minimumWeighIns, minimumSpanDays: minimumWeighInSpanDays)
        else { return nil }
        let change = trend.weeklyChange
        let average = logged.map(\.value).reduce(0, +) / Double(logged.count)
        let maintenance = average - change / 7 * kcalPerKg
        guard (1200...5500).contains(maintenance) else { return nil }
        return Result(maintenance: maintenance, averageIntake: average, weeklyChangeKg: change,
                      loggedDays: logged.count, weighIns: recentWeights.count,
                      partialDaysSkipped: partial, creatineWaterRemovedKg: removed,
                      uncertaintyKcal: trend.standardError.map { $0 / 7 * kcalPerKg })
    }
}
