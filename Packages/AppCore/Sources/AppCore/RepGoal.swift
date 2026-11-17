import Foundation

/// The next set's rep goal at the same weight, from the set just done and
/// how many more reps it had in it. The lifter sees only the goal ("8 reps");
/// the plan's reps-in-reserve target stays behind the scenes.
///
/// Reps you could have done = reps done + reps left, so the reps that leave
/// the plan's reserve next set are reps done + (reps left − planned reserve).
/// This is reps-in-reserve autoregulation applied to the rep count, which
/// gave about the same strength and muscle gains as fixed loading (Hickmott
/// et al., Sports Med Open 2022). Two cautions keep the step small:
/// - Guesses of reps left are off by about a rep, more on long sets and far
///   from failure (Halperin et al., Sports Med 2022), and "4+" can mean many
///   more, so a goal moves at most `maxStepUp` reps up a set.
/// - Reps at the same weight fall across sets as fatigue builds (Willardson &
///   Burkett, J Strength Cond Res 2006), so a goal that would rise from a set
///   on plan doesn't.
/// The goal stays near the planned range (`rangeSlack`), so a set doesn't
/// turn into a different kind of set; past it, the weight should change
/// (`Autoregulation`). Step sizes and slack are app choices.
public enum RepGoal {
    /// The most a goal rises after one set.
    public static let maxStepUp = 2
    /// The most a goal falls after one set (a set to failure that came up short).
    public static let maxStepDown = 3
    /// How far past the planned range a goal may go.
    public static let rangeSlack = 2

    /// Reps for the next set at the same weight.
    /// - Parameters:
    ///   - repsDone: reps in the set just logged.
    ///   - repsLeft: reps it had left, 0-4 (4 means "4 or more").
    ///   - targetRIR: the plan's reps in reserve.
    ///   - range: the plan's rep range.
    public static func next(repsDone: Int, repsLeft: Int, targetRIR: Double, range: ClosedRange<Int>) -> Int {
        let move = step(repsLeft: repsLeft, targetRIR: targetRIR)
        let low = max(1, range.lowerBound - rangeSlack)
        let high = min(Autoregulation.maxReps, range.upperBound + rangeSlack)
        return min(high, max(low, repsDone + move))
    }

    /// How many reps a rating moves the next goal from the reps just done:
    /// the whole reps between the reps left and the plan's reserve, within
    /// `maxStepUp` and `maxStepDown`. 0 means the set was on plan, which is
    /// also when a set row may say "Matched the plan" (`SetFeedback.verdict`).
    public static func step(repsLeft: Int, targetRIR: Double) -> Int {
        let gap = Double(min(4, max(0, repsLeft))) - targetRIR
        // A half-rep gap is within the guessing error: no change for it.
        let whole = Int(gap.rounded(.towardZero))
        return min(maxStepUp, max(-maxStepDown, whole))
    }

    // MARK: Each set's own goal

    /// The rep goal a set was given this session. Goals move after every
    /// rated set, so each set keeps the goal it had when it was done
    /// (`goals`: set order → goal); a set ticked on goal is never judged
    /// later against another set's goal or the plan's first number.
    /// - Parameters:
    ///   - goals: the goals recorded so far, by set order; nil on a change
    ///     saved before goals were kept per set.
    ///   - changed: for such an older change: the first set it moved and the
    ///     reps it set from there on.
    ///   - planned: today's planned reps, for a set before any change.
    public static func goal(setOrder: Int, goals: [Int: Int]?, changed: (fromOrder: Int, reps: Int)?, planned: Int?) -> Int? {
        if let goals {
            if let own = goals[setOrder] { return own }
            // No goal of its own (a set added since, which starts as a copy of
            // the set before it): the goal of the nearest set before it that has one.
            if let before = goals.keys.filter({ $0 < setOrder }).max(), let goal = goals[before] { return goal }
            return planned
        }
        if let changed, setOrder >= changed.fromOrder { return changed.reps }
        return planned
    }

    /// The goals to keep when a new change replaces the one before it: the
    /// recorded ones, or for a change saved without them, its reps on every
    /// set from the one it first moved (`setOrders`: the exercise's sets).
    public static func carriedGoals(_ goals: [Int: Int]?, changed: (fromOrder: Int, reps: Int)?, setOrders: [Int]) -> [Int: Int] {
        if let goals { return goals }
        guard let changed else { return [:] }
        var result: [Int: Int] = [:]
        for order in setOrders where order >= changed.fromOrder { result[order] = changed.reps }
        return result
    }

    /// "Goal 9 reps: you had 4+ left", "Goal 6 reps: that set was hard";
    /// nil when the goal didn't change.
    public static func note(goal: Int, previous: Int, repsLeft: Int) -> String? {
        guard goal != previous else { return nil }
        if goal > previous {
            return "Next set goal \(goal) reps: you had \(ReserveText.choiceLabel(repsLeft)) left"
        }
        return repsLeft == 0
            ? "Next set goal \(goal) reps: you hit your limit"
            : "Next set goal \(goal) reps: that set was harder than planned"
    }
}
