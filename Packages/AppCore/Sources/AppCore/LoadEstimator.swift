import Foundation

/// A starting weight for an exercise you haven't logged yet, so the first
/// session doesn't start from "pick a weight".
///
/// The estimate comes from, in order:
/// 1. Another exercise for the same movement you have done (dumbbell bench
///    from barbell bench, leg press from back squat), through a ratio table.
/// 2. Your best estimated 1RM on a related movement (incline press from flat
///    press, lunge from squat, pulldown from row), through a second table.
/// 3. Numbers you typed in ("Know your numbers?": your 5-rep bench, squat,
///    deadlift or overhead press; `Lifter.anchorOneRepMaxKg`).
/// 4. Your body weight, scaled for sex, training status and age, from
///    crowd-sourced strength standards.
///
/// Every ratio here is a population average from coaching tables (ExRx.net,
/// Symmetric Strength and Strength Level strength standards; common
/// lift-ratio guides), not from a study, and the spread between people is
/// wide: limb lengths, past sport and technique move the ratios a lot. So
/// the result is an app estimate for the middle of the rep range, cut a
/// little (`historyFraction` from your own lifts, `conservativeFraction`
/// from body weight) and rounded down to what the gym can load, and the UI
/// says to adjust after the first set. An earlier version took the top of
/// the range, the "untrained" column for everyone and an 85% cut on top:
/// about half of a trained lifter's working weight (audit 2026-11 §1).
public enum LoadEstimator {
    /// What the body-weight fallback needs to know about you.
    public struct Lifter: Sendable, Equatable {
        public var bodyMassKg: Double?
        public var sex: BiologicalSex
        public var status: TrainingStatus
        /// Age in years, if known: older lifters start lower (`ageFactor`).
        public var age: Int?
        /// 1RMs you told the app (in kg), by the slot's reference lift
        /// (`anchors(fiveRepMaxKg:)`). Beats the body-weight tables.
        public var anchorOneRepMaxKg: [MovementSlot: Double]

        public init(bodyMassKg: Double? = nil, sex: BiologicalSex = .male, status: TrainingStatus = .novice,
                    age: Int? = nil, anchorOneRepMaxKg: [MovementSlot: Double] = [:]) {
            self.bodyMassKg = bodyMassKg
            self.sex = sex
            self.status = status
            self.age = age
            self.anchorOneRepMaxKg = anchorOneRepMaxKg
        }

        /// No body weight: only history-based estimates are possible.
        public static let unknown = Lifter()
    }

    public struct Estimate: Sendable, Equatable {
        /// Working load in the gym's unit (per hand for dumbbells), already
        /// cut (`historyFraction` / `conservativeFraction`) and rounded to a
        /// load the gym can make.
        public var load: Double
        /// "your Bench Press" or "your body weight".
        public var source: String
        /// The weight the estimate asked for before rounding to the gym's
        /// loads. Far under `load` means the lightest load the gym has is
        /// too heavy for you (an empty bar for a light curl).
        public var target: Double
        /// The reps the load is estimated for: the middle of the range.
        public var reps: Int

        public init(load: Double, source: String, target: Double? = nil, reps: Int = 0) {
            self.load = load
            self.source = source
            self.target = target ?? load
            self.reps = reps
        }

        /// The note shown under the load in the plan.
        public var note: String { "Estimated from \(source): start here and adjust after set 1" }
    }

    /// From body weight, start at 85% of the estimate: the tables are
    /// population averages, and a first set that is too light costs one set
    /// while one that is too heavy costs form and the rest of the session.
    /// Also used for untrained lifters and from age 60 (Fragala et al., NSCA
    /// position statement, J Strength Cond Res 2019: start older adults
    /// conservatively). App choice.
    public static let conservativeFraction = 0.85
    /// From your own logged lifts (or numbers you typed in), 90%: the ratio
    /// tables are still averages, but your own 1RM is much closer. App choice
    /// (audit 2026-11 §1).
    public static let historyFraction = 0.9

