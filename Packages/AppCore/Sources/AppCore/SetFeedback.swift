import Foundation

/// The one-line verdict after a working set, and the personal records at the
/// end of an exercise.
///
/// Seeing how a set compares with the last one helps performance and strength
/// over a training cycle (Weakley J, et al. The effect of feedback on
/// resistance training performance and adaptations: a systematic review and
/// meta-analysis. Sports Med 2023). The wording is about the plan, not about
/// "beating" last time, so it doesn't push you past the target reps in reserve
/// (docs/research/lifting-features.md §3.1). PRs are reported quietly and
/// factually: celebrating them is engagement, not training (behaviour-change.md).
public enum SetFeedback {
    public enum Verdict: Sendable, Equatable {
        /// Fewer reps than the plan's target.
        case short(reps: Int)
        /// Past the plan's effort by at least `Autoregulation.triggerReps`.
        case pastEffort(targetRIR: Double)
        /// Heavier than the same set last time, at least as many reps (gym unit).
        case heavier(by: Double)
        /// Same weight as last time, more reps.
        case moreReps(Int)
        /// Hit the plan's target reps.
        case matchedPlan
        /// Same weight and reps as last time (no plan to compare with).
        case matchedLastTime

        public func message(unit: String) -> String {
            switch self {
            case let .short(reps):
                return "\(reps) short: the planner will hold the load"
            case let .pastEffort(rir):
                return "Harder than planned: aim for \(Autoregulation.reserveText(rir)) in reserve next set"
            case let .heavier(delta):
                return "+\(Autoregulation.format(delta)) \(unit) on last time"
            case let .moreReps(reps):
                return "+\(reps) rep\(reps == 1 ? "" : "s") on last time"
            case .matchedPlan:
                return "Matched the plan"
            case .matchedLastTime:
                return "Same as last time"
            }
        }

        /// True for the verdicts that say you're behind or over the plan.
        public var isCaution: Bool {
            switch self {
            case .short, .pastEffort: true
            default: false
            }
        }
    }

    /// The verdict for a logged set, compared with the plan first and then
    /// with the same set last session. `last` and `logged` weights are in the
    /// same unit. Nil when nothing was logged or there's nothing to compare.
    public static func verdict(
        logged: LiftProgress.LoggedSet,
        last: LiftProgress.LoggedSet?,
        targetReps: Int?,
        targetRPE: Double?
    ) -> Verdict? {
        guard logged.reps > 0 else { return nil }
        if let targetReps, logged.reps < targetReps {
            return .short(reps: targetReps - logged.reps)
        }
        // Grinding past the target effort is the risk of comparing with last
        // time, so it's named before any "+1 rep" (two reps past the plan:
        // outside the ~1-rep RPE error, Halperin et al. 2022).
        if let targetRPE, let rpe = logged.rpe, rpe - targetRPE >= Autoregulation.triggerReps - 0.001 {
            return .pastEffort(targetRIR: max(0, 10 - targetRPE))
        }
        if let last, last.reps > 0 {
            if logged.weight > last.weight + 0.01, logged.reps >= last.reps {
                return .heavier(by: logged.weight - last.weight)
            }
            if abs(logged.weight - last.weight) <= 0.01, logged.reps > last.reps {
                return .moreReps(logged.reps - last.reps)
            }
        }
        if targetReps != nil { return .matchedPlan }
        if let last, abs(logged.weight - last.weight) <= 0.01, logged.reps == last.reps {
            return .matchedLastTime
        }
        return nil
    }

    // MARK: Personal records

    public enum Record: Sendable, Equatable {
        /// Best estimated one-rep max (Epley with reps left from RPE, `OneRepMax`).
        case estimatedOneRepMax(Double)
        /// Most reps ever at this weight or heavier.
        case reps(weight: Double, reps: Int)
        /// Most weight × reps in one session.
        case volume(Double)

        public func message(unit: String) -> String {
            switch self {
            case let .estimatedOneRepMax(value):
                return "Best estimated 1RM: \(Autoregulation.format(value.rounded())) \(unit)"
            case let .reps(weight, reps):
                return "Most reps at \(Autoregulation.format(weight)) \(unit): \(reps)"
            case let .volume(value):
                return "Most volume in a session: \(Autoregulation.format(value.rounded())) \(unit)"
            }
        }
    }

    /// Records today's completed working sets set against every earlier
    /// session of the same exercise (same unit). None on the first session:
    /// there's nothing to beat yet (as `LiftProgress.points`).
    public static func records(today: [LiftProgress.LoggedSet], earlier: [LiftProgress.LoggedSession]) -> [Record] {
        let sets = today.filter { $0.reps > 0 }
        let past = earlier.flatMap(\.sets).filter { $0.reps > 0 }
        guard !sets.isEmpty, !past.isEmpty else { return [] }
        var result: [Record] = []

        let bestToday = sets.map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps, rpe: $0.rpe) }.max() ?? 0
        let bestBefore = past.map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps, rpe: $0.rpe) }.max() ?? 0
        if bestToday > bestBefore + 0.01 {
            result.append(.estimatedOneRepMax(bestToday))
        }

        // Rep PR: more reps than ever at this weight or heavier, where there
        // was an earlier set that heavy (a first-ever weight isn't a rep record).
        var repRecord: LiftProgress.LoggedSet?
        for set in sets where set.weight > 0 {
            let comparable = past.filter { $0.weight >= set.weight - 0.01 }
            guard let most = comparable.map(\.reps).max(), set.reps > most else { continue }
            if let current = repRecord, current.weight > set.weight || (current.weight == set.weight && current.reps >= set.reps) {
                continue
            }
            repRecord = set
        }
        if let repRecord {
            result.append(.reps(weight: repRecord.weight, reps: repRecord.reps))
        }

        let volumeToday = sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
        let volumeBefore = earlier.map { session in
            session.sets.filter { $0.reps > 0 }.reduce(0) { $0 + $1.weight * Double($1.reps) }
        }.max() ?? 0
        if volumeToday > volumeBefore + 0.01, volumeBefore > 0 {
            result.append(.volume(volumeToday))
        }
        return result
    }
}
