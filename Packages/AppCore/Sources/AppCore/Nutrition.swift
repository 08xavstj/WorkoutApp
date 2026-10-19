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
}
