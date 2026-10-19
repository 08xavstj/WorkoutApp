import Foundation

/// What the user is working toward. Drives the calorie target, protein and
/// how the trainer programs sets and reps.
public struct Goals: Codable, Sendable, Equatable {
    public enum Weight: String, Codable, Sendable, CaseIterable {
        case lose, maintain, gain
    }

    public enum Focus: String, Codable, Sendable, CaseIterable {
        case muscle, strength, endurance, health
    }

    public var weight: Weight
    /// Percent of body weight per week for lose/gain.
    public var weeklyRatePercent: Double
    public var focuses: [Focus]
    public var targetWeightKg: Double?

    public init(weight: Weight = .maintain, weeklyRatePercent: Double = 0.5, focuses: [Focus] = [.muscle], targetWeightKg: Double? = nil) {
        self.weight = weight
        self.weeklyRatePercent = weeklyRatePercent
        self.focuses = focuses
        self.targetWeightKg = targetWeightKg
    }

    /// Losing fat while building muscle ("recomposition").
    public var isRecomp: Bool { weight == .lose && focuses.contains(.muscle) }

    public var title: String {
        if isRecomp { return "Lose fat, build muscle" }
        let weightPart: String = switch weight {
        case .lose: "Lose weight"
        case .maintain: "Maintain weight"
        case .gain: "Gain weight"
        }
        let focusPart = focuses.map(\.label).joined(separator: " & ").lowercased()
        return focusPart.isEmpty ? weightPart : "\(weightPart), \(focusPart)"
    }
}

extension Goals.Focus {
    public var label: String {
        switch self {
        case .muscle: "Build muscle"
        case .strength: "Get stronger"
        case .endurance: "Stamina"
        case .health: "General health"
        }
    }
}

/// Research-based numbers for each goal.
///
/// - Rate of loss: about 0.5-1% of body weight a week keeps more muscle than
///   faster loss (Helms et al., JISSN 2014; Garthe et al., IJSNEM 2011).
/// - Rate of gain: about 0.25-0.5% a week; bigger surpluses mostly add fat
///   (Iraki et al., Sports 2019).
/// - Protein: 1.6 g/kg builds muscle (Morton et al., BJSM 2018); in a deficit
///   or recomposition, more helps keep muscle: 2.3-3.1 g per kg of *lean* mass
///   (Helms 2014; Barakat et al., Strength Cond J 2020). Grams per kg of total
///   weight overshoot for people with more body fat, so the target uses lean
///   mass when body fat is known, otherwise the goal weight or an adjusted
///   body weight when BMI is over 30.
public enum GoalPlanner {
    /// Daily calorie target from maintenance and the goal.
    public static func calorieTarget(maintenance: Double, bodyMassKg: Double, goals: Goals, sex: BiologicalSex) -> Double {
        let weeklyKg = bodyMassKg * goals.weeklyRatePercent / 100
        let daily = weeklyKg * AdaptiveTDEE.kcalPerKg / 7
        let target: Double = switch goals.weight {
        case .maintain: maintenance
        case .lose: maintenance - daily
        case .gain: maintenance + daily
        }
        // Don't go below a safe floor without medical supervision.
        let floor: Double = sex == .male ? 1500 : 1200
        return max(floor, target)
    }

    public static func proteinPerKg(_ goals: Goals) -> Double {
        if goals.weight == .lose { return 2.2 }
        return goals.focuses.contains(.muscle) || goals.focuses.contains(.strength) ? 1.6 : 1.2
    }

    /// Lean-mass protein in a deficit: the middle of Helms' 2.3-3.1 g/kg range.
    public static let deficitProteinPerKgLeanMass = 2.6

