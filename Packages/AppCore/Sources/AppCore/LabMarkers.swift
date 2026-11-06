import Foundation

/// Common blood tests with their usual units and typical adult reference
/// ranges, for entering results by hand and grouping imported ones. Ranges
/// vary between labs, so a range printed on your report always wins; these
/// are only defaults. Sources: Mayo Clinic Laboratories reference values;
/// ADA Standards of Care 2025 (HbA1c, fasting glucose); NCEP ATP III / AHA
/// (lipids); ESC/EAS 2019 (ApoB); Kronenberg et al., Eur Heart J 2022 (EAS
/// consensus on Lp(a)); IOM 2011 (vitamin D); Travison et al., J Clin
/// Endocrinol Metab 2017 (testosterone); AHA/CDC (hs-CRP); KDIGO 2024 (eGFR);
/// Sim et al., Eur J Appl Physiol 2019 (iron in athletes). Folate, magnesium
/// and uric acid ranges are typical lab values (Mayo; from memory in the
/// audit), so the wording stays cautious. Retest cadences come from the same
/// guidelines and the November 2026 research round (Johannesen et al., JACC
/// 2021 for ApoB). This catalog tracks results; it doesn't diagnose.
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
        /// A second, stricter floor for people who train (both sexes), where
        /// sports-medicine reviews set one (ferritin: Sim et al. 2019).
        public var athleteLow: Double?
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
        /// How often it's worth repeating, where a guideline or the research
        /// round says; nil when it's "whenever your doctor orders it".
        public var retest: String? = nil
    }

    static func u(_ unit: String, _ male: ClosedRange<Double>? = nil, female: ClosedRange<Double>? = nil,
                  high: Double? = nil, femaleHigh: Double? = nil, low: Double? = nil, femaleLow: Double? = nil,
                  athleteLow: Double? = nil) -> UnitOption {
        UnitOption(unit: unit, male: male, female: female, maleHigh: high, femaleHigh: femaleHigh, maleLow: low, femaleLow: femaleLow,
                   athleteLow: athleteLow)
    }

    /// Lipids and HbA1c: every 1-2 years when normal (guideline practice; health-metrics report).
    static let lipidRetest = "Every 1-2 years if normal, and about 3 months after a big change in diet or weight."

    public static let all: [Marker] = [
        Marker(id: "ldl", name: "LDL cholesterol", panel: "Lipids", aliases: ["ldl", "ldl-c", "ldl cholesterol", "ldl chol calc", "ldl cholesterol calculated"],
               units: [u("mg/dL", high: 100), u("mmol/L", high: 2.6)],
               about: "The main cholesterol that builds up in arteries. Lower is better; targets depend on your overall heart risk.",
               retest: lipidRetest),
        Marker(id: "hdl", name: "HDL cholesterol", panel: "Lipids", aliases: ["hdl", "hdl-c", "hdl cholesterol"],
               units: [u("mg/dL", low: 40, femaleLow: 50), u("mmol/L", low: 1.0, femaleLow: 1.3)],
               about: "\"Good\" cholesterol. Regular exercise tends to raise it.",
               retest: lipidRetest),
        Marker(id: "totalCholesterol", name: "Total cholesterol", panel: "Lipids", aliases: ["total cholesterol", "cholesterol", "cholesterol, total"],
               units: [u("mg/dL", high: 200), u("mmol/L", high: 5.2)],
               about: "All cholesterol together. LDL and HDL say more on their own.",
               retest: lipidRetest),
        Marker(id: "triglycerides", name: "Triglycerides", panel: "Lipids", aliases: ["triglycerides", "trig", "tg"],
               units: [u("mg/dL", high: 150), u("mmol/L", high: 1.7)],
               about: "Fat in the blood. Rises with excess calories, refined carbs and alcohol; falls with exercise.",
               retest: lipidRetest),
        Marker(id: "apoB", name: "ApoB", panel: "Lipids", aliases: ["apob", "apolipoprotein b"],
               units: [u("mg/dL", high: 100), u("g/L", high: 1.0)],
               about: "Counts the particles that carry cholesterol into arteries; a sharper heart-risk measure than LDL, and the one to watch if LDL looks fine but ApoB doesn't (Johannesen et al. 2021). Under 100 mg/dL is the usual goal; European guidelines use under 80 at high risk.",
               // Johannesen et al., JACC 2021 (discordant ApoB); health-metrics report: re-test after a bulk.
               retest: "Every 1-2 years if normal, and after a long bulk (a surplus with lots of saturated fat raises it)."),
        // EAS consensus (Kronenberg et al., Eur Heart J 2022; from memory in the audit): > 50 mg/dL or > 125 nmol/L high, 30-50 grey zone.
        Marker(id: "lpa", name: "Lp(a)", panel: "Lipids", aliases: ["lp(a)", "lpa", "lipoprotein(a)", "lipoprotein (a)", "lipoprotein a"],
               units: [u("mg/dL", high: 50), u("nmol/L", high: 125)],
               about: "A cholesterol particle whose level is set by your genes and barely moves with diet or training. Above about 50 mg/dL (125 nmol/L) counts as high and means keeping every other heart-risk number tight; 30-50 mg/dL is a grey zone (EAS consensus, Kronenberg et al. 2022).",
               retest: "Once in a lifetime is enough: it's genetic and stays put."),
        Marker(id: "hba1c", name: "HbA1c", panel: "Blood sugar", aliases: ["hba1c", "a1c", "hemoglobin a1c", "haemoglobin a1c", "glycated hemoglobin"],
               units: [u("%", high: 5.6), u("mmol/mol", high: 38)],
               about: "Average blood sugar over about 3 months. 5.7-6.4% is the prediabetes range; 6.5% is the diagnostic threshold doctors use, and it needs a repeat test.",
               retest: "Yearly if normal."),
        Marker(id: "glucose", name: "Fasting glucose", panel: "Blood sugar", aliases: ["glucose", "fasting glucose", "glucose, fasting", "glucose fasting"],
               units: [u("mg/dL", 70...99), u("mmol/L", 3.9...5.5)],
               about: "Blood sugar after not eating for 8 hours. 100-125 mg/dL (5.6-6.9 mmol/L) is the prediabetes range. A hard session or a high-protein meal the day before can nudge it up.",
               retest: "Yearly if normal; test fasted and rested."),
        // Sim et al., Eur J Appl Physiol 2019 (after Peeling 2007): in athletes ferritin < 35 µg/L is stage-1 iron
        // deficiency and < 20 stage 2 (thresholds from memory in the audit); the app flags under 30 for both sexes.
        Marker(id: "ferritin", name: "Ferritin", panel: "Iron", aliases: ["ferritin"],
               units: [u("ng/mL", 24...336, female: 11...307, athleteLow: 30), u("µg/L", 24...336, female: 11...307, athleteLow: 30)],
               about: "Your iron stores. Low ferritin causes tiredness and poorer endurance, even before anaemia shows. The lab range is a population spread, not a health line: under about 30 µg/L is low for someone who trains, whatever your sex (Sim et al. 2019). Ferritin also rises with inflammation, illness and hard training, so a normal value after a cold or a heavy week can hide low stores.",
               retest: "Yearly if you do a lot of endurance work or have periods, or when you're tired and stalling; test when well-rested and not ill."),
        Marker(id: "hemoglobin", name: "Hemoglobin", panel: "Blood count", aliases: ["hemoglobin", "haemoglobin", "hgb", "hb"],
               units: [u("g/dL", 13.2...16.6, female: 11.6...15.0), u("g/L", 132...166, female: 116...150)],
               about: "Carries oxygen in red blood cells. Low means anaemia; endurance suffers. Endurance training thins the blood a little, so athletes often run slightly lower."),
        Marker(id: "hematocrit", name: "Hematocrit", panel: "Blood count", aliases: ["hematocrit", "haematocrit", "hct"],
               units: [u("%", 38.3...48.6, female: 35.5...44.9), u("L/L", 0.383...0.486, female: 0.355...0.449)],
               about: "The share of blood made of red cells. Testosterone therapy can push it high, which needs checking."),
        Marker(id: "vitaminD", name: "Vitamin D (25-OH)", panel: "Vitamins", aliases: ["vitamin d", "25-oh vitamin d", "25-hydroxyvitamin d", "vitamin d, 25-hydroxy", "25(oh)d"],
               units: [u("ng/mL", 20...50), u("nmol/L", 50...125)],
               about: "20 ng/mL (50 nmol/L) or more covers bone health for nearly everyone; much higher levels have no proven extra benefit (IOM 2011). The Endocrine Society (2024) no longer advises routine testing in healthy adults.",
               retest: "Once, in winter, if you train indoors; only again if it was low."),
        Marker(id: "b12", name: "Vitamin B12", panel: "Vitamins", aliases: ["vitamin b12", "b12", "cobalamin"],
               units: [u("pg/mL", 200...900), u("pmol/L", 148...664)],
               about: "Needed for red blood cells and nerves. Plant-based diets and metformin can lower it. 200-300 pg/mL is borderline; ask about a follow-up test."),
        // Serum folate: deficient under ~3 ng/mL, adequate from 4 (WHO cut-offs; from memory in the audit).
        Marker(id: "folate", name: "Folate", panel: "Vitamins", aliases: ["folate", "serum folate", "folic acid", "folate, serum", "vitamin b9"],
               units: [u("ng/mL", low: 4), u("nmol/L", low: 9)],
               about: "A B vitamin for making red blood cells and DNA. About 4 ng/mL or more is adequate and under 3 is deficient; it falls with few vegetables or pulses, heavy drinking and some medicines."),
        Marker(id: "tsh", name: "TSH", panel: "Thyroid", aliases: ["tsh", "thyroid stimulating hormone", "thyrotropin"],
               units: [u("mIU/L", 0.4...4.0), u("mU/L", 0.4...4.0)],
               about: "Thyroid control hormone. High TSH can mean an underactive thyroid (tiredness, weight gain); low can mean overactive."),
        Marker(id: "testosterone", name: "Testosterone (total)", panel: "Hormones", aliases: ["testosterone", "total testosterone", "testosterone, total"],
               units: [u("ng/dL", 264...916, female: 15...70), u("nmol/L", 9.2...31.8, female: 0.5...2.4)],
               about: "Typical range for healthy men aged 19-39 from a harmonised reference (Travison et al. 2017); it falls about 1% a year after that. Best measured in the morning, fasted, twice before any conclusion.",
               retest: "Only with symptoms: two morning samples on different days."),
        Marker(id: "crp", name: "hs-CRP", panel: "Inflammation", aliases: ["hs-crp", "hscrp", "crp", "c-reactive protein", "high sensitivity crp"],
               units: [u("mg/L", high: 3), u("mg/dL", high: 0.3)],
               about: "Inflammation. Under 1 mg/L is low heart risk, 1-3 average, over 3 higher. A cold or a hard workout raises it for days; over 10 is acute inflammation, not heart risk.",
               retest: "If over 3, repeat in about 2 weeks when well and rested."),
        Marker(id: "creatinine", name: "Creatinine", panel: "Kidney", aliases: ["creatinine", "creat"],
               units: [u("mg/dL", 0.74...1.35, female: 0.59...1.04), u("µmol/L", 65...119, female: 52...92)],
               about: "A muscle waste product cleared by the kidneys. Creatine supplements and lots of muscle raise it without kidney harm."),
        Marker(id: "egfr", name: "eGFR", panel: "Kidney", aliases: ["egfr", "estimated gfr", "gfr"],
               units: [u("mL/min/1.73m²", low: 60), u("mL/min", low: 60)],
               about: "Estimated kidney filtering, worked out from creatinine. Under 60 for 3 months is the definition doctors use for chronic kidney disease (KDIGO); muscular people and creatine users can read falsely low, and a cystatin C test gets round that."),
        // Uric acid: Mayo 3.7-8.0 (men) / 2.7-6.1 (women) mg/dL; urate crystals form above ~6.8 mg/dL (from memory in the audit).
        Marker(id: "uricAcid", name: "Uric acid", panel: "Metabolic", aliases: ["uric acid", "urate", "serum urate", "uric acid, serum"],
               units: [u("mg/dL", 3.7...8.0, female: 2.7...6.1), u("µmol/L", 220...476, female: 161...363)],
               about: "A waste product from purines. Crystals can form in joints (gout) above about 6.8 mg/dL, even inside some lab ranges. It rises with fructose, beer, dehydration and very hard training, and falls with weight loss."),
        // Serum magnesium reflects body stores poorly (most is in bone and muscle); range from Mayo (from memory in the audit).
        Marker(id: "magnesium", name: "Magnesium", panel: "Metabolic", aliases: ["magnesium", "magnesium, serum", "serum magnesium"],
               units: [u("mg/dL", 1.7...2.3), u("mmol/L", 0.70...0.95)],
               about: "A mineral for muscle and nerve function. Blood magnesium is held steady by bone and kidney, so a normal result doesn't rule out a low intake; it mostly catches real deficiency."),
        Marker(id: "alt", name: "ALT", panel: "Liver", aliases: ["alt", "alanine aminotransferase", "sgpt"],
               units: [u("U/L", 7...55, female: 7...45)],
               about: "A liver enzyme. Hard lifting can raise it (and AST) for several days, so test after 2-3 easy days. A \"healthy\" ALT is under about 33 (men) or 25 (women), even if the lab range goes higher (ACG 2017).",
               retest: "After 2-3 easy days if it was raised following hard training."),
        Marker(id: "ast", name: "AST", panel: "Liver", aliases: ["ast", "aspartate aminotransferase", "sgot"],
               units: [u("U/L", 8...48, female: 8...43)],
               about: "An enzyme from liver and muscle. Rises after hard training as well as with liver strain.",
               retest: "After 2-3 easy days if it was raised following hard training."),
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

    /// The stricter "for someone who trains" floor for a marker in a unit, if it has one.
    public static func athleteLow(markerID: String, unit: String) -> Double? {
        marker(id: markerID)?.units.first { $0.unit.lowercased() == unit.lowercased() }?.athleteLow
    }

    /// When the lab's own range and the guideline line disagree, says both
    /// instead of only the lab's flag. Vitamin D is the case that matters:
    /// many labs flag under 30 ng/mL (Endocrine Society 2011), while the IOM
    /// (2011) found 20 ng/mL (50 nmol/L) covers bone health for nearly
    /// everyone, and the Endocrine Society's 2024 guideline dropped its 30
    /// target. Nil when they agree or the marker has no such split.
    public static func guidelineNote(markerID: String, value: Double, unit: String, labLow: Double?) -> String? {
        guard markerID == "vitaminD", let labLow, value < labLow,
              let line = marker(id: markerID)?.units.first(where: { $0.unit.lowercased() == unit.lowercased() })?.range(for: .male).low,
              value >= line else { return nil }
        let lineText = line.formatted(.number.precision(.fractionLength(0...1)))
        return "Below the lab's range; above the \(lineText) \(unit) IOM line. Guidelines differ."
    }

    /// A second line for people who train, shown next to the lab status: a
    /// result inside the lab range can still be low for an athlete (ferritin:
    /// Sim et al., Eur J Appl Physiol 2019). Nil when nothing applies.
    public static func trainingNote(markerID: String, value: Double, unit: String) -> String? {
        guard let floor = athleteLow(markerID: markerID, unit: unit), value < floor else { return nil }
        let limit = floor.formatted(.number.precision(.fractionLength(0...1)))
        return "Low for someone who trains: sports-medicine reviews put the floor at about \(limit) \(unit) (Sim et al. 2019), inside many lab ranges. Ferritin rises with inflammation and hard training, so a result taken when ill or after a heavy week can read higher than your stores. Worth raising with your doctor; not a diagnosis."
    }
}
