import Foundation

/// Vitamins and minerals logged in Cronometer (via Apple Health), averaged
/// over the last week and compared with US Dietary Reference Intakes (IOM /
/// NASEM; NIH Office of Dietary Supplements), with adult age bands.
///
/// "Low" means below the Estimated Average Requirement (EAR), the level that
/// meets half of people's needs: for one person, intake below the EAR is
/// likely inadequate, while the RDA covers ~97.5% of people (IOM, DRI:
/// Applications in Dietary Assessment, 2000). Nutrients with only an Adequate
/// Intake (potassium, sodium, fibre) have no EAR; under 70% of the AI is
/// flagged as "may be low". A week of logging isn't usual intake, so findings
/// are worded as "may be". Only flags what research links to how you feel,
/// train, sleep or fight off illness.
public enum Micronutrients {
    public enum Nutrient: String, CaseIterable, Sendable, Codable {
        case vitaminC, vitaminD, zinc, iron, magnesium, potassium, sodium, calcium, vitaminB12, folate, vitaminA, selenium, fiber

        public var name: String {
            switch self {
            case .vitaminC: "Vitamin C"
            case .vitaminD: "Vitamin D"
            case .zinc: "Zinc"
            case .iron: "Iron"
            case .magnesium: "Magnesium"
            case .potassium: "Potassium"
            case .sodium: "Sodium"
            case .calcium: "Calcium"
            case .vitaminB12: "Vitamin B12"
            case .folate: "Folate"
            case .vitaminA: "Vitamin A"
            case .selenium: "Selenium"
            case .fiber: "Fiber"
            }
        }

        /// Unit the values are in.
        public var unit: String {
            switch self {
            case .vitaminD, .vitaminB12, .folate, .vitaminA, .selenium: "µg"
            case .fiber: "g"
            default: "mg"
            }
        }

        /// Daily target (RDA or Adequate Intake) for adults, by sex and age
        /// where they differ: NIH Office of Dietary Supplements fact sheets
        /// (Iron: 8 mg men and women 51+, 18 mg women 19-50; Magnesium: 400/420 mg
        /// men, 310/320 mg women by age 19-30/31+; Calcium: 1,000 mg, 1,200 mg
        /// women 51+ and men 71+; Vitamin D: 15 µg, 20 µg over 70; Zinc 11/8 mg;
        /// Vitamin C 90/75 mg; Vitamin A 900/700 µg RAE; Potassium 3,400/2,600 mg AI;
        /// Sodium 1,500 mg AI; B12 2.4 µg; Folate 400 µg DFE; Selenium 55 µg),
        /// which reproduce the IOM/NASEM DRI tables.
        public func target(_ sex: BiologicalSex, age: Int = 30) -> Double {
            let male = sex == .male
            switch self {
            case .vitaminC: return male ? 90 : 75
            case .vitaminD: return age > 70 ? 20 : 15
            case .zinc: return male ? 11 : 8
            case .iron: return male || age > 50 ? 8 : 18
            case .magnesium: return male ? (age < 31 ? 400 : 420) : (age < 31 ? 310 : 320)
            case .potassium: return male ? 3400 : 2600
            case .sodium: return 1500
            case .calcium: return (male ? age > 70 : age > 50) ? 1200 : 1000
            case .vitaminB12: return 2.4
            case .folate: return 400
            case .vitaminA: return male ? 900 : 700
            case .selenium: return 55
            // Reynolds et al., Lancet 2019: benefits rise to 25-29 g/day (NutritionTargets.fiberTargetGrams).
            case .fiber: return NutritionTargets.fiberTargetGrams.upperBound
            }
        }

        /// Estimated Average Requirement, where one exists (nil for AI-only nutrients).
        public func averageRequirement(_ sex: BiologicalSex, age: Int = 30) -> Double? {
            let male = sex == .male
            switch self {
            case .vitaminC: return male ? 75 : 60
            case .vitaminD: return 10
            case .zinc: return male ? 9.4 : 6.8
            case .iron: return male || age > 50 ? 6 : 8.1
            case .magnesium: return male ? (age < 31 ? 330 : 350) : (age < 31 ? 255 : 265)
            case .calcium: return (male ? age > 70 : age > 50) ? 1000 : 800
            case .vitaminB12: return 2.0
            case .folate: return 320
            case .vitaminA: return male ? 625 : 500
            case .selenium: return 45
            case .potassium, .sodium, .fiber: return nil
            }
        }

