import Foundation

/// One day's food intake, as summed from Apple Health. Cronometer (and most
/// food loggers) write these values to Health when its Apple Health sync is on.
public struct NutritionDay: Sendable, Equatable {
    public var date: Date
    public var calories: Double?
    public var proteinGrams: Double?
    public var carbsGrams: Double?
    public var fatGrams: Double?
    public var fiberGrams: Double?
    public var waterLiters: Double?

    public init(
        date: Date,
        calories: Double? = nil,
        proteinGrams: Double? = nil,
        carbsGrams: Double? = nil,
        fatGrams: Double? = nil,
        fiberGrams: Double? = nil,
        waterLiters: Double? = nil
    ) {
        self.date = date
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.waterLiters = waterLiters
    }

    /// True when nothing was logged.
    public var isEmpty: Bool {
        [calories, proteinGrams, carbsGrams, fatGrams].allSatisfy { ($0 ?? 0) == 0 }
    }
}

public enum NutritionTargets {
    /// Daily protein for someone lifting regularly: 1.6 g per kg of body weight
    /// covers most people; up to 2.2 g/kg may help some (Morton et al., Br J
    /// Sports Med 2018: breakpoint 1.62 g/kg, 95% CI 1.03-2.20).
    /// `gramsPerKg` can be raised, e.g. to 2.0 on weight-loss medication.
    public static func proteinGrams(bodyMassKg: Double?, gramsPerKg: Double = 1.6) -> Double? {
        guard let bodyMassKg, bodyMassKg > 0 else { return nil }
        return (bodyMassKg * gramsPerKg).rounded()
    }

    // MARK: Fibre

    /// Daily fibre target: 25-29 g a day gave the largest fall in all-cause
    /// and heart mortality in 185 prospective studies and 58 trials (Reynolds
    /// et al., Lancet 2019), with some extra benefit above that. The dietary
    /// "adequate intake" (38 g for men under 50) is a population value, not an
    /// outcome target, so the target here is the trial range. Most people eat
    /// about half of it.
    public static let fiberTargetGrams: ClosedRange<Double> = 25...29
    /// Under this is clearly low: about the bottom of the intake bands with
    /// the worst outcomes in Reynolds 2019 (app choice from the research round).
    public static let fiberLowGrams = 20.0
    /// When gaining weight, a lot more than the target blunts appetite; the
    /// health-metrics report puts the useful range at 25-35 g.
    public static let fiberGainCapGrams = 35.0

    public enum FiberStatus: String, Sendable, Equatable {
        case low, nearTarget, onTarget
    }

    /// Where a day's (or a 7-day average) fibre intake sits against the target.
    public static func fiberStatus(grams: Double?) -> FiberStatus? {
        guard let grams, grams >= 0 else { return nil }
        if grams < fiberLowGrams { return .low }
        if grams < fiberTargetGrams.lowerBound { return .nearTarget }
        return .onTarget
    }

    /// Target text by goal. Losing: fibre is the satiety lever, so aim for the
    /// top of the range or more. Gaining: enough is enough. Everyone else: the
    /// trial range, and more is fine.
    public static func fiberTargetText(goals: Goals?) -> String {
        let low = Int(fiberTargetGrams.lowerBound)
        let high = Int(fiberTargetGrams.upperBound)
        switch goals?.weight {
        case .lose:
            return "\(low)-\(high) g a day or more; fibre is the cheapest way to feel full on fewer calories."
        case .gain:
            return "\(low)-\(Int(fiberGainCapGrams)) g a day; much more blunts appetite when you're trying to eat enough."
        default:
            return "\(low)-\(high) g a day or more."
        }
    }
}
