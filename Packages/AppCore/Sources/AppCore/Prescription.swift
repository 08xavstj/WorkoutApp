import Foundation

/// One exercise's plan in words, the same in the workout builder, the live
/// workout's exercise header and its collapsed rows: "3 × 7" and "82.5 kg"
/// or "24 kg per hand". No reps-in-reserve part: sets work to rep goals (`RepGoal`).
public enum Prescription {
    /// "3 × 7": today's rep goal (`PlannedExercise.targetReps`), or the range
    /// ("3 × 6–10") when there's none yet. `rpe` is ignored (kept for callers).
    public static func sets(_ sets: Int, repsLow: Int, repsHigh: Int, targetReps: Int?, rpe: Double? = nil) -> String {
        let reps = targetReps.map { "\($0)" } ?? (repsLow == repsHigh ? "\(repsHigh)" : "\(repsLow)–\(repsHigh)")
        return "\(sets) × \(reps)"
    }

    /// "82.5 kg", or "24 kg per hand" for dumbbells and kettlebells (the
    /// weight is per hand: `PlannedExercise.load`).
    public static func load(_ value: Double, unit: String, kind: EquipmentKind?) -> String {
        let text = "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
        return isPerHand(kind) ? text + " per hand" : text
    }

    /// Dumbbells and kettlebells are weighed per hand.
    public static func isPerHand(_ kind: EquipmentKind?) -> Bool {
        kind == .dumbbell || kind == .kettlebell
    }
}
