import Foundation

// MARK: - Supplements and blood tests on the vitamins page

/// Food logs miss what people take as pills. A supplement the user lists (and
/// marks as taken) counts toward its nutrient's 7-day average, and a blood
/// test for that nutrient is shown next to it, since a test says more about
/// your status than intake does (NIH Office of Dietary Supplements fact
/// sheets: serum 25(OH)D for vitamin D, ferritin for iron stores).
extension Micronutrients {
    /// One supplement dose taken, as the user wrote it ("Vitamin D", "2000 IU").
    public struct SupplementDose: Sendable, Equatable {
        public var name: String
        public var dose: String

        public init(name: String, dose: String) {
            self.name = name
            self.dose = dose
        }
    }

    /// The nutrient a supplement supplies, from its name; nil for anything
    /// else (creatine, fish oil, a multivitamin with no single amount).
    public static func supplementNutrient(name: String) -> Nutrient? {
        let text = name.lowercased()
        let keys: [(String, Nutrient)] = [
            ("vitamin d", .vitaminD), ("vit d", .vitaminD), ("cholecalciferol", .vitaminD), ("d3", .vitaminD),
            ("magnesium", .magnesium), ("zinc", .zinc), ("iron", .iron), ("ferrous", .iron),
            ("vitamin c", .vitaminC), ("ascorbic", .vitaminC), ("b12", .vitaminB12), ("cobalamin", .vitaminB12),
            ("folic", .folate), ("folate", .folate), ("calcium", .calcium), ("selenium", .selenium),
            ("potassium", .potassium), ("vitamin a", .vitaminA),
        ]
        if text.contains("multi") { return nil }
        return keys.first { text.contains($0.0) }?.1
    }

    /// The amount one dose adds, in the nutrient's own unit (`Nutrient.unit`).
    /// "2000 IU" of vitamin D is 50 µg (40 IU = 1 µg; NIH ODS vitamin D fact
    /// sheet). IU for other nutrients differs by form, so it isn't converted.
    /// Nil when the dose has no number or unit the app can read.
    public static func supplementAmount(_ dose: SupplementDose) -> (nutrient: Nutrient, amount: Double)? {
        guard let nutrient = supplementNutrient(name: dose.name) else { return nil }
        let text = dose.dose.lowercased().replacingOccurrences(of: ",", with: "")
        guard let match = text.firstMatch(of: /([0-9]+(?:\.[0-9]+)?)\s*(iu|mcg|µg|ug|mg|g)\b/),
              let number = Double(match.1) else { return nil }
        let unit = String(match.2)
        let target = nutrient.unit
        let amount: Double?
        switch (unit, target) {
        case ("iu", "µg"): amount = nutrient == .vitaminD ? number / 40 : nil
        case ("iu", _): amount = nil
        case ("mcg", "µg"), ("µg", "µg"), ("ug", "µg"), ("mg", "mg"), ("g", "g"): amount = number
        case ("mg", "µg"): amount = number * 1000
        case ("g", "mg"): amount = number * 1000
        case ("mcg", "mg"), ("µg", "mg"), ("ug", "mg"): amount = number / 1000
        case ("mg", "g"): amount = number / 1000
        default: amount = nil
        }
        guard let amount, amount > 0 else { return nil }
        return (nutrient, amount)
    }

    /// Daily average per nutrient of the doses taken over `days` days.
    public static func supplementAverages(_ taken: [SupplementDose], days: Int) -> [Nutrient: Double] {
        guard days > 0 else { return [:] }
        var totals: [Nutrient: Double] = [:]
        for dose in taken {
            if let found = supplementAmount(dose) { totals[found.nutrient, default: 0] += found.amount }
        }
        return totals.mapValues { $0 / Double(days) }
    }

    /// Food and supplement averages together, assessed as one intake; each
    /// finding keeps how much came from supplements.
    public static func assess(averages: [Nutrient: Double], supplements: [Nutrient: Double], daysLogged: Int,
                              sex: BiologicalSex, age: Int = 30) -> [Finding] {
        let combined = averages.merging(supplements.filter { averages[$0.key] != nil }) { $0 + $1 }
        return assess(averages: combined, daysLogged: daysLogged, sex: sex, age: age).map { finding in
            var finding = finding
            finding.fromSupplements = supplements[finding.nutrient] ?? 0
            return finding
        }
    }

    /// Findings that are over the upper limit, worst first.
    public static func tooHigh(_ findings: [Finding]) -> [Finding] {
        findings.filter { $0.kind == .high }.sorted { $0.percentOfTarget > $1.percentOfTarget }
    }
}

extension Micronutrients.Nutrient {
    /// The blood test for this nutrient's status (`LabMarkers`), if there is one.
    public var labMarkerID: String? {
        switch self {
        case .vitaminD: "vitaminD"
        case .iron: "ferritin"
        case .vitaminB12: "b12"
        case .folate: "folate"
        case .magnesium: "magnesium"
        default: nil
        }
    }
}
