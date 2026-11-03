import Foundation

/// Short sleep while cutting costs muscle.
///
/// In a 14-day crossover trial on the same calorie deficit, 5.5 h in bed
/// instead of 8.5 h cut fat loss by 55% and raised lean-mass loss by 60%
/// (Nedeltcheva et al., Ann Intern Med 2010; 10 people, so a small trial, but
/// in line with larger sleep-restriction work: health-metrics.md §4, rated
/// weak-moderate for the number). The rule from the report: in a deficit with
/// more than about 5 h of sleep debt over 14 nights, say the deficit is
/// costing muscle and ease the rate. The calorie loop (`CalorieBand`) is not
/// changed; the advice suggests a slower rate in Goals and the sleep plan.
public enum CutAndSleep {
    /// The `SleepDebt` level that triggers the advice: "high" starts at 6 h
    /// over 14 nights, the existing threshold nearest the report's "over 5 h".
    public static let triggerLevel: SleepDebt.Level = .high

    public static let title = "Short sleep while cutting costs muscle"

    public struct Advice: Sendable, Equatable {
        public var message: String
        /// A slower weekly rate (% of body weight) to pick in Goals, or nil
        /// when already at the slowest option.
        public var suggestedRatePercent: Double?

        public init(message: String, suggestedRatePercent: Double?) {
            self.message = message
            self.suggestedRatePercent = suggestedRatePercent
        }
    }

    /// The next slower rate from `GoalPlanner.rateOptions(for: .lose)`.
    public static func slowerRate(than rate: Double) -> Double? {
        GoalPlanner.rateOptions(for: .lose).filter { $0 < rate - 0.001 }.max()
    }

    /// Nil unless the goal is to lose weight and the 14-night sleep debt is high.
    public static func advice(goals: Goals?, sleepDebt: SleepDebt.Result?) -> Advice? {
        guard let goals, goals.weight == .lose, let sleepDebt, sleepDebt.level == triggerLevel else { return nil }
        let slower = slowerRate(than: goals.weeklyRatePercent)
        let debt = sleepDebt.hours.formatted(.number.precision(.fractionLength(0...1)))
        var message = "In a 14-day trial on the same diet, people sleeping 5.5 h instead of 8.5 h lost 55% less fat and 60% more lean mass (Nedeltcheva 2010; a small study). You're \(debt) h behind over 14 nights, so easing the deficit this week keeps more muscle: "
        if let slower {
            message += "pick \(slower.formatted(.number.precision(.fractionLength(0...2))))% a week in Goals for now, and follow the sleep plan first."
        } else {
            message += "you're already at the slowest rate, so follow the sleep plan first and hold the target rather than tightening it."
        }
        return Advice(message: message, suggestedRatePercent: slower)
    }
}
