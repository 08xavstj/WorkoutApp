import Foundation

/// Protein, carbohydrate and fat targets that fit inside the calorie target.
///
/// The app used to set protein and calories independently, so on a deep cut
/// the protein target (2.6 g per kg of lean mass when losing) could take 40%
/// of a 1,700 kcal day and crowd out the carbs needed to train. This split
/// keeps floors for fat and carbs and caps protein so they hold:
///
/// - Fat floor 0.7 g/kg (`fatFloorGramsPerKg`). Helms, Aragon & Fitschen
///   (JISSN 2014) put fat at 15-30% of calories for dieting lifters; for a
///   74 kg man on 1,700 kcal, 0.7 g/kg is 52 g, about 27%. Iraki et al.
///   (Sports 2019) give 0.5-1.5 g/kg for lifters eating at or above
///   maintenance ((m) not re-verified in this round). The 0.7 is an app
///   choice inside both ranges.
/// - Carbohydrate floor 2.0 g/kg when lifting (`carbsFloorGramsPerKgLifting`):
///   the bottom of the app's rest-day band (`NutritionTargets.carbsPerKg`),
///   itself an app choice just under Burke et al.'s 3-5 g/kg for light
///   training (J Sports Sci 2011), and never under the 130 g a day the
///   Institute of Medicine sets as the RDA for carbohydrate (2005). Helms 2014
///   treats carbs as what is left after protein and fat, so the floor is the
///   low end on purpose; a day over the floor is normal.
/// - Protein: the goal's target (`GoalPlanner.proteinGrams`) when it fits.
///   When it doesn't, it steps down to the bottom of the evidence range for a
///   deficit: 2.3 g/kg of lean mass (Helms, Zinn, Rowlands & Brown, IJSNEM
///   2014: 2.3-3.1 g/kg FFM) when body fat is known, else 2.0 g/kg of body
///   weight (Phillips & Van Loon, J Sports Sci 2011: 1.8-2.0 g/kg in energy
///   restriction; ISSN position stand, Jäger et al. 2017: 1.4-2.0 g/kg).
///   If even that leaves no room, protein is cut to what fits, but never under
///   1.6 g/kg (`proteinMinimumGramsPerKg`; Morton et al., BJSM 2018: no further
///   lean-mass gain above a 1.62 g/kg breakpoint, 95% CI 1.03-2.20), and
///   `tooFewCaloriesForFloors` is set so the UI can say the calorie target is
///   the problem. Evidence that the top of the protein range matters is weak:
///   Helms 2014 pooled six small studies, and Morton 2018 found no extra gain
///   above about 1.6 g/kg, so the step down costs little.
/// - Above the floors, fat sits at 25% of calories (`fatShareOfCalories`, an
///   app choice inside Helms' 15-30%) and carbs take the rest.
public struct MacroSplit: Sendable, Equatable {
    /// Daily protein, grams (possibly capped).
    public var proteinGrams: Double
    /// Daily carbohydrate, grams.
    public var carbsGrams: Double
    /// Daily fat, grams.
    public var fatGrams: Double
    /// The goal's protein target before the calorie cap.
    public var proteinGramsUncapped: Double
    /// The carb and fat floors the cap protects.
    public var carbsFloorGrams: Double
    public var fatFloorGrams: Double
    /// True when protein was cut to its minimum and the floors still don't fit.
    public var tooFewCaloriesForFloors: Bool
    /// The calorie target the split was made for.
    public var calorieTarget: Double

    public init(proteinGrams: Double, carbsGrams: Double, fatGrams: Double, proteinGramsUncapped: Double,
                carbsFloorGrams: Double, fatFloorGrams: Double, tooFewCaloriesForFloors: Bool, calorieTarget: Double) {
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.proteinGramsUncapped = proteinGramsUncapped
        self.carbsFloorGrams = carbsFloorGrams
        self.fatFloorGrams = fatFloorGrams
        self.tooFewCaloriesForFloors = tooFewCaloriesForFloors
        self.calorieTarget = calorieTarget
    }

