import Foundation

/// A starting weight for an exercise you haven't logged yet, so the first
/// session doesn't start from "pick a weight".
///
/// The estimate comes from, in order:
/// 1. Another exercise for the same movement you have done (dumbbell bench
///    from barbell bench, leg press from back squat), through a ratio table.
/// 2. Your best estimated 1RM on a related movement (incline press from flat
///    press, lunge from squat, pulldown from row), through a second table.
/// 3. Your body weight, scaled for sex and how long you've trained, from
///    beginner strength standards.
///
/// Every ratio here is a population average from coaching tables (ExRx.net
/// and Symmetric Strength strength standards; common lift-ratio guides), not
/// from a study, and the spread between people is wide: limb lengths, past
/// sport and technique move the ratios a lot. So the result is an app
/// estimate, cut to 85% (`conservativeFraction`) and rounded down to what
/// the gym can load, and the UI says to adjust after the first set. Starting
/// light also follows the ACSM's advice to progress by small steps (position
/// stand, Med Sci Sports Exerc 2009).
public enum LoadEstimator {
    /// What the body-weight fallback needs to know about you.
    public struct Lifter: Sendable, Equatable {
        public var bodyMassKg: Double?
        public var sex: BiologicalSex
        public var status: TrainingStatus

        public init(bodyMassKg: Double? = nil, sex: BiologicalSex = .male, status: TrainingStatus = .novice) {
            self.bodyMassKg = bodyMassKg
            self.sex = sex
            self.status = status
        }

        /// No body weight: only history-based estimates are possible.
        public static let unknown = Lifter()
    }

    public struct Estimate: Sendable, Equatable {
        /// Working load in the gym's unit (per hand for dumbbells), already
        /// cut to 85% and rounded to a load the gym can make.
        public var load: Double
        /// "your Bench Press" or "your body weight".
        public var source: String

        public init(load: Double, source: String) {
            self.load = load
            self.source = source
        }

        /// The note shown under the load in the plan.
        public var note: String { "Estimated from \(source): start here and adjust after set 1" }
    }

    /// Start at 85% of the estimate: a first set that is too light costs one
    /// set, one that is too heavy costs form and the rest of the session.
    /// App choice.
    public static let conservativeFraction = 0.85

    /// How far above beginner standards a lifter of each status starts. The
    /// steps (×1.3, ×1.6) are the app's rounding of the gap between the
    /// untrained and intermediate columns of the ExRx / Symmetric Strength
    /// tables; the tables themselves are coaching standards, not studies.
    public static func statusMultiplier(_ status: TrainingStatus) -> Double {
        switch status {
        case .untrained, .novice: 1.0
        case .intermediate: 1.3
        case .advanced: 1.6
        }
    }

    /// A working weight for `exerciseID` from your other lifts, or from your
    /// body weight. Nil for bodyweight exercises, exercises outside the
    /// catalog, and when there's nothing to estimate from.
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
              let factor = exerciseFactor(exerciseID) else { return nil }
        let reference: (oneRepMax: Double, source: String)
        if let same = referenceOneRepMax(slot: slot, excluding: exerciseID, history: history) {
            reference = same
        } else if let related = relatedReference(for: slot, history: history) {
            reference = related
        } else if let mass = lifter.bodyMassKg, mass > 0,
                  let fraction = bodyweightFraction(slot: slot, sex: lifter.sex) {
            let standard = gym.unit.fromKilograms(mass) * fraction * statusMultiplier(lifter.status)
            reference = (standard, "your body weight")
        } else {
            return nil
        }
        let oneRepMax = reference.oneRepMax * factor
        // Same Epley-style step as `WorkoutPlanner.suggestedLoad`: the load for
        // the top of the rep range with the reps in reserve the effort asks for.
        let effectiveReps = Double(reps.upperBound) + max(0, 10 - rpe)
        let target = oneRepMax / (1 + effectiveReps / 30) * conservativeFraction
        guard let load = gym.load(atMost: target, on: kind) else { return nil }
        return Estimate(load: load, source: reference.source)
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
        "Cable_Crunch": 1.0
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
        .calves: [(.squat, 0.8)]
    ]

    /// Beginner 1RM as a fraction of body weight for the slot's reference lift,
    /// from the "untrained" column of ExRx.net / Symmetric Strength strength
    /// standards (squat ~0.75, bench ~0.5, deadlift ~1.0, press ~0.35 for
    /// men; women about two thirds of that). Coaching tables with wide
    /// variation, rounded down; nil where no standard exists.
    static func bodyweightFraction(slot: MovementSlot, sex: BiologicalSex) -> Double? {
        let standard: (male: Double, female: Double)
        switch slot {
        case .squat: standard = (0.75, 0.5)
        case .hinge: standard = (0.9, 0.6)   // a Romanian deadlift sits under the 1.0 × BW deadlift standard
        case .horizontalPress: standard = (0.5, 0.3)
        case .inclinePress: standard = (0.4, 0.25)
        case .verticalPress: standard = (0.35, 0.2)
        case .horizontalRow: standard = (0.5, 0.3)
        case .verticalPull: standard = (0.5, 0.35)
        case .singleLeg: standard = (0.4, 0.25)
        case .biceps: standard = (0.25, 0.15)
        case .legExtension: standard = (0.5, 0.35)
        case .legCurl: standard = (0.35, 0.25)
        default: return nil
        }
        return sex == .female ? standard.female : standard.male
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
}
