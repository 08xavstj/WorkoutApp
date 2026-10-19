import Foundation

/// Common blood tests with their usual units and typical adult reference
/// ranges, for entering results by hand and grouping imported ones. Ranges
/// vary between labs, so a range printed on your report always wins; these
/// are only defaults. Sources: Mayo Clinic Laboratories reference values;
/// ADA Standards of Care 2025 (HbA1c, fasting glucose); NCEP ATP III / AHA
/// (lipids); IOM 2011 (vitamin D); Travison et al., J Clin Endocrinol Metab
/// 2017 (testosterone); AHA/CDC (hs-CRP); KDIGO 2024 (eGFR).
public enum LabMarkers {
    public struct UnitOption: Sendable, Equatable, Identifiable {
        public var unit: String
        /// Typical range for men and for women (often the same).
        public var male: ClosedRange<Double>?
        public var female: ClosedRange<Double>?
        /// For "under X" markers (e.g. LDL), the upper limit only.
        public var maleHigh: Double?
        public var femaleHigh: Double?
        /// For "at least X" markers (e.g. HDL, eGFR), the lower limit only.
        public var maleLow: Double?
        public var femaleLow: Double?
        public var id: String { unit }

        public func range(for sex: BiologicalSex) -> (low: Double?, high: Double?) {
            let range = sex == .male ? male : (female ?? male)
            if let range { return (range.lowerBound, range.upperBound) }
            let high = sex == .male ? maleHigh : (femaleHigh ?? maleHigh)
            let low = sex == .male ? maleLow : (femaleLow ?? maleLow)
            return (low, high)
        }
    }

