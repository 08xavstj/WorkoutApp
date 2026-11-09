import Foundation

/// A training block (mesocycle): 4-6 weeks in which the sets per exercise
/// ramp up, the effort target moves closer to failure, then one easier week,
/// then the next block starts.
///
/// - Periodised training beats non-periodised for 1RM strength (Williams et
///   al., Sports Med 2017, meta-analysis, ES 0.43); for muscle growth the
///   evidence is weaker and linear vs undulating makes no difference (Grgic
///   et al., PeerJ 2017), so the ramp is modest.
/// - The planned easier week follows the international Delphi consensus on
///   deloads: about a week, same weights, roughly half the sets (Bell et al.,
///   Sports Med Open 2023). One RCT found no advantage for a planned deload
///   over continuous training (Coleman et al., PeerJ 2024, not re-verified in
///   docs/research/competitors.md), so the UI calls it "planned", not "needed".
/// - Volume ramps within the planner's 10-20 hard sets per muscle a week and
///   is capped at 5 sets per exercise, because more sets keep adding muscle
///   only with diminishing returns (Pelland et al., Sports Med 2026;
///   Schoenfeld et al., J Sports Sci 2017).
///   Per muscle, `VolumeProgression` turns the block week into a weekly set
///   target (10 → 12 → 14 → 16, deload about half) that moves only when last
///   week's sets were done at the effort target and the muscle recovered; the
///   planner follows those targets (`WorkoutPlanner.plan(muscleSetGoals:)`)
///   and `setMultiplier` stays the fallback for muscles without one.
/// - The day-to-day HRV guidance stays on top: a low-recovery day lowers the
///   RPE inside the block (`WorkoutPlanner.targetRPE(recovery:block:)`), and
///   a week that starts with HRV below normal repeats the previous week's
///   sets instead of adding more (`nextWeek(after:hrvBelowNormal:)`).
///   Autoregulated and fixed loading give similar strength (Hickmott et al.,
///   Sports Med Open 2022), so neither layer is allowed to swing far.
public struct TrainingBlock: Codable, Sendable, Equatable {
    /// Where the block is this week: how many sets, how hard.
    public struct WeekState: Codable, Sendable, Equatable {
        /// 1-based week in the block.
        public var week: Int
        public var length: Int
        /// Multiplies the planner's base sets per exercise (`scaledSets`).
        public var setMultiplier: Double
        /// Reps in reserve to stop at on working sets.
        public var targetRIR: Int
        public var isDeload: Bool
        /// HRV was below normal when the week began, so the ramp stayed put.
        public var isHeld: Bool

        public init(week: Int, length: Int, setMultiplier: Double, targetRIR: Int, isDeload: Bool, isHeld: Bool = false) {
            self.week = week
            self.length = length
            self.setMultiplier = setMultiplier
            self.targetRIR = targetRIR
            self.isDeload = isDeload
            self.isHeld = isHeld
        }

        /// The RIR target as an RPE on the reps-in-reserve scale (RIR 1 = RPE 9).
        public var targetRPE: Double { Double(10 - targetRIR) }

        /// "Block week 3 of 5 · 1 rep in the tank" or "Deload week (5 of 5) · 3
        /// reps in the tank": the same words the sets and the builder use (`ReserveText`).
        public var label: String {
            isDeload
                ? "Deload week (\(week) of \(length)) · \(ReserveText.text(Double(targetRIR)))"
                : "Block week \(week) of \(length) · \(ReserveText.text(Double(targetRIR)))"
        }

        /// The note, plus "Today eased to 3-4 reps in the tank." when the day's plan
        /// backs off from the block's target (low recovery).
        public func note(plannedRPE: Double) -> String {
            let reserve = 10 - plannedRPE
            guard reserve > Double(targetRIR) + 0.25 else { return note }
            return note + " Today eased to \(ReserveText.text(reserve))."
        }

        /// One short line on what this week changes.
        public var note: String {
            // RIR 3 at the usual reps makes the planner's weights a little lighter (`WorkoutPlanner.suggestedLoad`).
            if isDeload { return "Planned easier week: about half the sets, a little lighter." }
            if isHeld { return "HRV is below your normal range, so this week repeats last week's sets instead of adding more." }
            let percent = Int(((setMultiplier - 1) * 100).rounded())
            let reserve = ReserveText.text(Double(targetRIR))
            if percent <= 0 { return "Base sets this week; stop with \(reserve)." }
            return "About \(percent)% more sets than week 1; stop with \(reserve)."
        }
    }

    /// Monday the block began.
    public var start: Date
    public var style: TrainingStyle
    /// Weeks in the block, deload week included.
    public var length: Int
    /// The week the block is on.
    public var week: WeekState
    /// Monday of the calendar week `week` applies to.
    public var weekStart: Date
    /// Weeks the ramp was held for low HRV (the block runs that much longer).
    public var heldWeeks: Int

    public init(start: Date, style: TrainingStyle, length: Int? = nil) {
        let weeks = length ?? Self.length(for: style)
        self.start = start
        self.style = style
        self.length = weeks
        self.week = Self.weekState(1, style: style, length: weeks)
        self.weekStart = start
        self.heldWeeks = 0
    }

    // MARK: Schedule

    /// Block length by goal, deload included: strength 5 (4 building weeks),
    /// muscle and strength + muscle 6 (5 building weeks), balanced 5. Both sit inside the 4-6 week
    /// range in docs/research/competitors.md §2a.2; the app chose the longer
    /// ramp for muscle because volume, not intensity, is its lever. Stamina
    /// and health goals keep steady weeks with no ramp and no deload (the
    /// report's goal tailoring: "keep the current 2-3 full-body days").
    public static func length(for style: TrainingStyle) -> Int {
        switch style {
        case .strength, .balanced: 5
        case .muscle, .strengthAndMuscle: 6
        case .endurance: 4
        }
    }

