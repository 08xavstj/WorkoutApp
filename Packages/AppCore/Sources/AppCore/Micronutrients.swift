import Foundation

/// Vitamins and minerals logged in Cronometer (via Apple Health), averaged
/// over the last week and compared with US Dietary Reference Intakes (NIH
/// Office of Dietary Supplements; adults 19-50). Only flags what research
/// links to how you feel, train, sleep or fight off illness.
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

        /// Daily target (RDA or Adequate Intake).
        public func target(_ sex: BiologicalSex) -> Double {
            let male = sex == .male
            switch self {
            case .vitaminC: return male ? 90 : 75
            case .vitaminD: return 15
            case .zinc: return male ? 11 : 8
            case .iron: return male ? 8 : 18
            case .magnesium: return male ? 410 : 315
            case .potassium: return male ? 3400 : 2600
            case .sodium: return 1500
            case .calcium: return 1000
            case .vitaminB12: return 2.4
            case .folate: return 400
            case .vitaminA: return male ? 900 : 700
            case .selenium: return 55
            case .fiber: return male ? 38 : 25
            }
        }

        /// Upper limit (or, for sodium, the 2,300 mg chronic-disease limit).
        public var upperLimit: Double? {
            switch self {
            case .vitaminC: 2000
            case .vitaminD: 100
            case .zinc: 40
            case .iron: 45
            case .sodium: 2300
            case .calcium: 2500
            case .vitaminA: 3000
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
            case .vitaminC: "Low vitamin C weakens immune defences; regular intake shortens colds, and halves them in people under heavy physical stress (Hemilä & Chalker, Cochrane 2013)."
            case .vitaminD: "Low vitamin D is linked with more respiratory infections; daily vitamin D lowered infection risk in trials, most in people who were low (Martineau et al., BMJ 2017). Food rarely covers it, so sun or a supplement usually does."
            case .zinc: "Zinc supports immune cells; low intake makes colds more likely and longer (Hemilä, JRSM Open 2017)."
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
    public static func assess(averages: [Nutrient: Double], daysLogged: Int, sex: BiologicalSex) -> [Finding] {
        guard daysLogged >= 4 else { return [] }
        return Nutrient.allCases.compactMap { nutrient in
            guard let average = averages[nutrient] else { return nil }
            let target = nutrient.target(sex)
            if let limit = nutrient.upperLimit, average > limit {
                return Finding(nutrient: nutrient, average: average, target: target, kind: .high, effect: nutrient.highEffect)
            }
            if average < target * 0.7 {
                return Finding(nutrient: nutrient, average: average, target: target, kind: .low, effect: nutrient.lowEffect)
            }
            return Finding(nutrient: nutrient, average: average, target: target, kind: .ok, effect: nil)
        }
    }

    /// Short notes for one area (e.g. the illness watch uses `.immune`).
    public static func notes(_ findings: [Finding], area: Area) -> [String] {
        findings.filter { $0.kind == .low && $0.nutrient.areas.contains(area) }
            .map { "\($0.nutrient.name) has averaged \(Int($0.percentOfTarget.rounded()))% of target this week." }
    }
}