    /// Age from which the body-weight tables are scaled down, and the cut-off
    /// for the conservative start. Muscle strength falls about 1-2% a year
    /// from around age 50 and faster after 70 (Keller & Engelhardt, Muscles
    /// Ligaments Tendons J 2013;3:346, review; Fragala et al. 2019). The steps are
    /// the app's rounding of that decline, not a table from a study.
    public static func ageFactor(_ age: Int?) -> Double {
        guard let age else { return 1 }
        switch age {
        case ..<40: return 1
        case 40..<50: return 0.95
        case 50..<60: return 0.88
        case 60..<70: return 0.8
        default: return 0.7
        }
    }

    /// The reps the starting weight is estimated for: the middle of the
    /// range, rounded up (8 for 6-10, 10 for 8-12). Estimating for the top of
    /// the range on top of the other cuts started lifters far too light.
    public static func estimateReps(_ reps: ClosedRange<Int>) -> Int {
        (reps.lowerBound + reps.upperBound + 1) / 2
    }

    /// 1RMs (kg) by slot from 5-rep maxes you know, in kg: Epley (1 + 5/30)
    /// for the 1RM; the hinge slot's reference is the Romanian deadlift, about
    /// 0.8 × a conventional deadlift (coaching ratio; wide spread).
    public static func anchors(benchKg: Double? = nil, squatKg: Double? = nil, deadliftKg: Double? = nil,
                               pressKg: Double? = nil) -> [MovementSlot: Double] {
        var result: [MovementSlot: Double] = [:]
        func oneRM(_ fiveRM: Double?) -> Double? {
            guard let fiveRM, fiveRM.isFinite, fiveRM > 0 else { return nil }
            return fiveRM * (1 + 5.0 / 30)
        }
        if let bench = oneRM(benchKg) { result[.horizontalPress] = bench }
        if let squat = oneRM(squatKg) { result[.squat] = squat }
        if let deadlift = oneRM(deadliftKg) { result[.hinge] = deadlift * 0.8 }
        if let press = oneRM(pressKg) { result[.verticalPress] = press }
        return result
    }

    /// A working weight for `exerciseID` from your other lifts, numbers you
    /// gave, or your body weight, for the middle of `reps` (`estimateReps`)
    /// at the effort `rpe` asks. Nil for bodyweight exercises, exercises
    /// outside the catalog, and when there's nothing to estimate from.
    public static func estimate(
        exerciseID: String,
        reps: ClosedRange<Int>,
        rpe: Double,
        history: [String: ExerciseHistory],
        lifter: Lifter,
        gym: GymProfile
    ) -> Estimate? {
        guard let exercise = ExerciseCatalog.exercise(id: exerciseID), let kind = exercise.load,
              let slot = ExerciseCatalog.slot(for: exerciseID),
              let factor = exerciseFactor(exerciseID), factor > 0 else { return nil }
        let reference: (oneRepMax: Double, source: String)
        var cut = historyFraction
        if let same = referenceOneRepMax(slot: slot, excluding: exerciseID, history: history) {
            reference = same
        } else if let related = relatedReference(for: slot, history: history) {
            reference = related
        } else if let anchored = anchorReference(for: slot, lifter: lifter, unit: gym.unit) {
            reference = anchored
        } else if let mass = lifter.bodyMassKg, mass.isFinite, mass > 0,
                  let fraction = bodyweightFraction(slot: slot, sex: lifter.sex, status: lifter.status) {
            let standard = gym.unit.fromKilograms(mass) * fraction * ageFactor(lifter.age)
            reference = (standard, "your body weight")
            cut = conservativeFraction
        } else {
            return nil
        }
        // Untrained lifters and those 60 and over always start at the conservative cut.
        if lifter.status == .untrained || (lifter.age ?? 0) >= 60 { cut = min(cut, conservativeFraction) }
        let oneRepMax = reference.oneRepMax * factor
        guard oneRepMax.isFinite, oneRepMax > 0 else { return nil }
        // Same Epley step as `WorkoutPlanner.progression`: the load for the
        // middle of the rep range with the reps in reserve the effort asks for.
        let count = estimateReps(reps)
        let effectiveReps = Double(count) + max(0, 10 - rpe)
        let target = oneRepMax / (1 + effectiveReps / 30) * cut
        guard let load = gym.load(atMost: target, on: kind) else { return nil }
        return Estimate(load: load, source: reference.source, target: target, reps: count)
    }