    /// True when the goal's protein target was lowered to fit the calories.
    public var proteinWasCapped: Bool { proteinGrams < proteinGramsUncapped - 0.5 }

    /// Protein's share of the calorie target, 0-100.
    public var proteinPercentOfCalories: Double {
        guard calorieTarget > 0 else { return 0 }
        return proteinGrams * Self.kcalPerGramProtein / calorieTarget * 100
    }

    // MARK: Constants

    /// Fat floor, g per kg body weight (Helms 2014: 15-30% of calories; app choice, see above).
    public static let fatFloorGramsPerKg = 0.7
    /// Carbohydrate floor for lifters, g/kg (bottom of the app's rest-day band; Burke 2011).
    public static let carbsFloorGramsPerKgLifting = 2.0
    /// Carbohydrate floor for everyone, g a day (Institute of Medicine 2005 RDA).
    public static let carbsFloorGramsRDA = 130.0
    /// Protein is never cut under this, g per kg of reference weight (Morton et al., BJSM 2018).
    public static let proteinMinimumGramsPerKg = 1.6
    /// Step-down protein in a deficit, g per kg of lean mass (bottom of Helms 2014's 2.3-3.1).
    public static let deficitProteinLowPerKgLeanMass = 2.3
    /// Step-down protein in a deficit without body fat, g/kg body weight (Phillips & Van Loon 2011; Jäger 2017).
    public static let deficitProteinLowPerKg = 2.0
    /// Fat's share of calories above the floors (app choice inside Helms 2014's 15-30%).
    public static let fatShareOfCalories = 0.25

    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarbs = 4.0
    static let kcalPerGramFat = 9.0

    // MARK: Split

    /// The day's macro targets, or nil without a weight or a calorie target.
    /// - Parameters:
    ///   - minimumProteinPerKg: a floor per kg of reference weight (e.g. 2.0 on
    ///     some medications); it is kept even when it breaks the carb floor.
    ///   - trainingStatus: with no goals, anyone trained counts as lifting.
    public static func make(calorieTarget: Double?, bodyMassKg: Double?, bodyFatPercent: Double?, heightCm: Double?,
                            goals: Goals?, sex: BiologicalSex, trainingStatus: TrainingStatus?,
                            minimumProteinPerKg: Double? = nil) -> MacroSplit? {
        guard let calorieTarget, calorieTarget > 0, let bodyMassKg, bodyMassKg > 0 else { return nil }
        guard let uncapped = GoalPlanner.proteinGrams(goals: goals, bodyMassKg: bodyMassKg, bodyFatPercent: bodyFatPercent,
                                                      heightCm: heightCm, minimumPerKg: minimumProteinPerKg) else { return nil }
        let reference = GoalPlanner.proteinReferenceWeight(goals: goals, bodyMassKg: bodyMassKg, heightCm: heightCm)
        let lifting = isLifting(goals: goals, trainingStatus: trainingStatus)

        let fatFloor = (bodyMassKg * fatFloorGramsPerKg).rounded()
        let carbsFloor = lifting ? max(carbsFloorGramsRDA, (bodyMassKg * carbsFloorGramsPerKgLifting).rounded()) : carbsFloorGramsRDA
        let roomForProtein = (calorieTarget - fatFloor * kcalPerGramFat - carbsFloor * kcalPerGramCarbs) / kcalPerGramProtein

        var protein = uncapped
        if uncapped > roomForProtein {
            protein = min(stepDownProtein(bodyMassKg: bodyMassKg, bodyFatPercent: bodyFatPercent, reference: reference, goals: goals),
                          roomForProtein.rounded(.down))
        }
        let minimum = (reference * max(proteinMinimumGramsPerKg, minimumProteinPerKg ?? 0)).rounded()
        var tooFew = false
        if protein < minimum {
            protein = minimum
            tooFew = true
        }
        protein = min(protein, uncapped)

        let remaining = calorieTarget - protein * kcalPerGramProtein
        let fat: Double
        let carbs: Double
        if tooFew {
            fat = fatFloor
            carbs = max(0, (remaining - fat * kcalPerGramFat) / kcalPerGramCarbs).rounded()
        } else {
            let fatCeiling = (remaining - carbsFloor * kcalPerGramCarbs) / kcalPerGramFat
            let preferred = calorieTarget * fatShareOfCalories / kcalPerGramFat
            fat = min(max(preferred, fatFloor), max(fatFloor, fatCeiling)).rounded()
            carbs = max(0, (remaining - fat * kcalPerGramFat) / kcalPerGramCarbs).rounded()
        }
        return MacroSplit(proteinGrams: protein, carbsGrams: carbs, fatGrams: fat, proteinGramsUncapped: uncapped,
                          carbsFloorGrams: carbsFloor, fatFloorGrams: fatFloor,
                          tooFewCaloriesForFloors: tooFew, calorieTarget: calorieTarget)
    }