    public struct Marker: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var panel: String
        /// Other names labs print, lowercased.
        public var aliases: [String]
        public var units: [UnitOption]
        /// What it tells you, in plain words.
        public var about: String
    }

    static func u(_ unit: String, _ male: ClosedRange<Double>? = nil, female: ClosedRange<Double>? = nil,
                  high: Double? = nil, femaleHigh: Double? = nil, low: Double? = nil, femaleLow: Double? = nil) -> UnitOption {
        UnitOption(unit: unit, male: male, female: female, maleHigh: high, femaleHigh: femaleHigh, maleLow: low, femaleLow: femaleLow)
    }

    public static let all: [Marker] = [
        Marker(id: "ldl", name: "LDL cholesterol", panel: "Lipids", aliases: ["ldl", "ldl-c", "ldl cholesterol", "ldl chol calc", "ldl cholesterol calculated"],
               units: [u("mg/dL", high: 100), u("mmol/L", high: 2.6)],
               about: "The main cholesterol that builds up in arteries. Lower is better; targets depend on your overall heart risk."),
        Marker(id: "hdl", name: "HDL cholesterol", panel: "Lipids", aliases: ["hdl", "hdl-c", "hdl cholesterol"],
               units: [u("mg/dL", low: 40, femaleLow: 50), u("mmol/L", low: 1.0, femaleLow: 1.3)],
               about: "\"Good\" cholesterol. Regular exercise tends to raise it."),
        Marker(id: "totalCholesterol", name: "Total cholesterol", panel: "Lipids", aliases: ["total cholesterol", "cholesterol", "cholesterol, total"],
               units: [u("mg/dL", high: 200), u("mmol/L", high: 5.2)],
               about: "All cholesterol together. LDL and HDL say more on their own."),
        Marker(id: "triglycerides", name: "Triglycerides", panel: "Lipids", aliases: ["triglycerides", "trig", "tg"],
               units: [u("mg/dL", high: 150), u("mmol/L", high: 1.7)],
               about: "Fat in the blood. Rises with excess calories, refined carbs and alcohol; falls with exercise."),
        Marker(id: "apoB", name: "ApoB", panel: "Lipids", aliases: ["apob", "apolipoprotein b"],
               units: [u("mg/dL", high: 100), u("g/L", high: 1.0)],
               about: "Counts the particles that carry cholesterol into arteries; a sharper heart-risk measure than LDL."),
        Marker(id: "hba1c", name: "HbA1c", panel: "Blood sugar", aliases: ["hba1c", "a1c", "hemoglobin a1c", "haemoglobin a1c", "glycated hemoglobin"],
               units: [u("%", high: 5.6), u("mmol/mol", high: 38)],
               about: "Average blood sugar over about 3 months. 5.7-6.4% is the prediabetes range; 6.5% or more suggests diabetes."),
        Marker(id: "glucose", name: "Fasting glucose", panel: "Blood sugar", aliases: ["glucose", "fasting glucose", "glucose, fasting", "glucose fasting"],
               units: [u("mg/dL", 70...99), u("mmol/L", 3.9...5.5)],
               about: "Blood sugar after not eating for 8 hours. 100-125 mg/dL (5.6-6.9 mmol/L) is the prediabetes range."),
        Marker(id: "ferritin", name: "Ferritin", panel: "Iron", aliases: ["ferritin"],
               units: [u("ng/mL", 24...336, female: 11...307), u("µg/L", 24...336, female: 11...307)],
               about: "Your iron stores. Low ferritin causes tiredness and poorer endurance, even before anaemia shows."),
        Marker(id: "hemoglobin", name: "Hemoglobin", panel: "Blood count", aliases: ["hemoglobin", "haemoglobin", "hgb", "hb"],
               units: [u("g/dL", 13.2...16.6, female: 11.6...15.0), u("g/L", 132...166, female: 116...150)],
               about: "Carries oxygen in red blood cells. Low means anaemia; endurance suffers."),
        Marker(id: "hematocrit", name: "Hematocrit", panel: "Blood count", aliases: ["hematocrit", "haematocrit", "hct"],
               units: [u("%", 38.3...48.6, female: 35.5...44.9), u("L/L", 0.383...0.486, female: 0.355...0.449)],
               about: "The share of blood made of red cells. Testosterone therapy can push it high, which needs checking."),
        Marker(id: "vitaminD", name: "Vitamin D (25-OH)", panel: "Vitamins", aliases: ["vitamin d", "25-oh vitamin d", "25-hydroxyvitamin d", "vitamin d, 25-hydroxy", "25(oh)d"],
               units: [u("ng/mL", 20...50), u("nmol/L", 50...125)],
               about: "20 ng/mL (50 nmol/L) or more covers bone health for nearly everyone; much higher levels have no proven extra benefit (IOM 2011)."),
        Marker(id: "b12", name: "Vitamin B12", panel: "Vitamins", aliases: ["vitamin b12", "b12", "cobalamin"],
               units: [u("pg/mL", 200...900), u("pmol/L", 148...664)],
               about: "Needed for red blood cells and nerves. Plant-based diets and metformin can lower it."),
        Marker(id: "tsh", name: "TSH", panel: "Thyroid", aliases: ["tsh", "thyroid stimulating hormone", "thyrotropin"],
               units: [u("mIU/L", 0.4...4.0), u("mU/L", 0.4...4.0)],
               about: "Thyroid control hormone. High TSH can mean an underactive thyroid (tiredness, weight gain); low can mean overactive."),
        Marker(id: "testosterone", name: "Testosterone (total)", panel: "Hormones", aliases: ["testosterone", "total testosterone", "testosterone, total"],
               units: [u("ng/dL", 264...916, female: 15...70), u("nmol/L", 9.2...31.8, female: 0.5...2.4)],
               about: "Typical range for healthy young men from a harmonised reference (Travison et al. 2017). Best measured in the morning."),
        Marker(id: "crp", name: "hs-CRP", panel: "Inflammation", aliases: ["hs-crp", "hscrp", "crp", "c-reactive protein", "high sensitivity crp"],
               units: [u("mg/L", high: 3), u("mg/dL", high: 0.3)],
               about: "Inflammation. Under 1 mg/L is low heart risk, 1-3 average, over 3 higher. A cold or a hard workout raises it for days."),
        Marker(id: "creatinine", name: "Creatinine", panel: "Kidney", aliases: ["creatinine", "creat"],
               units: [u("mg/dL", 0.74...1.35, female: 0.59...1.04), u("µmol/L", 65...119, female: 52...92)],
               about: "A muscle waste product cleared by the kidneys. Creatine supplements and lots of muscle raise it without kidney harm."),
        Marker(id: "egfr", name: "eGFR", panel: "Kidney", aliases: ["egfr", "estimated gfr", "gfr"],
               units: [u("mL/min/1.73m²", low: 60), u("mL/min", low: 60)],
               about: "Estimated kidney filtering, worked out from creatinine. Under 60 for 3 months is chronic kidney disease (KDIGO); muscular people and creatine users can read falsely low."),
        Marker(id: "alt", name: "ALT", panel: "Liver", aliases: ["alt", "alanine aminotransferase", "sgpt"],
               units: [u("U/L", 7...55, female: 7...45)],
               about: "A liver enzyme. Hard lifting can raise it (and AST) for several days, so test after 2-3 easy days."),
        Marker(id: "ast", name: "AST", panel: "Liver", aliases: ["ast", "aspartate aminotransferase", "sgot"],
               units: [u("U/L", 8...48, female: 8...43)],
               about: "An enzyme from liver and muscle. Rises after hard training as well as with liver strain."),
    ]

    public static func marker(id: String) -> Marker? {
        all.first { $0.id == id }
    }

    /// The catalog marker a printed test name refers to.
    public static func match(_ name: String) -> Marker? {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ,()\\-]", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
        // Different tests whose names contain a catalog name.
        if cleaned.contains("non-hdl") || cleaned.contains("non hdl") || cleaned.contains("ratio") { return nil }
        if let exact = all.first(where: { $0.aliases.contains(cleaned) || $0.name.lowercased() == cleaned }) {
            return exact
        }
        // Longest alias contained in the name, so "LDL Cholesterol Calc" beats "cholesterol".
        let candidates = all.flatMap { marker in marker.aliases.map { (marker, $0) } }
            .filter { alias in alias.1.count >= 3 && containsWord(cleaned, alias.1) }
        return candidates.max { $0.1.count < $1.1.count }?.0
    }

    static func containsWord(_ text: String, _ phrase: String) -> Bool {
        let pattern = "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: phrase) + "($|[^a-z0-9])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    public enum Status: String, Sendable {
        case low = "Low", inRange = "In range", high = "High"
    }

    public static func status(value: Double, low: Double?, high: Double?) -> Status? {
        if low == nil && high == nil { return nil }
        if let low, value < low { return .low }
        if let high, value > high { return .high }
        return .inRange
    }
}