    // MARK: Tables

    /// Each exercise's working load as a fraction of its movement's reference
    /// lift (the barbell or main machine version). Dumbbell and kettlebell
    /// values are per hand: two dumbbells carry about 80% of the barbell
    /// load, so 0.4 each. Coaching rules of thumb; wide spread. Nil for
    /// bodyweight exercises and anything outside the table.
    static func exerciseFactor(_ exerciseID: String) -> Double? {
        exerciseFactors[exerciseID]
    }

    static let exerciseFactors: [String: Double] = [
        // Horizontal press (reference: barbell bench press).
        "Barbell_Bench_Press_-_Medium_Grip": 1.0, "Dumbbell_Bench_Press": 0.4,
        "Leverage_Chest_Press": 0.9, "Smith_Machine_Bench_Press": 0.95,
        // Incline press (reference: barbell incline press).
        "Barbell_Incline_Bench_Press_-_Medium_Grip": 1.0, "Incline_Dumbbell_Press": 0.4,
        // Vertical press (reference: standing barbell press).
        "Standing_Military_Press": 1.0, "Dumbbell_Shoulder_Press": 0.4,
        "Machine_Shoulder_Military_Press": 0.9, "Two-Arm_Kettlebell_Military_Press": 0.4,
        // Chest fly (reference: cable fly stack).
        "Cable_Crossover": 1.0, "Butterfly": 1.0, "Dumbbell_Flyes": 0.35,
        // Lateral raise (reference: dumbbell, per hand).
        "Side_Lateral_Raise": 1.0, "Cable_Seated_Lateral_Raise": 1.0,
        // Triceps (reference: cable overhead extension).
        "Cable_Rope_Overhead_Triceps_Extension": 1.0, "Dumbbell_One-Arm_Triceps_Extension": 0.5,
        "Triceps_Pushdown_-_Rope_Attachment": 1.0, "EZ-Bar_Skullcrusher": 1.0,
        // Vertical pull (reference: lat pulldown stack).
        "Wide-Grip_Lat_Pulldown": 1.0,
        // Horizontal row (reference: barbell row).
        "Bent_Over_Barbell_Row": 1.0, "Seated_Cable_Rows": 1.0, "One-Arm_Dumbbell_Row": 0.4, "Leverage_Iso_Row": 1.0,
        // Rear delt (reference: face pull stack).
        "Face_Pull": 1.0, "Reverse_Flyes": 0.25,
        // Biceps (reference: barbell curl).
        "Barbell_Curl": 1.0, "Dumbbell_Bicep_Curl": 0.45, "EZ-Bar_Curl": 1.0, "Machine_Bicep_Curl": 1.0,
        // Hammer curl (reference: dumbbell, per hand; the rope is held in both hands).
        "Hammer_Curls": 1.0, "Cable_Hammer_Curls_-_Rope_Attachment": 1.8,
        // Squat (reference: back squat). Leg press sled loads run well above
        // the squat (no trunk to stabilise); 1.6 is the conservative end.
        "Barbell_Squat": 1.0, "Leg_Press": 1.6, "Goblet_Squat": 0.3, "Dumbbell_Squat": 0.3,
        // Hinge (reference: barbell Romanian deadlift).
        "Romanian_Deadlift": 1.0, "Stiff-Legged_Dumbbell_Deadlift": 0.4, "One-Arm_Kettlebell_Swings": 0.25,
        // Single leg (reference: barbell lunge).
        "Barbell_Lunge": 1.0, "Split_Squat_with_Dumbbells": 0.4,
        // Leg curl / extension / calves (machine stacks; brands differ a lot).
        "Seated_Leg_Curl": 1.0, "Lying_Leg_Curls": 1.0,
        "Leg_Extensions": 1.0,
        "Standing_Calf_Raises": 1.0, "Calf_Raise_On_A_Dumbbell": 0.3,
        // Core.
        "Cable_Crunch": 1.0,
        // Staples added in 2026-11 (audit §12), same references as their slot.
        "Barbell_Deadlift": 1.25,           // ≈ RDL / 0.8
        "Hack_Squat": 1.1, "Smith_Machine_Squat": 0.9,
        "Dumbbell_Incline_Row": 0.4, "Lying_T-Bar_Row": 0.9,
        "Incline_Dumbbell_Curl": 0.35, "Machine_Preacher_Curls": 0.9,
        "Seated_Calf_Raise": 0.8,
        "Close-Grip_Barbell_Bench_Press": 3.0, // triceps reference ≈ 0.3 × bench
        "Machine_Triceps_Extension": 1.0,
        "Reverse_Machine_Flyes": 1.0,
        "Dumbbell_Lunges": 0.35,
        // Hip thrust (reference: barbell hip thrust).
        "Barbell_Hip_Thrust": 1.0, "Barbell_Glute_Bridge": 0.9, "Pull_Through": 0.3,
        // Pain regressions (`PainGuard.regressionTable`), against their slot's reference.
        "Dumbbell_Bench_Press_with_Neutral_Grip": 0.4, "Dumbbell_Floor_Press": 0.35, "Floor_Press": 0.85,
        "Hammer_Grip_Incline_DB_Bench_Press": 0.4,
        "Box_Squat": 0.85
    ]