        /// Upper limit (or, for sodium, the 2,300 mg chronic-disease limit).
        /// Vitamin A has none here: its 3,000 µg limit is for preformed retinol
        /// only, and food logs report total vitamin A including carotenes
        /// from vegetables, which can't cause toxicity.
        public func upperLimit(age: Int = 30) -> Double? {
            switch self {
            case .vitaminC: 2000
            case .vitaminD: 100
            case .zinc: 40
            case .iron: 45
            case .sodium: 2300
            case .calcium: age > 50 ? 2000 : 2500
            case .selenium: 400
            default: nil
            }
        }

        /// What each one matters for in this app.
        public var areas: Set<Area> {
            switch self {
            case .vitaminC, .vitaminD, .zinc, .selenium, .vitaminA: [.immune]
            case .iron, .vitaminB12, .folate: [.energy]
            case .magnesium: [.sleep, .muscle]
            case .potassium, .sodium: [.hydration]
            case .calcium: [.muscle]
            case .fiber: [.energy]
            }
        }

        var lowEffect: String {
            switch self {
            case .vitaminC: "Vitamin C supports immune cells. In trials, regular vitamin C supplements roughly halved colds in people under heavy physical stress (e.g. marathon runners); for most people the effect on colds is small (Hemilä & Chalker, Cochrane 2013)."
            case .vitaminD: "Vitamin D supports bones and muscles, and food rarely covers it, so sun or a supplement usually does. Whether supplements prevent respiratory infections is unclear: a small benefit in earlier pooled trials was no longer significant after the largest trials were added (Jolliffe et al., Lancet Diabetes Endocrinol 2025)."
            case .zinc: "Zinc supports immune cells. Separately, zinc lozenges started at the first sign of a cold shortened colds by about a third in trials (Hemilä, JRSM Open 2017)."
            case .selenium: "Selenium supports immune and thyroid function."
            case .vitaminA: "Vitamin A supports immune defences in the airways and gut."
            case .iron: "Low iron causes tiredness, a higher heart rate at the same effort and lower endurance, especially in women and endurance athletes (Sim et al., Eur J Appl Physiol 2019)."
            case .vitaminB12: "Low B12 can cause tiredness and low energy; plant-based diets need a source."
            case .folate: "Folate is needed to make red blood cells; low intake can add to tiredness."
            case .magnesium: "Low magnesium is linked with poorer sleep and muscle cramps; most people fall short (Arab et al., Biol Trace Elem Res 2023 review)."
            case .potassium: "Potassium helps fluid balance and muscle contraction, and offsets sodium's effect on blood pressure."
            case .sodium: "Sodium is lost in sweat; very low intake on heavy training days can mean cramps and dizziness."
            case .calcium: "Calcium keeps bones strong under heavy training, together with vitamin D."
            case .fiber: "Low fibre means steadier energy and gut health are harder to keep up; most people eat about half the target."
            }
        }

        var highEffect: String {
            switch self {
            case .sodium: "Above the 2,300 mg guideline; fine on heavy sweating days, but regularly high sodium raises blood pressure."
            case .iron: "Above the 45 mg upper limit: iron supplements at this level can upset your stomach; check with your doctor."
            case .zinc: "Above the 40 mg upper limit: long-term high zinc can lower copper and immunity."
            case .vitaminD: "Above the 100 µg (4,000 IU) upper limit: high doses for months can raise calcium too much."
            default: "Above the upper limit; mostly a concern with supplements."
            }
        }
    }

    public enum Area: String, Sendable, Codable, CaseIterable {
        case immune, energy, sleep, muscle, hydration
    }

