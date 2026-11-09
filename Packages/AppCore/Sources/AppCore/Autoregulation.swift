import Foundation

/// Set-by-set effort autoregulation: after a working set, the logged RPE is
/// compared with the plan's reps-in-reserve (RIR) target and the next set's
/// load moves one gym jump when the gap is clear.
///
/// Evidence: RIR/RPE-based autoregulation gives about the same strength and
/// muscle gains as fixed percentage loading (Hickmott LM, Chilibeck PD, Shaw
/// KA, Butcher SJ. The effect of load and volume autoregulation on muscular
/// strength and hypertrophy: a systematic review and meta-analysis. Sports Med
/// Open 2022;8:9), so this is a convenience that keeps the effort on plan, not
/// a gains claim. Lifters misjudge reps left by about one rep, more on
/// high-rep sets (Halperin I, Malleron T, Har-Nir I, et al. Accuracy in
/// predicting repetitions to task failure in resistance exercise: a scoping
/// review and exploratory meta-analysis. Sports Med 2022;52:377-390), hence the
/// one-rep tolerance band (1.5 reps on sets over 12) and no adjustment on sets
/// over 20 reps. Noisy RPE can make the load whipsaw, so it changes at most
/// once per exercise per session. The first working set moves only on a
/// clear miss (`firstSetGap`), or at the normal trigger when the weight was
/// an estimate (`firstSetCanAdjust`): that's when the first set says most
/// (audit 2026-11 §2; docs/research/lifting-features.md §3.2).
public enum Autoregulation {
    /// A gap of up to this many reps between the reps you had left and the
    /// target counts as on plan (Halperin et al., Sports Med 2022: ~1 rep error).
    public static let toleranceReps = 1.0
    /// A gap of this many reps or more moves the next set (Halperin et al. 2022;
    /// feature spec §3.2).
    public static let triggerReps = 2.0
    /// Reps-left estimates get worse as sets get longer, so sets over this
    /// many reps never trigger a change (Halperin et al., Sports Med 2022).
    /// Was 12, which ruled out every 10-15 small-lift set.
    public static let maxReps = 20
    /// Above this many reps the tolerance widens to `longSetToleranceReps`
    /// (Halperin et al. 2022: errors grow with reps).
    public static let longSetReps = 12
    public static let longSetToleranceReps = 1.5
    /// A gap this big moves even the first working set, and by up to two
    /// jumps: three reps is well past the ~1-rep guessing error (Halperin
    /// et al. 2022). App choice.
    public static let firstSetGap = 3.0
    /// One jump down (or up) of more than this share of the load is too coarse
    /// for a one-set correction: two reps in reserve is only about 7% of the
    /// load by the Epley formula (≈3.3% a rep). Reps change instead. Same
    /// ceiling as the planner's routine jump (ACSM position stand, Med Sci
    /// Sports Exerc 2009: add 2-10% at a time).
    public static let maxJumpFraction = WorkoutPlanner.routineJumpFraction

    public enum Change: String, Codable, Sendable, Equatable {
        /// Within the tolerance: the next set stays as planned.
        case hold
        /// Fresher than planned: one gym jump heavier.
        case loadUp
        /// Harder than planned: one gym jump lighter.
        case loadDown
        /// Harder than planned and the next lighter weight is a big jump: fewer reps.
        case trimReps
        /// Fresher than planned and the next heavier weight is a big jump: more reps.
        case addReps
    }

    public struct Suggestion: Sendable, Equatable {
        public var change: Change
        /// Next set's load, in the gym's unit (per hand for dumbbells).
        public var load: Double
        /// Next set's reps.
        public var reps: Int
        /// Reps the logged set had left (10 − RPE).
        public var repsInReserve: Double
        /// The plan's target reps in reserve.
        public var targetRIR: Double

        public init(change: Change, load: Double, reps: Int, repsInReserve: Double, targetRIR: Double) {
            self.change = change
            self.load = load
            self.reps = reps
            self.repsInReserve = repsInReserve
            self.targetRIR = targetRIR
        }

        /// "Next set 62.5 kg (you had 3 in reserve)"; nil for `hold`. Reps in
        /// reserve are written by `ReserveText`, as everywhere on the phone.
        public func message(unit: String) -> String? {
            let had = repsInReserve < 0.25 ? "you went to failure" : "you had \(ReserveText.text(repsInReserve))"
            let plan = "plan: \(ReserveText.text(targetRIR))"
            switch change {
            case .hold:
                return nil
            case .loadUp:
                return "Next set \(Autoregulation.format(load)) \(unit) (\(had))"
            case .loadDown:
                return "Next set \(Autoregulation.format(load)) \(unit) (\(had); \(plan))"
            case .trimReps:
                return "Next set \(reps) reps, same weight (\(had); \(plan))"
            case .addReps:
                return "Next set \(reps) reps, same weight (\(had))"
            }
        }
    }

