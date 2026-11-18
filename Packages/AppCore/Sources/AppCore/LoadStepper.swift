import Foundation

// What the Digital Crown steps through on the Watch's Set page: the loads the
// gym can make, the reps, or a hold's seconds. Foundation only, with no
// reference to anything else in AppCore, so the Watch app compiles this file
// on its own (project.yml, `TensileWatch: sources:`).
//
// The loads come from the phone (`WatchSession.ExerciseSnapshot.achievableLoadsKg`,
// built from the gym's plates, dumbbells and stacks), so the crown only offers
// what can be loaded, as CLAUDE.md requires of the trainer. Weights are kept
// in kilograms; the Watch converts only to show them.

/// Steps a set's weight, reps or hold time.
public nonisolated struct LoadStepper: Sendable, Equatable {
    /// Weights in kg, ascending, never empty.
    public let loads: [Double]

    /// Reps the crown allows: 0-50 (app's choice: covers any set a lifter logs,
    /// including a high-rep finisher; 0 logs a failed attempt).
    public static let repRange = 0...50
    /// A hold's seconds step by 5 (the existing app's choice in the Watch's
    /// hold adjuster: fine enough for a plank, few crown detents).
    public static let holdStepSeconds = 5
    /// A hold tops out at 10 minutes (app's choice).
    public static let maximumHoldSeconds = 600
    /// Steps of the gym's smallest jump either side of the planned weight when
    /// the phone sent no load list (app's choice: room for a big change on a
    /// warm-up or a missed jump without an endless crown).
    public static let fallbackStepsBelow = 20
    public static let fallbackStepsAbove = 20

    /// Loads the gym can make, or, without a list, steps of `stepKg` around
    /// `weightKg`. The planned weight is always one of them, so the crown
    /// starts on it even when it isn't a makeable load (it was typed in).
    public init(achievableKg: [Double]?, weightKg: Double, stepKg: Double) {
        var values = (achievableKg ?? []).filter { $0.isFinite && $0 >= 0 }
        if values.isEmpty {
            let step = stepKg.isFinite && stepKg > 0 ? stepKg : 2.5
            let planned = weightKg.isFinite ? max(0, weightKg) : 0
            let low = max(0, planned - Double(Self.fallbackStepsBelow) * step)
            let count = Int(((planned + Double(Self.fallbackStepsAbove) * step - low) / step).rounded(.down))
            values = (0...max(0, count)).map { low + Double($0) * step }
        }
        if weightKg.isFinite, weightKg >= 0, !values.contains(where: { abs($0 - weightKg) < 0.001 }) {
            values.append(weightKg)
        }
        let sorted = values.sorted()
        var unique: [Double] = []
        for value in sorted where unique.last.map({ abs($0 - value) >= 0.001 }) ?? true {
            unique.append(value)
        }
        loads = unique.isEmpty ? [0] : unique
    }

    /// The index of the load nearest `weightKg` (the lighter one on a tie).
    public func nearestIndex(to weightKg: Double) -> Int {
        guard weightKg.isFinite else { return 0 }
        var best = 0
        for index in loads.indices where abs(loads[index] - weightKg) < abs(loads[best] - weightKg) - 0.000_1 {
            best = index
        }
        return best
    }

    /// The load `steps` places from the one nearest `weightKg`, held at the ends.
    public func step(from weightKg: Double, by steps: Int) -> Double {
        loads[clampedIndex(nearestIndex(to: weightKg) + steps)]
    }

    /// The load at a crown position (rounded), held at the ends.
    public func load(atCrown value: Double) -> Double {
        guard value.isFinite else { return loads[0] }
        return loads[clampedIndex(Int(value.rounded()))]
    }

    public func clampedIndex(_ index: Int) -> Int {
        min(loads.count - 1, max(0, index))
    }

    /// Reps moved by `steps`, kept in `repRange`.
    public static func reps(_ reps: Int, by steps: Int) -> Int {
        min(repRange.upperBound, max(repRange.lowerBound, reps + steps))
    }

    /// A hold's seconds moved by `steps` of 5 s: first onto the 5 s grid
    /// (32 → 35 up, 32 → 30 down), then whole steps; 0 to 10 minutes.
    public static func holdSeconds(_ seconds: Int, by steps: Int) -> Int {
        guard steps != 0 else { return min(maximumHoldSeconds, max(0, seconds)) }
        let step = holdStepSeconds
        let current = max(0, seconds)
        var value: Int
        if steps > 0 {
            value = (current / step + 1) * step + (steps - 1) * step
        } else {
            value = ((current - 1) / step) * step + (steps + 1) * step
            if current == 0 { value = 0 }
        }
        return min(maximumHoldSeconds, max(0, value))
    }
}