    public struct Finding: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable { case low, ok, high }
        public var nutrient: Nutrient
        public var average: Double
        public var target: Double
        public var kind: Kind
        public var effect: String?
        public var id: Nutrient { nutrient }
        public var percentOfTarget: Double { average / max(target, 0.0001) * 100 }
    }

    /// - Parameters:
    ///   - averages: 7-day daily averages.
    ///   - daysLogged: days with food logged in that window; needs at least 4.
    public static func assess(averages: [Nutrient: Double], daysLogged: Int, sex: BiologicalSex, age: Int = 30) -> [Finding] {
        guard daysLogged >= 4 else { return [] }
        return Nutrient.allCases.compactMap { nutrient in
            guard let average = averages[nutrient] else { return nil }
            let target = nutrient.target(sex, age: age)
            if let limit = nutrient.upperLimit(age: age), average > limit {
                return Finding(nutrient: nutrient, average: average, target: target, kind: .high, effect: nutrient.highEffect)
            }
            let lowLine = nutrient.averageRequirement(sex, age: age) ?? target * 0.7
            if average < lowLine {
                return Finding(nutrient: nutrient, average: average, target: target, kind: .low, effect: nutrient.lowEffect)
            }
            return Finding(nutrient: nutrient, average: average, target: target, kind: .ok, effect: nil)
        }
    }

    /// Short notes for one area (e.g. the illness watch uses `.immune`).
    public static func notes(_ findings: [Finding], area: Area) -> [String] {
        findings.filter { $0.kind == .low && $0.nutrient.areas.contains(area) }
            .map { "\($0.nutrient.name) may be low: it has averaged \(Int($0.percentOfTarget.rounded()))% of target this week." }
    }
}

// MARK: - What to fix: food sources and the one-line summary

extension Micronutrients {
    /// A food that is rich in one nutrient, with its content per 100 g from
    /// USDA FoodData Central (SR Legacy / Foundation Foods; values rounded).
    /// Cronometer uses the same database, so the amounts line up with the log.
    public struct FoodSource: Sendable, Equatable {
        public var name: String
        /// Amount of the nutrient (in the nutrient's unit) per 100 g of food.
        public var perHundredGrams: Double
        /// The largest portion worth suggesting, in grams (a handful of seeds,
        /// a plate of spinach), so fixes stay realistic.
        public var maxGrams: Double
        /// Short note shown with the food ("non-heme iron: pair with vitamin C").
        public var note: String?
        public var source: String { "USDA FoodData Central" }
    }

    /// One concrete fix: this much of this food adds this much of the nutrient.
    public struct FoodFix: Sendable, Equatable, Identifiable {
        public var food: FoodSource
        public var grams: Double
        public var amount: Double
        public var id: String { food.name }
        /// Whether this portion alone closes the gap to the target.
        public var closesGap: Bool
    }

