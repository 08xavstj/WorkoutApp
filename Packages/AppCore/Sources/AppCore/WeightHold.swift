import Foundation

/// What happens when the weight trend reaches the target: an offer to hold
/// there, and one line if the trend later drifts well above it.
///
/// Regain is the usual course after weight loss (Hall & Kahan, Med Clin
/// North Am 2018), and app-driven loss fades by 12 months (Chew et al., J Med
/// Internet Res 2022). What helped in the one large trial was weighing
/// regularly with a rule for acting on a set regain: over 18 months the share
/// regaining 2.3 kg or more was 72% with newsletters, 46% with the
/// face-to-face programme and 55% online (Wing et al., N Engl J Med
/// 2006;355:1563-71, 314 people; abstract checked on PubMed November 2026).
/// Weighing alone does little; inside a programme it helps (Madigan et al.,
/// IJBNPA 2015). So the hold is a weekly weigh-in plus one line with two
/// ways to act, and nothing else.
///
/// The risks set the limits (docs/research/healthy-living-2026-11.md §3 item
/// 6): weight vigilance can harm someone prone to disordered eating
/// (Anderberg et al., Body Image 2025, cross-sectional), so everything here
/// reads the smoothed trend and never a single weigh-in, shows nothing with
/// Hide calories on or when weigh-ins have stopped, never shows the regain
/// line during a planned gain, and the app draws none of it in red.
public enum WeightHold {
    /// How far above the held weight the trend sits before the line shows.
    /// App's choice of "about 2 kg", from the 2.3 kg regain Wing 2006 used
    /// as its outcome; the trial itself tested a programme, not this width.
    public static let regainBandKg = 2.0
    /// How long the trend has to stay above the band, days (app's choice).
    public static let regainDays = 14
    /// Weigh-ins in those days, and the days they span, before the line can
    /// show: weekly weighing gives two or three in a fortnight (app's choice).
    public static let regainMinimumWeighIns = 2
    public static let regainMinimumSpanDays = 7.0
    /// While holding, a weigh-in is asked for once a week: daily and weekly
    /// weighing did not differ in a meta-analysis (Madigan 2015).
    public static let weighInEveryDays = 7
    /// With no weigh-in for this long, weight tracking counts as paused: no
    /// nudge, no offer and no line until the next weigh-in (app's choice; the
    /// app has no pause switch, so stopping is the switch).
    public static let pausedAfterDays = 14
    /// "Not now" hides the hold offer for this long (app's choice).
    public static let offerAgainAfterDays = 14
    /// The rate of the short cut back to the held weight, % of body weight a
    /// week: the bottom of the 0.5-1% range that keeps muscle (Helms et al.,
    /// JISSN 2014), and never above the person's own limit (`GoalPlanner.RateLimit`).
    public static let shortCutRatePercent = 0.5
    /// A BMI under this is classed as underweight (WHO, Obesity: preventing
    /// and managing the global epidemic, Technical Report Series 894, 2000;
    /// the standard cut-off, not re-verified this round).
    public static let underweightBMI = 18.5

    /// The weight being held and since when. Kept by the app in UserDefaults.
    public struct State: Codable, Sendable, Equatable {
        public var targetKg: Double
        public var since: Date

        public init(targetKg: Double, since: Date) {
            self.targetKg = targetKg
            self.since = since
        }
    }

    // MARK: The trend

