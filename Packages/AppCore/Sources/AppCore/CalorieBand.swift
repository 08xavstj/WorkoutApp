import Foundation

/// The flexible calorie band and the weekly target adjustment.
///
/// - Band: ±10% around the daily target. Flexible dieting matched rigid
///   dieting for fat loss and kept more fat-free mass afterwards (Conlin et
///   al., JISSN 2021); rigid restraint goes with overeating and anxiety
///   (Smith et al., Appetite 1999). Daily numbers are noisy; the weekly
///   average is what moves weight.
/// - Weekly adjustment: the target moves once a week, by at most 100 kcal,
///   toward what measured maintenance and the goal rate call for. The
///   measured side needs 14 fully logged days (`AdaptiveTDEE`); the loop is
///   the one the self-monitoring evidence supports (Burke, Wang & Sevick,
///   J Am Diet Assoc 2011; Berry et al., Obes Rev 2021). Guard rails: losing
///   faster than 1% of body weight a week costs muscle (Helms et al., JISSN
///   2014; Garthe et al., IJSNEM 2011) and gaining faster than 0.5% a week is
///   mostly fat (Iraki et al., Sports 2019), so those always move the target
///   a full step the safe way.
public enum CalorieBand {
    /// ±10% (Conlin et al., JISSN 2021).
    public static let flexibleFraction = 0.10
    /// Most the target moves in a week, kcal/day (docs/research/nutrition.md: "nudge ±100 kcal").
    public static let maxWeeklyStepKcal = 100.0
    /// Changes smaller than this are inside the maintenance estimate's noise
    /// and aren't worth a new number (app choice: half a step).
    public static let minimumStepKcal = 50.0
    /// Fastest safe loss, % of body weight a week (Helms 2014; Garthe 2011).
    public static let maxLossPercentPerWeek = 1.0
    /// Fastest useful gain, % of body weight a week (Iraki 2019).
    public static let maxGainPercentPerWeek = 0.5

    public static func range(target: Double) -> ClosedRange<Double> {
        (target * (1 - flexibleFraction))...(target * (1 + flexibleFraction))
    }

    public enum Reason: String, Sendable {
        case slowerThanPlanned = "weight moved slower than planned"
        case fasterThanPlanned = "weight moved faster than planned"
        case losingTooFast = "you were losing faster than 1% a week, which costs muscle"
        case gainingTooFast = "you were gaining faster than planned, and extra speed is mostly fat"
        case driftingUp = "your weight has been drifting up"
        case driftingDown = "your weight has been drifting down"
        case maintenanceChanged = "your measured maintenance changed"
    }

    public struct Adjustment: Sendable, Equatable {
        /// Change to the daily target, kcal, rounded to 10 (negative = eat less).
        public var deltaKcal: Double
        public var newTarget: Double
        public var reason: Reason

        /// "Target adjusted −60 kcal this week: weight moved slower than planned"
        public var note: String {
            let sign = deltaKcal < 0 ? "−" : "+"
            return "Target adjusted \(sign)\(Int(abs(deltaKcal))) kcal this week: \(reason.rawValue)."
        }
    }

    /// The week's adjustment, or nil when nothing should change.
    /// - Parameters:
    ///   - measuredMaintenance: from `AdaptiveTDEE.Result.maintenance`.
    ///   - currentTarget: the target in force this week.
    ///   - weeklyChangeKg: measured change per week, negative = losing (`AdaptiveTDEE.Result.weeklyChangeKg`).
    ///   - loggedDays: fully logged days behind the estimate (`AdaptiveTDEE.Result.loggedDays`).
    public static func weeklyAdjustment(
        measuredMaintenance: Double,
        currentTarget: Double,
        goals: Goals,
        bodyMassKg: Double,
        weeklyChangeKg: Double,
        loggedDays: Int,
        sex: BiologicalSex
    ) -> Adjustment? {
        guard loggedDays >= AdaptiveTDEE.minimumLoggedDays, bodyMassKg > 0, currentTarget > 0 else { return nil }
        let desired = GoalPlanner.calorieTarget(maintenance: measuredMaintenance, bodyMassKg: bodyMassKg, goals: goals, sex: sex)
        var delta = desired - currentTarget
        let percent = weeklyChangeKg / bodyMassKg * 100
        let planned: Double = switch goals.weight {
        case .lose: -goals.weeklyRatePercent
        case .gain: goals.weeklyRatePercent
        case .maintain: 0
        }
        var reason: Reason
        var guarded = false
        if percent < -maxLossPercentPerWeek {
            delta = max(delta, maxWeeklyStepKcal)
            reason = .losingTooFast
            guarded = true
        } else if percent > max(maxGainPercentPerWeek, goals.weight == .gain ? goals.weeklyRatePercent : 0) + 0.1 {
            // +0.1 point of slack: the weekly trend from a handful of weigh-ins is noisy.
            delta = min(delta, -maxWeeklyStepKcal)
            reason = .gainingTooFast
            guarded = true
        } else {
            switch goals.weight {
            case .maintain:
                reason = percent > 0.1 ? .driftingUp : (percent < -0.1 ? .driftingDown : .maintenanceChanged)
            case .lose:
                // Losing less than planned (percent is less negative) → slower.
                reason = percent > planned + 0.1 ? .slowerThanPlanned : (percent < planned - 0.1 ? .fasterThanPlanned : .maintenanceChanged)
            case .gain:
                reason = percent < planned - 0.1 ? .slowerThanPlanned : (percent > planned + 0.1 ? .fasterThanPlanned : .maintenanceChanged)
            }
        }
        delta = min(maxWeeklyStepKcal, max(-maxWeeklyStepKcal, delta))
        delta = (delta / 10).rounded() * 10
        guard guarded || abs(delta) >= minimumStepKcal else { return nil }
        let floor = GoalPlanner.calorieFloor(sex: sex)
        let newTarget = max(floor, currentTarget + delta)
        let applied = newTarget - currentTarget
        guard applied != 0 else { return nil }
        return Adjustment(deltaKcal: applied, newTarget: newTarget, reason: reason)
    }
}
