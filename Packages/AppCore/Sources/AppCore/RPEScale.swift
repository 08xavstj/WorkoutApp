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
        Level(rpe: 8.5, repsLeft: "1-2", title: "Hard", feel: "Definitely one more, maybe two."),
        Level(rpe: 8, repsLeft: "2", title: "Hard", feel: "Two more reps in the tank. The typical working-set target."),
        Level(rpe: 7.5, repsLeft: "2-3", title: "Challenging", feel: "Definitely two more, maybe three."),
        Level(rpe: 7, repsLeft: "3", title: "Challenging", feel: "Three more reps possible. Fast, controlled reps."),
        Level(rpe: 6, repsLeft: "4", title: "Moderate", feel: "Four more reps. Good for technique and lighter days."),
        Level(rpe: 5, repsLeft: "5+", title: "Easy", feel: "Warm-up weight; could do many more."),
    ]

    public static func level(for rpe: Double) -> Level? {
        levels.min { abs($0.rpe - rpe) < abs($1.rpe - rpe) }
    }

    /// e.g. "RPE 8 · 2 reps left"
    public static func summary(_ rpe: Double) -> String {
        guard let level = level(for: rpe) else { return "RPE \(rpe.formatted())" }
        let reps = level.repsLeft == "1" ? "1 rep left" : "\(level.repsLeft) reps left"
        return "RPE \(rpe.formatted()) · \(reps)"
    }

    /// Whole-workout difficulty for the finish screen.
    public static func sessionLabel(_ rpe: Int) -> String {
        switch rpe {
        case ...2: "Very easy"
        case 3...4: "Easy"
        case 5...6: "Moderate"
        case 7...8: "Hard"
        case 9: "Very hard"
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
/// capped at 15.
public enum OneRepMax {
    public static func estimate(weight: Double, reps: Int, rpe: Double?) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        let repsLeft = rpe.map { max(0, min(4, 10 - $0)) } ?? 0
        let toFailure = min(15, Double(reps) + repsLeft)
        return toFailure <= 1 ? weight : weight * (1 + toFailure / 30)
    }
}
