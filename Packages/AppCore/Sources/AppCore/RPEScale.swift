import Foundation

/// The RPE (rate of perceived exertion) scale for a set, defined by reps in
/// reserve: how many more reps you could have done with good form. This is
/// the RIR-based scale used in strength research (Zourdos et al., J Strength
/// Cond Res 2016; Helms et al., Strength Cond J 2016).
///
/// Session RPE (rating the whole workout when you finish) uses the same 1-10
/// numbers but means overall difficulty (Foster et al., J Strength Cond Res 2001).
public enum RPEScale {
    public struct Level: Sendable, Equatable, Identifiable {
        public var rpe: Double
        public var repsLeft: String
        public var title: String
        public var feel: String
        public var id: Double { rpe }
    }

    public static let levels: [Level] = [
        Level(rpe: 10, repsLeft: "0", title: "Max effort", feel: "No more reps possible, and you couldn't have added weight."),
        Level(rpe: 9.5, repsLeft: "0", title: "Near max", feel: "No more reps, but you could have added a little weight."),
        Level(rpe: 9, repsLeft: "1", title: "Very hard", feel: "One more rep was possible. Bar speed slows a lot."),
        // Half steps get a "+" so no two rows read the same.
        Level(rpe: 8.5, repsLeft: "1-2", title: "Hard+", feel: "Definitely one more, maybe two."),
        Level(rpe: 8, repsLeft: "2", title: "Hard", feel: "Two more reps left. A typical working set."),
        Level(rpe: 7.5, repsLeft: "2-3", title: "Challenging+", feel: "Definitely two more, maybe three."),
        Level(rpe: 7, repsLeft: "3", title: "Challenging", feel: "Three more reps possible. Fast, controlled reps."),
        Level(rpe: 6, repsLeft: "4", title: "Moderate", feel: "Four more reps. Good for technique and lighter days."),
        Level(rpe: 5, repsLeft: "5+", title: "Easy", feel: "Warm-up weight; could do many more."),
    ]

    public static func level(for rpe: Double) -> Level? {
        levels.min { abs($0.rpe - rpe) < abs($1.rpe - rpe) }
    }

    /// e.g. "2 reps left · RPE 8": the reps left lead, RPE is the secondary
    /// label (`ReserveText`), so the plain words come first everywhere.
    public static func summary(_ rpe: Double) -> String {
        guard let level = level(for: rpe) else { return "RPE \(rpe.formatted())" }
        let reps = level.repsLeft == "1" ? "1 rep left" : "\(level.repsLeft) reps left"
        return "\(reps) · RPE \(rpe.formatted())"
    }

    /// Whole-workout difficulty for the finish screen: the verbal anchors of
    /// Foster's session-RPE scale (CR-10; Foster et al., J Strength Cond Res
    /// 2001): 1 very, very easy, 2 easy, 3 moderate, 4 somewhat hard, 5 hard,
    /// 7 very hard, 10 maximal; the unlabelled 6, 8 and 9 take the anchor
    /// below them. `StrainCalculator.rpeToTrimp` is calibrated on these anchors
    /// (moderate ≈ 3, hard ≈ 5-6, very hard ≈ 7), so the words matter: the old
    /// labels called 5-6 "moderate" and 7-8 "hard", nudging ratings up.
    public static func sessionLabel(_ rpe: Int) -> String {
        switch rpe {
        case ...1: "Very, very easy"
        case 2: "Easy"
        case 3: "Moderate"
        case 4: "Somewhat hard"
        case 5...6: "Hard"
        case 7...9: "Very hard"
        default: "Maximal"
        }
    }
}

/// Estimated one-rep max from a set, counting the reps you had left.
///
/// Epley: 1RM = weight x (1 + reps/30), where reps means reps to failure. With
/// the reps-in-reserve RPE scale, reps to failure = reps done + (10 - RPE)
/// (Zourdos et al., J Strength Cond Res 2016). Ignoring RPE would make a set
/// of 8 at RPE 8 look like a max effort and under-prescribe the next session.
/// Rep-max equations lose accuracy past ~10-12 reps, so effective reps are
/// capped at 15, and what is shown comes only from sets of 10 reps or fewer
/// (`displayEstimate`). Lifters misjudge reps left by about one on average, and
/// guesses get worse further from failure and on high-rep sets (Halperin et
/// al., Sports Med 2022), so at most 4 reps left are counted.
public enum OneRepMax {
    public static func estimate(weight: Double, reps: Int, rpe: Double?) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        let repsLeft = rpe.map { max(0, min(4, 10 - $0)) } ?? 0
        let toFailure = min(15, Double(reps) + repsLeft)
        return toFailure <= 1 ? weight : weight * (1 + toFailure / 30)
    }

    /// Estimates are shown, and records set, only from sets of this many
    /// reps or fewer. Rep-max equations are most accurate from 10 reps or
    /// fewer and differ by lift (LeSuer DA, et al. J Strength Cond Res
    /// 1997;11(4):211-213), and the reps people manage at a given share of
    /// their 1RM vary by exercise, more so at lighter loads (Nuzzo JL, et al.
    /// Sports Med 2024;54(2):303-321; meta-regression of 952 tests). The
    /// research doc allows 10-12; the lower end is used so every screen and
    /// the lift-goal trend (`LiftGoalProjection.maximumReps`) share one rule.
    /// The planner still uses `estimate` for higher-rep sets: it only needs a
    /// relative load, not a number to show.
    public static let maximumReliableReps = 10

    /// The estimate to show or to compare as a record; nil for a set of more
    /// than `maximumReliableReps` reps, or with no weight.
    public static func displayEstimate(weight: Double, reps: Int, rpe: Double?) -> Double? {
        guard reps > 0, reps <= maximumReliableReps, weight > 0 else { return nil }
        return estimate(weight: weight, reps: reps, rpe: rpe)
    }

    /// Put before every estimated 1RM on screen: "≈ 96 kg".
    public static let symbol = "≈"

    /// The caveat wherever an estimate is shown or shared.
    public static let caveat = "Estimated 1RM (≈) comes from your sets of 10 reps or fewer and the reps you had left; it's an estimate and varies by lift (LeSuer 1997; Nuzzo 2024)."
}