    /// Related movements to borrow from, best first, with the ratio of this
    /// slot's reference 1RM to theirs (incline ≈ 0.8 × flat bench, overhead
    /// press ≈ 0.6 × bench, pulldown ≈ 0.9 × row, lunge ≈ 0.5 × squat …).
    /// Common strength-standard ratios (ExRx.net, Symmetric Strength): coaching
    /// tables, not studies, rounded to the conservative side. One hop only.
    static let relatedSlots: [MovementSlot: [(slot: MovementSlot, ratio: Double)]] = [
        .inclinePress: [(.horizontalPress, 0.8), (.verticalPress, 1.2)],
        .horizontalPress: [(.inclinePress, 1.2), (.verticalPress, 1.5)],
        .verticalPress: [(.horizontalPress, 0.6), (.inclinePress, 0.7)],
        .chestFly: [(.horizontalPress, 0.3)],
        .lateralRaise: [(.verticalPress, 0.2)],
        .triceps: [(.horizontalPress, 0.3)],
        .verticalPull: [(.horizontalRow, 0.9)],
        .horizontalRow: [(.verticalPull, 1.0)],
        .rearDelt: [(.horizontalRow, 0.4)],
        .biceps: [(.horizontalRow, 0.4), (.verticalPull, 0.4)],
        .hammerCurl: [(.biceps, 0.45)],
        .squat: [(.hinge, 0.9)],
        .hinge: [(.squat, 0.9)],
        .singleLeg: [(.squat, 0.5)],
        .legCurl: [(.hinge, 0.4), (.squat, 0.35)],
        .legExtension: [(.squat, 0.5)],
        .calves: [(.squat, 0.8)],
        .hipThrust: [(.squat, 1.0), (.hinge, 1.1)]
    ]

