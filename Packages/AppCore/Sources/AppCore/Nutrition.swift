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

    // MARK: Protein per meal

    /// Protein per meal: about 0.4 g/kg at each of 4 meals reaches the daily
    /// 1.6 g/kg with every dose in the range that fully stimulates muscle
    /// protein synthesis (Schoenfeld & Aragon, JISSN 2018: 0.4 g/kg across at
    /// least 4 meals, 0.25-0.55 g/kg per dose; Moore et al., J Gerontol A 2015:
    /// about 0.24 g/kg young, 0.40 g/kg older per dose; Kerksick et al., ISSN
    /// nutrient timing 2017: 20-40 g every 3-4 h). With 3 logged meals the
    /// per-meal dose rises so the day still reaches 1.6 g/kg (0.53 g/kg, inside
    /// Schoenfeld's 0.55 ceiling). Endurance or health-only goals get the
    /// lighter 3 × 0.3 g/kg pattern from docs/research/nutrition.md. Long-term
    /// body-composition trials are few, so the UI says "about".
    public static let proteinPerMealGramsPerKg = ProteinMeals.gramsPerKgPerMeal
    public static let proteinPerMealCeilingGramsPerKg = 0.55

    /// Grams per meal and how many meals, or nil without a weight.
    /// - Parameter loggedMeals: meals seen in today's food log (3 switches to the 3-meal spread).
    public static func proteinPerMeal(bodyMassKg: Double?, goals: Goals?, loggedMeals: Int? = nil) -> (grams: Double, meals: Int)? {
        guard let bodyMassKg, bodyMassKg > 0 else { return nil }
        let lifting = goals.map { $0.focuses.contains(.muscle) || $0.focuses.contains(.strength) || $0.weight == .lose } ?? true
        if !lifting {
            // Endurance / health only: 3 meals of about 0.3 g/kg (nutrition.md).
            return ((bodyMassKg * 0.3).rounded(), 3)
        }
        let meals = loggedMeals == 3 ? 3 : ProteinMeals.targetMeals
        let perKg = min(proteinPerMealCeilingGramsPerKg, max(proteinPerMealGramsPerKg, 1.6 / Double(meals)))
        return ((bodyMassKg * perKg).rounded(), meals)
    }

    // MARK: Carbohydrate by training day

    /// Carbohydrate per kg body weight, a training-day and rest-day pair.
    /// Burke et al. (J Sports Sci 2011): 3-5 g/kg for light or skill-based
    /// days, 5-7 g/kg for about an hour a day of moderate training, 6-10 for
    /// 1-3 h; Kerksick et al. (ISSN nutrient timing 2017) for the refuelling
    /// side. For lifters carbs are what's left after protein and fat (Helms
    /// et al., JISSN 2014), so the lifting bands are the low end of Burke's
    /// table: 3-5 g/kg on training days and, as an app choice below Burke's
    /// lowest band, 2-3 g/kg on rest days. Endurance focus: 5-7 training,
    /// 3-5 rest. Calorie targets are untouched; this only shapes the split.
    public static func carbsPerKg(trainingDay: Bool, goals: Goals?) -> ClosedRange<Double> {
        let endurance = goals?.focuses.contains(.endurance) == true
        if endurance { return trainingDay ? 5...7 : 3...5 }
        return trainingDay ? 3...5 : 2...3
    }

    /// Grams for the day, from the per-kg band; nil without a weight.
    public static func carbsGrams(bodyMassKg: Double?, trainingDay: Bool, goals: Goals?) -> ClosedRange<Double>? {
        guard let bodyMassKg, bodyMassKg > 0 else { return nil }
        let band = carbsPerKg(trainingDay: trainingDay, goals: goals)
        return (bodyMassKg * band.lowerBound).rounded()...(bodyMassKg * band.upperBound).rounded()
    }

    /// "Carbs: about 240-400 g today (training day), 160-240 g on rest days."
    public static func carbsText(bodyMassKg: Double?, trainingDay: Bool, goals: Goals?) -> String? {
        guard let today = carbsGrams(bodyMassKg: bodyMassKg, trainingDay: trainingDay, goals: goals),
              let other = carbsGrams(bodyMassKg: bodyMassKg, trainingDay: !trainingDay, goals: goals) else { return nil }
        func text(_ range: ClosedRange<Double>) -> String { "\(Int(range.lowerBound))-\(Int(range.upperBound)) g" }
        return trainingDay
            ? "Carbs: about \(text(today)) today (training day), \(text(other)) on rest days."
            : "Carbs: about \(text(today)) today (rest day), \(text(other)) on training days."
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