    /// The next working set after one you just logged, or nil when the rules
    /// don't apply: no RPE logged, no reps, more than `maxReps` reps, a change
    /// already made for this exercise this session, or the first working set
    /// (`setNumber` 1) with a gap under `firstSetGap` (unless
    /// `firstSetCanAdjust`: the weight was an estimate or the lift has fewer
    /// than three logged sessions). `logged.weight` is in the gym's unit;
    /// `kind` is the equipment the load is on (nil for bodyweight, where only
    /// reps move). A gap of `firstSetGap` or more moves up to two jumps.
    public static func nextSet(
        after logged: LiftProgress.LoggedSet,
        setNumber: Int,
        targetRIR: Double,
        alreadyAdjusted: Bool,
        kind: EquipmentKind?,
        gym: GymProfile,
        firstSetCanAdjust: Bool = false
    ) -> Suggestion? {
        guard setNumber >= 1, !alreadyAdjusted, let rpe = logged.rpe, rpe.isFinite,
              logged.reps > 0, logged.reps <= maxReps else { return nil }
        let reserve = max(0, 10 - rpe)
        let gap = reserve - targetRIR
        if setNumber == 1, !firstSetCanAdjust, abs(gap) < firstSetGap - 0.001 { return nil }
        var suggestion = Suggestion(change: .hold, load: logged.weight, reps: logged.reps,
                                    repsInReserve: reserve, targetRIR: targetRIR)
        let tolerance = logged.reps > longSetReps ? longSetToleranceReps : toleranceReps
        let trigger = triggerReps + (tolerance - toleranceReps)
        if gap >= trigger - 0.001 {
            if var next = heavier(than: logged.weight, kind: kind, gym: gym) {
                // A clear miss: a second jump, if that one is small too.
                if gap >= firstSetGap - 0.001, let second = heavier(than: next, kind: kind, gym: gym) { next = second }
                suggestion.change = .loadUp
                suggestion.load = next
            } else {
                let reps = min(maxReps, logged.reps + repChange(for: gap, tolerance: tolerance))
                if reps > logged.reps {
                    suggestion.change = .addReps
                    suggestion.reps = reps
                }
            }
        } else if gap <= -trigger + 0.001 {
            if let lighter = lighter(than: logged.weight, kind: kind, gym: gym) {
                suggestion.change = .loadDown
                suggestion.load = lighter
            } else {
                let reps = max(1, logged.reps - repChange(for: -gap, tolerance: tolerance))
                if reps < logged.reps {
                    suggestion.change = .trimReps
                    suggestion.reps = reps
                }
            }
        }
        return suggestion
    }

    /// Reps to add or trim to land back inside the band: the gap past the tolerance, at least 1.
    static func repChange(for gap: Double, tolerance: Double = toleranceReps) -> Int {
        guard gap.isFinite else { return 1 }
        return max(1, Int(min(50, gap - tolerance).rounded(.down)))
    }

    /// One jump heavier, if the gym has one that isn't a big jump.
    static func heavier(than weight: Double, kind: EquipmentKind?, gym: GymProfile) -> Double? {
        guard let kind, weight > 0, let next = gym.nextLoad(above: weight, on: kind),
              (next - weight) / weight <= maxJumpFraction + 0.0001 else { return nil }
        return next
    }

    /// One jump lighter, if the gym has one that isn't a big jump.
    static func lighter(than weight: Double, kind: EquipmentKind?, gym: GymProfile) -> Double? {
        guard let kind, weight > 0,
              let lower = gym.achievableLoads(for: kind).last(where: { $0 < weight - 0.001 }),
              (weight - lower) / weight <= maxJumpFraction + 0.0001 else { return nil }
        return lower
    }

    /// "3", "2.5" or "none".
    static func reserveText(_ reps: Double) -> String {
        reps < 0.25 ? "none" : format(reps)
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// How a lift moves forward from session to session. Adding load and adding
/// reps both built muscle and strength similarly over 8 weeks (Plotkin D, et
/// al. Progressive overload without progressing load? The effects of load or
/// repetition progression on muscular adaptations. PeerJ 2022;10:e14142), so
/// the choice is about equipment: barbells move in small jumps, light
/// dumbbells and coarse stacks don't. Adding sets is the volume route
/// (more weekly sets, more growth up to a point: Pelland et al., Sports Med
/// 2026); it's offered as your own choice, not a default: the weekly set
/// targets (`VolumeProgression`) already add sets, and set progression
/// defaulted on isolation lifts never added weight once they fixed the sets
/// (audit 2026-11 §5).
public enum ProgressionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case load, reps, sets

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .load: "Load"
        case .reps: "Reps"
        case .sets: "Sets"
        }
    }

    /// One plain line on what the planner does.
    public var summary: String {
        switch self {
        case .load: "Add weight once you reach the top of the rep range."
        case .reps: "Keep the weight and add a rep each time; move up once you're 2 past the range."
        case .sets: "Keep the weight and add a set each time you reach the top of the range, up to 5; then move up."
        }
    }

    /// The default when you haven't picked one: load for barbell-type lifts;
    /// reps for bodyweight and for equipment whose next jump is big (over 10%,
    /// ACSM 2009); load otherwise. `compound` no longer changes it (isolation
    /// work used to default to sets).
    public static func suggested(kind: EquipmentKind?, compound: Bool, bigJump: Bool) -> ProgressionMode {
        switch kind {
        case .barbell, .ezBar, .smithMachine: return .load
        case nil, .bodyweight, .bands, .pullUpBar, .dipStation: return .reps
        default: break
        }
        return bigJump ? .reps : .load
    }
}