    /// 1RM as a fraction of body weight for the slot's reference lift, by
    /// training status (untrained, novice, intermediate, advanced), for men.
    /// From the crowd-sourced strength standards of ExRx.net, Symmetric
    /// Strength and Strength Level (bench about 0.7 / 1.0 / 1.3 / 1.5 × body
    /// weight, squat 0.9 / 1.3 / 1.7 / 2.1, deadlift 1.1 / 1.6 / 2.0 / 2.5):
    /// coaching tables, not studies, with a wide spread between people.
    /// Accessory lifts follow common lift ratios. Women: about 0.6 × the
    /// men's figure on upper-body lifts and 0.75 × on lower-body lifts (the
    /// same tables; relative gains are similar between sexes: Roberts,
    /// Nuckols & Krieger, J Strength Cond Res 2020). Nil where no standard exists.
    static func bodyweightFraction(slot: MovementSlot, sex: BiologicalSex, status: TrainingStatus) -> Double? {
        let male: [Double]
        switch slot {
        case .squat: male = [0.9, 1.3, 1.7, 2.1]
        case .hinge: male = [0.9, 1.25, 1.6, 2.0]   // Romanian deadlift ≈ 0.8 × deadlift
        case .horizontalPress: male = [0.7, 1.0, 1.3, 1.5]
        case .inclinePress: male = [0.55, 0.8, 1.05, 1.2]   // ≈ 0.8 × flat bench
        case .verticalPress: male = [0.45, 0.6, 0.8, 1.0]
        case .horizontalRow: male = [0.6, 0.85, 1.1, 1.3]
        case .verticalPull: male = [0.55, 0.75, 1.0, 1.2]   // pulldown ≈ 0.9 × row
        case .singleLeg: male = [0.45, 0.65, 0.85, 1.05]   // barbell lunge ≈ 0.5 × squat
        case .biceps: male = [0.3, 0.4, 0.55, 0.7]
        case .legExtension: male = [0.5, 0.65, 0.85, 1.05]
        case .legCurl: male = [0.35, 0.5, 0.65, 0.8]
        case .hipThrust: male = [0.9, 1.3, 1.8, 2.3]   // hip thrusts run above the squat
        // Small lifts: rough coaching ratios (per hand for dumbbells; cable and
        // machine stacks differ a lot by brand), so a new lifter's first set
        // has a number instead of "pick a weight". Low end on purpose.
        case .lateralRaise: male = [0.06, 0.09, 0.12, 0.15]
        case .hammerCurl: male = [0.1, 0.14, 0.18, 0.22]
        case .triceps: male = [0.2, 0.3, 0.4, 0.5]
        case .rearDelt: male = [0.2, 0.3, 0.4, 0.5]
        case .chestFly: male = [0.2, 0.3, 0.4, 0.5]
        case .calves: male = [0.6, 0.9, 1.2, 1.5]
        default: return nil
        }
        let index = switch status {
        case .untrained: 0
        case .novice: 1
        case .intermediate: 2
        case .advanced: 3
        }
        guard sex == .female else { return male[index] }
        let lower: Set<MovementSlot> = [.squat, .hinge, .singleLeg, .legExtension, .legCurl, .hipThrust, .calves]
        return male[index] * (lower.contains(slot) ? 0.75 : 0.6)
    }

    /// The untrained column (`bodyweightFraction(slot:sex:status:)`).
    static func bodyweightFraction(slot: MovementSlot, sex: BiologicalSex) -> Double? {
        bodyweightFraction(slot: slot, sex: sex, status: .untrained)
    }

    // MARK: Lookups

    /// The slot's reference 1RM from an exercise in it you have done (catalog
    /// order, best first), with the exercise named for the note.
    static func referenceOneRepMax(slot: MovementSlot, excluding exerciseID: String?,
                                   history: [String: ExerciseHistory]) -> (oneRepMax: Double, source: String)? {
        for exercise in ExerciseCatalog.options[slot] ?? [] where exercise.id != exerciseID {
            guard let past = history[exercise.id], past.bestEstimatedOneRepMax > 0,
                  let factor = exerciseFactor(exercise.id), factor > 0 else { continue }
            return (past.bestEstimatedOneRepMax / factor, "your \(exercise.name)")
        }
        return nil
    }

    /// The slot's reference 1RM borrowed from a related slot you have history in.
    static func relatedReference(for slot: MovementSlot,
                                 history: [String: ExerciseHistory]) -> (oneRepMax: Double, source: String)? {
        for related in relatedSlots[slot] ?? [] {
            if let reference = referenceOneRepMax(slot: related.slot, excluding: nil, history: history) {
                return (reference.oneRepMax * related.ratio, reference.source)
            }
        }
        return nil
    }

    /// The slot's reference 1RM, in the gym's unit, from numbers you typed in
    /// (`Lifter.anchorOneRepMaxKg`): the slot's own, else a related slot's
    /// through `relatedSlots`.
    static func anchorReference(for slot: MovementSlot, lifter: Lifter, unit: LoadUnit) -> (oneRepMax: Double, source: String)? {
        func usable(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return unit.fromKilograms(value)
        }
        if let own = usable(lifter.anchorOneRepMaxKg[slot]) { return (own, "the numbers you gave") }
        for related in relatedSlots[slot] ?? [] {
            if let value = usable(lifter.anchorOneRepMaxKg[related.slot]) {
                return (value * related.ratio, "the numbers you gave")
            }
        }
        return nil
    }
}