    /// True when weigh-ins have stopped (`pausedAfterDays`), or there never was one.
    public static func isPaused(lastWeighIn: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let lastWeighIn else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWeighIn), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= pausedAfterDays
    }

    /// The smoothed trend today (`WeightTrend.smooth`, the line on the weight
    /// chart): nil without enough recent weigh-ins for a trend
    /// (`WeightTrend.minimumWeighIns` in the last 28 days), or when weighing
    /// has stopped. The smoothing lags a steady loss by about half a kilo, so
    /// the trend reaches a target a little after the scale does.
    public static func currentTrendKg(_ weights: [DayValue], now: Date = .now, calendar: Calendar = .current) -> Double? {
        let past = weights.filter { $0.date <= now && $0.value > 0 }
        guard !isPaused(lastWeighIn: past.map(\.date).max(), now: now, calendar: calendar) else { return nil }
        let recent = past.filter { $0.date >= now.addingTimeInterval(-28 * 86_400) }
        guard recent.count >= WeightTrend.minimumWeighIns else { return nil }
        return WeightTrend.smooth(past).last?.value
    }

    // MARK: Target reached

    public struct Offer: Sendable, Equatable {
        public var targetKg: Double
        public var trendKg: Double
    }

    /// The "Hold here" offer: a lose or gain goal whose target the trend has
    /// reached. Nil while already holding, with calories hidden, while
    /// snoozed, or without a current trend.
    public static func offer(weights: [DayValue], goals: Goals?, holding: State?, hideCalories: Bool,
                             snoozedUntil: Date? = nil, now: Date = .now, calendar: Calendar = .current) -> Offer? {
        guard !hideCalories, holding == nil, let goals, goals.weight != .maintain,
              let target = goals.targetWeightKg, target > 0 else { return nil }
        if let snoozedUntil, now < snoozedUntil { return nil }
        guard let trend = currentTrendKg(weights, now: now, calendar: calendar) else { return nil }
        let reached = goals.weight == .lose ? trend <= target : trend >= target
        return reached ? Offer(targetKg: target, trendKg: trend) : nil
    }

    /// The goals once holding: maintain, so calories move to measured
    /// maintenance (`GoalPlanner.calorieTarget`). The target leaves the goal
    /// and lives in the hold's `State`.
    public static func holdGoals(from goals: Goals) -> Goals {
        var held = goals
        held.weight = .maintain
        held.targetWeightKg = nil
        return held
    }

    // MARK: The regain line

    public struct Regain: Sendable, Equatable {
        public var targetKg: Double
        public var trendKg: Double
        public var aboveKg: Double { trendKg - targetKg }
    }

    /// The one line: while holding, the trend has sat more than
    /// `regainBandKg` above the held weight for `regainDays`. Nil otherwise,
    /// with calories hidden, when weighing has stopped, and during a gain.
    public static func regain(weights: [DayValue], holding: State?, goals: Goals?, hideCalories: Bool,
                              now: Date = .now, calendar: Calendar = .current) -> Regain? {
        guard let holding, !hideCalories, goals?.weight != .gain else { return nil }
        let past = weights.filter { $0.date <= now && $0.value > 0 }
        guard !isPaused(lastWeighIn: past.map(\.date).max(), now: now, calendar: calendar) else { return nil }
        let windowStart = now.addingTimeInterval(-Double(regainDays) * 86_400)
        let window = WeightTrend.smooth(past).filter { $0.date >= windowStart }
        guard window.count >= regainMinimumWeighIns, let first = window.first, let last = window.last,
              last.date.timeIntervalSince(first.date) >= regainMinimumSpanDays * 86_400,
              window.allSatisfy({ $0.value > holding.targetKg + regainBandKg }) else { return nil }
        return Regain(targetKg: holding.targetKg, trendKg: last.value)
    }

    /// Option one: a short cut back to the held weight at `shortCutRatePercent`
    /// (or the person's own limit when that is lower).
    public static func shortCutGoals(from goals: Goals, holding: State, maximumPercent: Double? = nil) -> Goals {
        var cut = goals
        cut.weight = .lose
        cut.weeklyRatePercent = min(shortCutRatePercent, maximumPercent ?? shortCutRatePercent)
        cut.targetWeightKg = holding.targetKg
        return cut
    }

    /// About how many weeks the short cut takes, rounded up.
    public static func shortCutWeeks(_ regain: Regain, ratePercent: Double = shortCutRatePercent) -> Int {
        let weekly = regain.trendKg * ratePercent / 100
        guard weekly > 0 else { return 0 }
        return max(1, Int((regain.aboveKg / weekly).rounded(.up)))
    }

    /// Option two: accept the new weight. The hold moves to the trend,
    /// rounded to half a kilo.
    public static func accepted(_ regain: Regain, now: Date = .now) -> State {
        State(targetKg: (regain.trendKg * 2).rounded() / 2, since: now)
    }

    // MARK: Weigh-ins while holding

    public static let weighInTitle = "Weekly weigh-in"

    /// While holding: no weigh-in for a week. Stops by itself once weighing
    /// has stopped for `pausedAfterDays`, so it is one week of a quiet row,
    /// never a standing reminder.
    public static func weighInDue(holding: State?, lastWeighIn: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard holding != nil, let lastWeighIn, !isPaused(lastWeighIn: lastWeighIn, now: now, calendar: calendar) else { return false }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWeighIn), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= weighInEveryDays
    }

    public static func weighInDetail(lastWeighIn: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let lastWeighIn else { return "One weigh-in a week keeps your trend current while you hold." }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWeighIn), to: calendar.startOfDay(for: now)).day ?? 0
        return "Last weigh-in \(days) days ago. One a week keeps your trend current while you hold; read the trend, not the number."
    }

    // MARK: Checking a new target

    public enum TargetWarning: Sendable, Equatable {
        /// The target is under a BMI of 18.5.
        case underweight(bmi: Double)
        /// The target and its date (or the chosen pace) ask for more than the personal limit.
        case fasterThanLimit(percentPerWeek: Double, limitPercent: Double)
    }

    /// What to ask about before a target is saved. Empty when there is nothing to ask.
    /// - Parameters:
    ///   - targetDate: when the target is meant to be reached, if the goal
    ///     has a date. Without one, the chosen weekly rate is checked instead.
    ///   - limit: the person's fastest rate (`GoalPlanner.maximumWeeklyRate`).
    public static func targetWarnings(goals: Goals, targetKg: Double?, currentKg: Double?, heightCm: Double?,
                                      limit: GoalPlanner.RateLimit, targetDate: Date? = nil, now: Date = .now) -> [TargetWarning] {
        guard goals.weight != .maintain else { return [] }
        var warnings: [TargetWarning] = []
        if goals.weight == .lose, let targetKg, targetKg > 0, let heightCm, heightCm > 100 {
            let meters = heightCm / 100
            let bmi = targetKg / (meters * meters)
            if bmi < underweightBMI { warnings.append(.underweight(bmi: bmi)) }
        }
        var rate = goals.weeklyRatePercent
        if let targetDate, let targetKg, let currentKg, currentKg > 0 {
            let weeks = targetDate.timeIntervalSince(now) / (7 * 86_400)
            let change = goals.weight == .lose ? currentKg - targetKg : targetKg - currentKg
            // A date already past, or under a week away, asks for all of it in one week.
            if change > 0 { rate = change / max(1, weeks) / currentKg * 100 }
        }
        if limit.percent > 0, rate > limit.percent + 0.001 {
            warnings.append(.fasterThanLimit(percentPerWeek: rate, limitPercent: limit.percent))
        }
        return warnings
    }

    /// One plain sentence per warning, for the confirmation.
    public static func message(_ warning: TargetWarning, losing: Bool = true) -> String {
        switch warning {
        case .underweight(let bmi):
            return "That target is a BMI of \(Longevity.one(bmi)). Under \(Longevity.one(underweightBMI)) is classed as underweight (WHO), which carries health risks of its own."
        case .fasterThanLimit(let percent, let limit):
            let cost = losing ? "costs muscle" : "mostly adds fat"
            return "That asks for about \(Longevity.one(percent))% of your weight a week. For you, faster than \(Longevity.one(limit))% a week \(cost)."
        }
    }
}

extension WeighInNudge {
    /// The weigh-in row with the hold in mind: a lose or gain goal keeps the
    /// usual rule (`isDue(goals:lastWeighIn:)`); a held weight asks once a
    /// week (`WeightHold.weighInDue`); a plain maintain goal still gets none.
    public static func isDue(goals: Goals?, lastWeighIn: Date?, holding: WeightHold.State?,
                             now: Date = .now, calendar: Calendar = .current) -> Bool {
        if isDue(goals: goals, lastWeighIn: lastWeighIn, now: now, calendar: calendar) { return true }
        guard goals?.weight == .maintain else { return false }
        return WeightHold.weighInDue(holding: holding, lastWeighIn: lastWeighIn, now: now, calendar: calendar)
    }
}