    /// The weight protein is worked out from: current weight, or an adjusted
    /// body weight when BMI is over 30 (weight at BMI 25 plus 40% of the
    /// excess), or the goal weight when losing if that's lower.
    public static func proteinReferenceWeight(goals: Goals?, bodyMassKg: Double, heightCm: Double?) -> Double {
        var reference = bodyMassKg
        if let heightCm, heightCm > 100 {
            let meters = heightCm / 100
            let atBMI25 = 25 * meters * meters
            if bodyMassKg / (meters * meters) > 30 {
                reference = atBMI25 + 0.4 * (bodyMassKg - atBMI25)
            }
        }
        if let goals, goals.weight == .lose, let target = goals.targetWeightKg, target > 0 {
            reference = min(reference, target)
        }
        return reference
    }

    /// Daily protein in grams for the goal.
    /// - Parameter minimumPerKg: a floor per kg of reference weight (e.g. 2.0
    ///   for some medications).
    public static func proteinGrams(goals: Goals?, bodyMassKg: Double?, bodyFatPercent: Double?,
                                    heightCm: Double?, minimumPerKg: Double? = nil) -> Double? {
        guard let bodyMassKg, bodyMassKg > 0 else { return nil }
        let reference = proteinReferenceWeight(goals: goals, bodyMassKg: bodyMassKg, heightCm: heightCm)
        let grams: Double
        if let goals, goals.weight == .lose, let fat = bodyFatPercent, fat > 3, fat < 60 {
            grams = bodyMassKg * (1 - fat / 100) * deficitProteinPerKgLeanMass
        } else {
            grams = reference * (goals.map(proteinPerKg) ?? 1.6)
        }
        let floor = reference * (minimumPerKg ?? 0)
        return max(grams, floor).rounded()
    }

    /// Allowed weekly rates (% body weight) for the picker.
    public static func rateOptions(for weight: Goals.Weight) -> [Double] {
        switch weight {
        case .lose: [0.25, 0.5, 0.75, 1.0]
        case .gain: [0.25, 0.5]
        case .maintain: []
        }
    }

    /// The trainer's set and rep style for these goals.
    public static func trainingStyle(_ goals: Goals) -> TrainingStyle {
        if goals.focuses.contains(.strength) && !goals.focuses.contains(.muscle) { return .strength }
        if goals.focuses.contains(.muscle) { return .muscle }
        if goals.focuses.contains(.endurance) { return .endurance }
        return .balanced
    }

    /// A starting suggestion from body composition (the user can change it).
    public static func suggest(bodyFatPercent: Double?, bmi: Double?, sex: BiologicalSex) -> Goals {
        let highFat: Bool = {
            if let fat = bodyFatPercent { return fat > (sex == .male ? 22 : 32) }
            if let bmi { return bmi >= 27 }
            return false
        }()
        let lowFat: Bool = {
            if let fat = bodyFatPercent { return fat < (sex == .male ? 12 : 20) }
            if let bmi { return bmi < 20 }
            return false
        }()
        if highFat { return Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle]) }
        if lowFat { return Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.muscle]) }
        return Goals(weight: .maintain, focuses: [.muscle, .health])
    }

    /// Weeks to reach the target weight at the chosen rate.
    public static func weeksToTarget(currentKg: Double, goals: Goals) -> Double? {
        guard let target = goals.targetWeightKg, goals.weight != .maintain else { return nil }
        let weekly = currentKg * goals.weeklyRatePercent / 100
        guard weekly > 0 else { return nil }
        let remaining = goals.weight == .lose ? currentKg - target : target - currentKg
        return remaining > 0 ? remaining / weekly : 0
    }
}

/// How the trainer sets reps and effort.
public enum TrainingStyle: String, Codable, Sendable {
    /// 6-8 on big lifts, 10-12 on small ones (the default).
    case balanced
    /// Heavier: 3-6 reps on big lifts, 2-3 reps left in the tank.
    case strength
    /// Muscle growth: 6-10 / 10-15, sets taken closer to failure (Robinson et al., Sports Med 2024).
    case muscle
    /// Lighter and higher reps with shorter rests.
    case endurance
}