    /// Lifters (muscle or strength focus, or losing weight, as in
    /// `NutritionTargets.proteinPerMeal`) get the 2 g/kg carb floor; with no
    /// goals, anyone past "untrained" does.
    static func isLifting(goals: Goals?, trainingStatus: TrainingStatus?) -> Bool {
        if let goals {
            return goals.focuses.contains(.muscle) || goals.focuses.contains(.strength) || goals.weight == .lose
        }
        return (trainingStatus ?? .novice) != .untrained
    }

    /// The bottom of the deficit range: 2.3 g/kg lean mass (Helms 2014) with
    /// body fat, else 2.0 g/kg (Phillips & Van Loon 2011). Outside a deficit
    /// the goal target is already 1.2-1.6 g/kg, so there is nothing to step to.
    static func stepDownProtein(bodyMassKg: Double, bodyFatPercent: Double?, reference: Double, goals: Goals?) -> Double {
        guard let goals, goals.weight == .lose else { return reference * GoalPlanner.proteinPerKg(goals ?? Goals()) }
        if let fat = bodyFatPercent, fat > 3, fat < 60 {
            return (bodyMassKg * (1 - fat / 100) * deficitProteinLowPerKgLeanMass).rounded()
        }
        return (reference * deficitProteinLowPerKg).rounded()
    }

    // MARK: Text

    /// "Protein 145 g · Carbs about 163 g (at least 148) · Fat at least 52 g".
    /// Each macro shows the same target its bar fills to (`carbsGrams`,
    /// `fatGrams`), with the floor beside it when the two differ: above the
    /// floors the split is flexible (Helms 2014).
    public var summaryLine: String {
        let carbs = Self.targetText(target: carbsGrams, floor: carbsFloorGrams, floorHolds: !tooFewCaloriesForFloors)
        let fat = Self.targetText(target: fatGrams, floor: fatFloorGrams, floorHolds: true)
        return "Protein \(Int(proteinGrams)) g · Carbs \(carbs) · Fat \(fat)"
    }

    /// "at least 52 g" when the target sits on its floor, "about 163 g (at
    /// least 148)" above it, and just "about 90 g" when the floor doesn't fit.
    static func targetText(target: Double, floor: Double, floorHolds: Bool) -> String {
        guard floorHolds else { return "about \(Int(target)) g" }
        if target - floor < 1 { return "at least \(Int(floor)) g" }
        return "about \(Int(target)) g (at least \(Int(floor)))"
    }

    /// One line for when protein was lowered, or nil.
    public var capNote: String? {
        if tooFewCaloriesForFloors {
            return "\(Int(calorieTarget)) kcal is too little for \(Int(proteinGrams)) g of protein plus enough carbs and fat; a slower rate in Goals fixes this."
        }
        guard proteinWasCapped else { return nil }
        return "Protein \(Int(proteinGrams)) g: the usual \(Int(proteinGramsUncapped)) g doesn't fit \(Int(calorieTarget)) kcal alongside enough carbs and fat."
    }
}