    /// About three foods per nutrient, all from USDA FoodData Central (per 100 g).
    public static func foodSources(_ nutrient: Nutrient) -> [FoodSource] {
        switch nutrient {
        case .magnesium: [
            // USDA FoodData Central: pumpkin seed kernels, roasted (SR 12016) ~550 mg; almonds (SR 12061) 270 mg; spinach, cooked (SR 11458) 87 mg.
            FoodSource(name: "pumpkin seeds", perHundredGrams: 550, maxGrams: 40),
            FoodSource(name: "almonds", perHundredGrams: 270, maxGrams: 50),
            FoodSource(name: "cooked spinach", perHundredGrams: 87, maxGrams: 150),
        ]
        case .iron: [
            // USDA: beef liver, cooked 6.5 mg; lentils, cooked 3.3 mg; spinach, cooked 3.6 mg (non-heme).
            FoodSource(name: "beef liver", perHundredGrams: 6.5, maxGrams: 100, note: "heme iron, well absorbed"),
            FoodSource(name: "cooked lentils", perHundredGrams: 3.3, maxGrams: 250, note: "non-heme: pair with vitamin C, keep tea and coffee an hour away"),
            FoodSource(name: "cooked spinach", perHundredGrams: 3.6, maxGrams: 150, note: "non-heme: pair with vitamin C"),
        ]
        case .vitaminC: [
            // USDA: red bell pepper, raw 128 mg; kiwifruit 93 mg; broccoli, cooked 65 mg.
            FoodSource(name: "red pepper", perHundredGrams: 128, maxGrams: 150),
            FoodSource(name: "kiwi", perHundredGrams: 93, maxGrams: 150),
            FoodSource(name: "cooked broccoli", perHundredGrams: 65, maxGrams: 200),
        ]
        case .vitaminD: [
            // USDA: Atlantic salmon, cooked ~11 µg; sardines, canned in oil 4.8 µg; whole egg 2.0 µg.
            // Food rarely covers vitamin D; sun or a supplement usually does (Owens et al., Sports Med 2018).
            FoodSource(name: "salmon", perHundredGrams: 11, maxGrams: 150),
            FoodSource(name: "canned sardines", perHundredGrams: 4.8, maxGrams: 120),
            FoodSource(name: "eggs", perHundredGrams: 2.0, maxGrams: 150),
        ]
        case .zinc: [
            // USDA: beef, ground 85% lean, cooked 6.3 mg; pumpkin seed kernels 7.8 mg; cashews 5.6 mg.
            FoodSource(name: "lean beef", perHundredGrams: 6.3, maxGrams: 150),
            FoodSource(name: "pumpkin seeds", perHundredGrams: 7.8, maxGrams: 40),
            FoodSource(name: "cashews", perHundredGrams: 5.6, maxGrams: 50),
        ]
        case .potassium: [
            // USDA: white beans, cooked 561 mg; potato, baked with skin 535 mg; banana 358 mg.
            FoodSource(name: "cooked white beans", perHundredGrams: 561, maxGrams: 250),
            FoodSource(name: "baked potato with skin", perHundredGrams: 535, maxGrams: 300),
            FoodSource(name: "banana", perHundredGrams: 358, maxGrams: 240),
        ]
        case .sodium: [
            // USDA: green olives, brined 1,556 mg; feta 917 mg; dill pickles 809 mg. Mostly a heavy-sweat-day fix.
            FoodSource(name: "olives", perHundredGrams: 1556, maxGrams: 60),
            FoodSource(name: "feta", perHundredGrams: 917, maxGrams: 60),
            FoodSource(name: "pickles", perHundredGrams: 809, maxGrams: 100),
        ]
        case .calcium: [
            // USDA: cheddar 710 mg; sardines, canned with bones 382 mg; plain low-fat yogurt 183 mg.
            FoodSource(name: "cheddar", perHundredGrams: 710, maxGrams: 50),
            FoodSource(name: "canned sardines", perHundredGrams: 382, maxGrams: 120),
            FoodSource(name: "plain yogurt", perHundredGrams: 183, maxGrams: 300),
        ]
        case .vitaminB12: [
            // USDA: sardines, canned 8.9 µg; beef, cooked 2.6 µg; whole egg 1.1 µg. Plant-based: fortified foods or a supplement (Rogerson, JISSN 2017).
            FoodSource(name: "canned sardines", perHundredGrams: 8.9, maxGrams: 120),
            FoodSource(name: "lean beef", perHundredGrams: 2.6, maxGrams: 150),
            FoodSource(name: "eggs", perHundredGrams: 1.1, maxGrams: 150, note: "plant-based diets need fortified foods or a supplement"),
        ]
        case .folate: [
            // USDA: spinach, raw 194 µg; lentils, cooked 181 µg; asparagus, cooked 149 µg.
            FoodSource(name: "raw spinach", perHundredGrams: 194, maxGrams: 100),
            FoodSource(name: "cooked lentils", perHundredGrams: 181, maxGrams: 250),
            FoodSource(name: "cooked asparagus", perHundredGrams: 149, maxGrams: 150),
        ]
        case .vitaminA: [
            // USDA (RAE): sweet potato, baked 961 µg; carrots, raw 835 µg; spinach, cooked 524 µg.
            FoodSource(name: "baked sweet potato", perHundredGrams: 961, maxGrams: 200),
            FoodSource(name: "carrots", perHundredGrams: 835, maxGrams: 150),
            FoodSource(name: "cooked spinach", perHundredGrams: 524, maxGrams: 150),
        ]
        case .selenium: [
            // USDA: Brazil nuts 1,917 µg (one or two nuts a day; the upper limit is 400 µg); tuna, cooked 108 µg; whole egg 31 µg.
            FoodSource(name: "Brazil nuts", perHundredGrams: 1917, maxGrams: 10, note: "one or two nuts; more goes over the upper limit"),
            FoodSource(name: "tuna", perHundredGrams: 108, maxGrams: 150),
            FoodSource(name: "eggs", perHundredGrams: 31, maxGrams: 150),
        ]
        case .fiber: [
            // USDA: chia seeds 34 g; cooked lentils 7.9 g; raspberries 6.5 g.
            FoodSource(name: "chia seeds", perHundredGrams: 34, maxGrams: 30),
            FoodSource(name: "cooked lentils", perHundredGrams: 7.9, maxGrams: 250),
            FoodSource(name: "raspberries", perHundredGrams: 6.5, maxGrams: 200),
        ]
        }
    }