    /// Sets added each building week (+10%), and where the ramp stops.
    static let rampStep = 0.10
    /// Strength and balanced: 1.0 → 1.1 → 1.2 → 1.25. Muscle: up to 1.4, so a
    /// 4-set base reaches the 5-set cap (two exercises × two sessions ≈ 20
    /// sets a muscle a week, the top of the productive range).
    static func rampCap(style: TrainingStyle) -> Double {
        style.buildsMuscle ? 1.4 : 1.25
    }
    /// Deload: about half the sets (Bell et al. 2023), rounded up from 0.5 so
    /// a 3-set exercise keeps 2.
    public static let deloadMultiplier = 0.6
    /// Fewest and most sets per exercise after scaling.
    public static let setRange = 2...5
    /// Reps in reserve: 3 → 2 → 1 → 1 … on building weeks, 3 on the deload.
    static let startRIR = 3
    static let deloadRIR = 3

    static func hasDeload(style: TrainingStyle) -> Bool { style != .endurance }

    /// The week-by-week state for a block of this style and length.
    public static func weekState(_ week: Int, style: TrainingStyle, length: Int) -> WeekState {
        let index = max(1, min(week, length))
        let deload = hasDeload(style: style) && index == length
        if deload {
            return WeekState(week: index, length: length, setMultiplier: deloadMultiplier, targetRIR: deloadRIR, isDeload: true)
        }
        if style == .endurance {
            return WeekState(week: index, length: length, setMultiplier: 1, targetRIR: startRIR, isDeload: false)
        }
        let multiplier = min(rampCap(style: style), 1 + rampStep * Double(index - 1))
        let rir = max(1, startRIR - (index - 1))
        return WeekState(week: index, length: length, setMultiplier: (multiplier * 100).rounded() / 100, targetRIR: rir, isDeload: false)
    }

    /// Every week of a block, for previews and tests.
    public static func schedule(style: TrainingStyle, length: Int? = nil) -> [WeekState] {
        let weeks = length ?? Self.length(for: style)
        return (1...max(1, weeks)).map { weekState($0, style: style, length: weeks) }
    }

    /// Base sets × this week's multiplier, kept to 2-5 sets per exercise.
    public static func scaledSets(_ base: Int, multiplier: Double) -> Int {
        // A NaN or infinite multiplier (a corrupt saved block) would trap the Int conversion.
        let product = (Double(base) * multiplier).rounded()
        guard product.isFinite else { return max(setRange.lowerBound, min(setRange.upperBound, base)) }
        let scaled = Int(max(-1_000, min(1_000, product)))
        return max(setRange.lowerBound, min(setRange.upperBound, scaled))
    }

    // MARK: Moving through the block

    /// The week after `week`, or nil when the block is finished. With HRV
    /// below normal the ramp holds: the same week comes back marked `isHeld`,
    /// unless the next week is the deload, which is the right week for a low
    /// HRV anyway.
    public func nextWeek(after week: WeekState, hrvBelowNormal: Bool = false) -> WeekState? {
        guard week.week < length else { return nil }
        let next = Self.weekState(week.week + 1, style: style, length: length)
        if hrvBelowNormal && !next.isDeload && !week.isDeload {
            var held = week
            held.isHeld = true
            return held
        }
        return next
    }

    /// After a break this long the block starts again from week 1 rather
    /// than resuming mid-ramp. Strength and muscle are largely kept for about
    /// 3 weeks off (Mujika & Padilla, Sports Med 2000; Bosquet et al., Scand
    /// J Med Sci Sports 2013, meta-analysis: strength holds for about 3 weeks
    /// of detraining), so a two-week gap no longer resets the ramp; 4 weeks
    /// is the app's line (audit 2026-11 §9). Weekly sets after a shorter
    /// gap come from what you did before it (`VolumeProgression.startingSets(for:recentWeeklySets:weeksAway:style:)`).
    public static let restartAfterWeeksAway = 4

    /// The block as it stands in the week containing `now`: unchanged within
    /// the same calendar week, moved on one week otherwise, or a fresh block
    /// (in `style`, default the same) when this one has finished or more than
    /// a week was skipped.
    public func advanced(to now: Date, hrvBelowNormal: Bool = false, style newStyle: TrainingStyle? = nil, calendar: Calendar = .current) -> TrainingBlock {
        let thisWeek = WeeklyPlan.weekStart(containing: now, calendar: calendar)
        guard thisWeek > weekStart else { return self }
        let days = calendar.dateComponents([.day], from: weekStart, to: thisWeek).day ?? 7
        let weeksGone = max(1, days / 7)
        if weeksGone >= Self.restartAfterWeeksAway {
            return TrainingBlock(start: thisWeek, style: newStyle ?? style)
        }
        guard let next = nextWeek(after: week, hrvBelowNormal: hrvBelowNormal) else {
            return TrainingBlock(start: thisWeek, style: newStyle ?? style)
        }
        var block = self
        block.week = next
        block.weekStart = thisWeek
        if next.isHeld { block.heldWeeks += 1 }
        return block
    }

    /// Does this block's current week cover the week starting `weekStart`?
    public func covers(weekStart other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(weekStart, inSameDayAs: other)
    }

    /// One line for the AI coach.
    public var coachLine: String {
        var line = "Training block: week \(week.week) of \(week.length), RIR \(week.targetRIR)"
        if week.isDeload { line += " (planned easier week, about half the sets)" }
        else if week.isHeld { line += " (ramp held: HRV below normal)" }
        else if week.setMultiplier > 1 { line += " (sets ×\(week.setMultiplier.formatted()))" }
        return line + "."
    }
}
