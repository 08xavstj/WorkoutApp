import Foundation

/// The one way the app words reps in reserve (RIR): how many more clean reps
/// you could have done when you stopped the set. The plain words lead ("3
/// reps in the tank", "3 left"); RPE is only a small secondary label, because
/// lifters found "3 in reserve" next to an RPE number confusing. The RIR-based
/// RPE scale is RPE = 10 − reps left (Zourdos et al., J Strength Cond Res
/// 2016; Helms et al., Strength Cond J 2016).
/// A half-rep can't be done, so a half shows as the two whole reps around it.
public enum ReserveText {
    /// "3 reps in the tank", "1 rep in the tank", "2-3 reps in the tank",
    /// "to failure". Rounded to the nearest half rep first.
    public static func text(_ reserve: Double) -> String {
        guard let bound = bounds(reserve) else { return "to failure" }
        let (low, high) = (bound.low, bound.high)
        return phrase(low: low, high: high)
    }

    /// The same from a planned RPE (reps in reserve = 10 − RPE).
    public static func text(rpe: Double) -> String {
        text(10 - rpe)
    }

    /// The range the sets actually ask for, from each one's planned RPE:
    /// "3 reps in the tank" when they agree, "2-3 reps in the tank" when big
    /// and small lifts differ. `fallback` (an RPE) when there are none.
    public static func text(rpes: [Double], fallback: Double) -> String {
        guard let bound = bounds(rpes: rpes, fallback: fallback) else { return "to failure" }
        let (low, high) = (bound.low, bound.high)
        return phrase(low: low, high: high)
    }

    /// Just the number, for a stat tile: "3", "2-3", "0".
    public static func count(_ reserve: Double) -> String {
        guard let bound = bounds(reserve) else { return "0" }
        let (low, high) = (bound.low, bound.high)
        return range(low: low, high: high)
    }

    /// The number for the range the sets ask for: "2-3", "3", "0".
    public static func count(rpes: [Double], fallback: Double) -> String {
        guard let bound = bounds(rpes: rpes, fallback: fallback) else { return "0" }
        let (low, high) = (bound.low, bound.high)
        return range(low: low, high: high)
    }

    /// Compact, for set rows and pills: "3 left", "2-3 left", "0 left".
    public static func short(rpe: Double) -> String {
        "\(count(10 - rpe)) left"
    }

    /// For VoiceOver: "3 reps left", "1 rep left", "2 to 3 reps left", "no reps left".
    public static func spoken(rpe: Double) -> String {
        guard let bound = bounds(10 - rpe) else { return "no reps left" }
        let (low, high) = (bound.low, bound.high)
        if low == high { return low == 1 ? "1 rep left" : "\(low) reps left" }
        return "\(low) to \(high) reps left"
    }

    // MARK: The "reps left" buttons

    /// The buttons after a set: 0, 1, 2, 3 and 4+ reps left. 4 is the most
    /// counted because guesses further from failure get unreliable (Halperin
    /// et al., Sports Med 2022; see `OneRepMax`).
    public static let repsLeftChoices = [0, 1, 2, 3, 4]

    /// "4+" for the last button, else the number.
    public static func choiceLabel(_ left: Int) -> String {
        left >= 4 ? "4+" : "\(max(0, left))"
    }

    /// The RPE stored for a "reps left" tap: 10 − reps left (0 → 10 … 4+ → 6).
    public static func rpe(repsLeft: Int) -> Double {
        Double(10 - min(4, max(0, repsLeft)))
    }

    /// The button a logged or planned RPE falls on: whole reps left, 0-4
    /// (RPE 7.5 → 2, with the half shown separately; RPE 5 → 4+).
    public static func choice(rpe: Double) -> Int {
        min(4, max(0, Int((10 - rpe + 0.001).rounded(.down))))
    }

    // MARK: Explainer

    /// Title of the first-time card and the guide's top: "What “3 reps in the tank” means".
    public static func explainerTitle(_ reserve: Double) -> String {
        "What \u{201C}\(text(reserve))\u{201D} means"
    }

    /// The plain-words explanation for a target, shown the first time a
    /// workout has one and from the ⓘ beside the plan line.
    public static func explainerBody(_ reserve: Double) -> String {
        let after = "After each set, tap how many more you could have done. The app uses it to adjust your next set."
        guard let bound = bounds(reserve) else {
            return "Keep going until another clean rep won't go, then stop. " + after
        }
        let (low, high) = (bound.low, bound.high)
        let more = low == high && low == 1 ? "1 more rep" : "\(range(low: low, high: high)) more reps"
        return "Pick a weight you could lift for about \(more) than the target, and stop the set there. " + after
    }

    /// The worked example in the guide: "You planned 8 reps with 2 left:
    /// pick a weight you could do 10 times, and stop at 8."
    public static func example(reps: Int, reserve: Int) -> String {
        let left = max(0, reserve)
        if left == 0 { return "You planned \(reps) reps to failure: pick a weight you can do about \(reps) times, and stop when another rep won't go." }
        return "You planned \(reps) reps with \(left) left: pick a weight you could do \(reps + left) times, and stop at \(reps)."
    }

    // MARK: Helpers

    /// Whole reps around a reserve rounded to the nearest half; nil at failure.
    private static func bounds(_ reserve: Double) -> (low: Int, high: Int)? {
        let halves = (max(0, reserve) * 2).rounded() / 2
        let low = Int(halves.rounded(.down))
        let high = Int(halves.rounded(.up))
        return high == 0 ? nil : (low: low, high: high)
    }

    private static func bounds(rpes: [Double], fallback: Double) -> (low: Int, high: Int)? {
        let reserves = rpes.map { (max(0, 10 - $0) * 2).rounded() / 2 }
        guard let least = reserves.min(), let most = reserves.max() else { return bounds(10 - fallback) }
        let low = Int(least.rounded(.down))
        let high = Int(most.rounded(.up))
        return high == 0 ? nil : (low: low, high: high)
    }

    private static func range(low: Int, high: Int) -> String {
        low == high ? "\(low)" : "\(low)-\(high)"
    }

    private static func phrase(low: Int, high: Int) -> String {
        if low == high, low == 1 { return "1 rep in the tank" }
        return "\(range(low: low, high: high)) reps in the tank"
    }
}