    /// The portion of each food that would close the gap to the target (rounded
    /// up to 5 g under 30 g, else 10 g), capped at a realistic serving. Up to
    /// three fixes, the ones that close the gap first.
    public static func fixes(for finding: Finding, limit: Int = 3) -> [FoodFix] {
        let gap = finding.target - finding.average
        guard gap > 0 else { return [] }
        let fixes = foodSources(finding.nutrient).map { food -> FoodFix in
            let exact = gap / food.perHundredGrams * 100
            let step: Double = exact < 30 ? 5 : 10
            let grams = min(food.maxGrams, max(step, (exact / step).rounded(.up) * step))
            let amount = grams * food.perHundredGrams / 100
            return FoodFix(food: food, grams: grams, amount: amount, closesGap: amount >= gap - 0.0001)
        }
        return Array(fixes.sorted { a, b in
            if a.closesGap != b.closesGap { return a.closesGap }
            return a.amount > b.amount
        }.prefix(limit))
    }

    /// Low findings, worst first: what the page lists under "What to fix".
    public static func toFix(_ findings: [Finding]) -> [Finding] {
        findings.filter { $0.kind == .low }.sorted { $0.percentOfTarget < $1.percentOfTarget }
    }

    /// One line for Today's Up next / Nutrition, or nil when there's nothing to
    /// show (fewer than 4 logged days). "3 low this week: magnesium, iron and vitamin D".
    public static func summaryLine(findings: [Finding]) -> String? {
        guard !findings.isEmpty else { return nil }
        let low = toFix(findings)
        guard !low.isEmpty else { return "Vitamins and minerals near target this week" }
        let names = low.prefix(3).map { finding -> String in
            let name = finding.nutrient.name
            return name.prefix(1).lowercased() + name.dropFirst()
        }
        let list: String
        switch names.count {
        case 1: list = names[0]
        case 2: list = "\(names[0]) and \(names[1])"
        default: list = "\(names[0]), \(names[1]) and \(names[2])"
        }
        let more = low.count > 3 ? " and \(low.count - 3) more" : ""
        return "\(low.count) low this week: \(list)\(more)"
    }

    /// Where evidence suggests athletes need more than the RDA (IOC consensus,
    /// Maughan et al., Br J Sports Med 2018;52:439-55). Targets are not raised:
    /// the RDA is a population target and the IOC's advice is to test, not to
    /// supplement on intake alone.
    public static func athleteNote(_ nutrient: Nutrient, sex: BiologicalSex, focuses: [Goals.Focus]) -> String? {
        switch nutrient {
        case .iron where sex == .female && focuses.contains(.endurance):
            // Maughan et al. 2018; Sim et al., Eur J Appl Physiol 2019: iron deficiency is common in female endurance athletes.
            return "Women who train for endurance lose more iron (sweat, foot-strike, periods) and are often low. Worth a ferritin test before any supplement."
        case .iron where focuses.contains(.endurance):
            return "Endurance training raises iron losses a little; a ferritin blood test tells you more than intake does (IOC consensus 2018)."
        case .vitaminD:
            // Maughan et al. 2018; Owens et al., Sports Med 2018: indoor and winter training raise deficiency risk.
            return "If you train mostly indoors or it's winter, food won't cover vitamin D; a 25(OH)D blood test settles it (IOC consensus 2018)."
        case .calcium where sex == .female:
            // Maughan et al. 2018: low energy availability in women raises bone needs; the IOC notes calcium with vitamin D.
            return "Bone needs calcium and vitamin D together, especially when eating less than you burn for long stretches (IOC consensus 2018)."
        default:
            return nil
        }
    }
}
