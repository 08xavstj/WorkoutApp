import Foundation

/// How two scores for the same days move together: how often they change in
/// the same direction from one day to the next, and, once there are enough
/// days, a rank correlation.
///
/// Descriptive only. Used for Apple's numbers beside the app's own
/// (`AppleScoreLog`): the two are worked out differently, and neither is a
/// reference for the other, so nothing here says which one is right.
public enum ScoreAgreement {
    /// Both numbers on one day. `day` counts days (any fixed origin).
    public struct Pair: Sendable, Equatable {
        public var day: Int
        public var apple: Double
        public var app: Double

        public init(day: Int, apple: Double, app: Double) {
            self.day = day
            self.apple = apple
            self.app = app
        }
    }

    // MARK: Direction

    /// Day-to-day changes compared between entries at most this many days
    /// apart. The app's choice: a change across a longer gap says little about
    /// whether the two scores react to the same nights.
    public static let maxGapDays = 3

    public struct Direction: Sendable, Equatable {
        /// Both went up, or both went down.
        public var same: Int
        /// One went up while the other went down.
        public var opposite: Int
        /// One or both didn't change (common for a 0–10 score), so there is
        /// no direction to compare.
        public var flat: Int

        /// Changes where both moved.
        public var compared: Int { same + opposite }
        /// Share that moved the same way, nil when none can be compared.
        public var share: Double? { compared > 0 ? Double(same) / Double(compared) : nil }
    }

    /// Compares the direction of each change between consecutive entries.
    public static func direction(_ pairs: [Pair]) -> Direction {
        let sorted = pairs.sorted { $0.day < $1.day }
        var result = Direction(same: 0, opposite: 0, flat: 0)
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next.day - previous.day
            guard gap >= 1, gap <= maxGapDays else { continue }
            let apple = next.apple - previous.apple
            let app = next.app - previous.app
            if apple == 0 || app == 0 {
                result.flat += 1
            } else if (apple > 0) == (app > 0) {
                result.same += 1
            } else {
                result.opposite += 1
            }
        }
        return result
    }

    // MARK: Correlation

    /// Days with both numbers before a correlation is shown. The app's
    /// choice, not a published cut-off: with fewer, the likely range of a
    /// rank correlation covers most of −1…1 (at 10 days a measured 0.5 could
    /// be anything from about −0.2 to 0.9; at 20, about 0.05 to 0.8, by the
    /// interval below). Correlations only settle near their true value at
    /// around 250 pairs (Schönbrodt & Perugini, J Res Pers 2013;47:609–612),
    /// so even past 20 the figure is a description of these days, not a finding.
    public static let minimumPairsForCorrelation = 20

    public struct Correlation: Sendable, Equatable {
        /// Spearman's rank correlation, −1…1.
        public var rho: Double
        public var count: Int
        /// Approximate 95% interval. Too narrow if anything: consecutive days
        /// aren't independent, which the formula assumes.
        public var low: Double
        public var high: Double
    }

    /// Spearman's rank correlation, or nil with fewer than
    /// `minimumPairsForCorrelation` pairs or when one score never changed.
    ///
    /// Ranks, not raw values: the scales differ (0–10 against 1–99), a 0–10
    /// score has many ties, and nothing says the relation is a straight line.
    /// The interval is Fisher's z with the Spearman variance
    /// (1 + rho²/2)/(n − 3) (Bonett & Wright, Psychometrika 2000;65:23–28).
    public static func spearman(_ pairs: [Pair], minimumPairs: Int = minimumPairsForCorrelation) -> Correlation? {
        let count = pairs.count
        guard count >= max(4, minimumPairs) else { return nil }
        guard let rho = pearson(ranks(pairs.map(\.apple)), ranks(pairs.map(\.app))) else { return nil }
        let bounded = min(0.999_999, max(-0.999_999, rho))
        let z = atanh(bounded)
        let error = ((1 + bounded * bounded / 2) / Double(count - 3)).squareRoot()
        return Correlation(rho: rho, count: count, low: tanh(z - 1.96 * error), high: tanh(z + 1.96 * error))
    }

    /// Ranks from 1, ties sharing the average of their positions.
    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = [Double](repeating: 0, count: values.count)
        var start = 0
        while start < order.count {
            var end = start
            while end + 1 < order.count, values[order[end + 1]] == values[order[start]] { end += 1 }
            let shared = Double(start + end) / 2 + 1
            for position in start...end { result[order[position]] = shared }
            start = end + 1
        }
        return result
    }

    /// Pearson's r; nil when either side has no spread.
    static func pearson(_ first: [Double], _ second: [Double]) -> Double? {
        guard first.count == second.count, first.count > 1 else { return nil }
        let count = Double(first.count)
        let meanFirst = first.reduce(0, +) / count
        let meanSecond = second.reduce(0, +) / count
        var cross = 0.0, spreadFirst = 0.0, spreadSecond = 0.0
        for (a, b) in zip(first, second) {
            cross += (a - meanFirst) * (b - meanSecond)
            spreadFirst += (a - meanFirst) * (a - meanFirst)
            spreadSecond += (b - meanSecond) * (b - meanSecond)
        }
        guard spreadFirst > 0, spreadSecond > 0 else { return nil }
        return min(1, max(-1, cross / (spreadFirst * spreadSecond).squareRoot()))
    }

    // MARK: Difference

    /// Apple's number minus the app's, averaged. Only meaningful when the two
    /// share a scale (`AppleScoreKind.sharesScaleWithApp`).
    public static func meanDifference(_ pairs: [Pair]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        return pairs.reduce(0) { $0 + ($1.apple - $1.app) } / Double(pairs.count)
    }

    // MARK: Summary

    public struct Summary: Sendable, Equatable {
        /// Days with both numbers.
        public var count: Int
        public var direction: Direction
        public var correlation: Correlation?
        public var meanDifference: Double?
        /// More days needed before a correlation is shown (0 once shown or
        /// when it can't be worked out).
        public var pairsUntilCorrelation: Int
    }

    public static func summary(_ pairs: [Pair]) -> Summary {
        Summary(
            count: pairs.count,
            direction: direction(pairs),
            correlation: spearman(pairs),
            meanDifference: meanDifference(pairs),
            pairsUntilCorrelation: max(0, minimumPairsForCorrelation - pairs.count)
        )
    }
}
