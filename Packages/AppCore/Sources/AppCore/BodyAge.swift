import Foundation

/// A "body age" estimate: your age, moved up or down by measurements that
/// research links with how long people live. It's a motivating summary, not a
/// medical test. No composite like this has been validated, only its parts,
/// so it is shown as whole years with a ±5-year range (app choice; the audit
/// asked for a range rather than a point).
///
/// How each factor turns into years:
/// - Fitness (VO₂ max) is the biggest. "Fitness age": the age whose median
///   VO₂ max matches yours, on the FRIEND registry medians (Kaminsky et al.,
///   Mayo Clin Proc 2015; `Biomarkers.fitnessAge`), the same reference the
///   percentile label uses (`VO2Norms`), so a "Good" VO₂ max (at or above
///   the median) can't add years. The
///   fitness-age idea is Nes et al., Med Sci Sports Exerc 2011; Nes 2014 is
///   the mortality follow-up. Just below the median
///   (95-100% of it) it adds nothing: watch VO₂ max is off by ~10%, so that
///   gap is noise (app choice). Below the band, years count from the band's
///   edge so the factor has no jump. It counts at 60% weight because the
///   other factors overlap with it (the 60% is the app's choice).
/// - Mortality hazards from the other studies become years with the Gompertz
///   rule that the risk of dying doubles about every 8 years:
///   years = 8 × log2(hazard ratio) ("effective age", Spiegelhalter, BMC Med
///   Inform Decis Mak 2016).
///   - Resting heart rate: hazard 1.09 per 10 bpm above 60 (Zhang et al. 2016),
///     about 1 year per 10 bpm.
///   - Sleep: short sleep (mostly defined as under 6 h) had hazard 1.12 vs
///     7-8 h (Cappuccio et al., Sleep 2010). That compares whole groups, so
///     it's applied once (about 1.3 years), not per missing hour: in full at
///     6 h or less, nothing from 7 h (the bottom of the reference group), and
///     a straight line between, because the studies say nothing about where
///     inside 6-7 h the risk starts and a cliff at 6.0 h made 5 minutes of
///     sleep worth 1.3 years (the ramp is the app's choice). Long sleep
///     (9 h+) is linked with higher risk too, but is thought to be a sign of
///     ill health rather than a cause, so it adds no years and is flagged instead.
///   - Steps: risk falls up to about 8-10k steps a day under 60 and 6-8k from
///     60, then flattens (Paluch et al., Lancet Public Health 2022). About 0.6
///     years per 1,000 steps from 7,000 (6,000 from age 60), with no extra
///     credit past the plateau.
///   - Body composition, one of three (best available first):
///     - Waist-to-height ratio when a waist reading from the last 90 days
///       exists. WHtR predicts cardiometabolic risk better than BMI and ignores
///       muscle mass (Ashwell, Gunn & Gibson, Obes Rev 2012; Browning 2010 for
///       the 0.5 line). Ashwell 2012 reports risk discrimination, not mortality
///       hazards, so the step sizes borrow the BMI overweight and obese hazards
///       below: 0.5-0.6 ("raised") counts like BMI 27.5-30, 0.6+ ("high") like
///       BMI 30-35 (app mapping from the research round).
///     - Body-fat bands, an app heuristic (no mortality study by body-fat %),
///       used because BMI overrates muscular people.
///     - BMI hazards (never-smokers, vs 22.5-25) from the Global BMI Mortality
///       Collaboration (Lancet 2016), as the fallback.
///     Each of the three is read off straight lines, not steps: a band's
///     figure applies at the middle of the band and the healthy range is flat
///     (`bodyFatPoints`, `bmiHazardPoints`, `waistHazardPoints`). The studies
///     report one figure per band; joining them is the app's choice, made so
///     that 0.2 points of body fat can't be worth 1.5 years.
/// - Body size is counted once. VO₂ max is per kilogram, so extra weight
///   lowers it and raises BMI, body fat or waist at the same time: a heavy,
///   unfit person was getting up to +12 years twice. In pooled cohorts, unfit
///   people had about twice the mortality risk whatever their BMI, and fit
///   people who were overweight or obese had about the same risk as fit
///   people of normal weight (Barry et al., Prog Cardiovasc Dis
///   2014;56:382-390, meta-analysis of 10 studies; "fit" there meant only
///   "not in the lowest fitness group"), so most of the body-size risk is
///   already in the fitness figure. The years from fitness and from
///   body composition together are therefore capped at
///   `bodySizeAndFitnessCapYears` (12, the fitness factor's own ceiling);
///   the cap, and trimming the body-composition factor rather than fitness,
///   are the app's choice.
public enum BodyAge {
    public struct Inputs: Sendable, Equatable {
        public var age: Int
        public var sex: BiologicalSex
        public var vo2Max: Double?
        public var restingHeartRate: Double?
        public var sleepHours: Double?
        public var dailySteps: Double?
        public var bodyFatPercent: Double?
        public var bmi: Double?
        /// Waist / height from a reading in the last 90 days (the caller checks
        /// the age; see `WaistToHeightRatio.isFresh`). Replaces BMI and body fat.
        public var waistToHeightRatio: Double?
        /// How old the VO₂ max reading is, in days (nil if unknown).
        public var vo2MaxAgeDays: Int?
        /// How old the body fat or BMI reading is, in days (nil if unknown).
        public var bodyCompositionAgeDays: Int?

        public init(age: Int, sex: BiologicalSex, vo2Max: Double? = nil, restingHeartRate: Double? = nil,
                    sleepHours: Double? = nil, dailySteps: Double? = nil, bodyFatPercent: Double? = nil, bmi: Double? = nil,
                    vo2MaxAgeDays: Int? = nil, bodyCompositionAgeDays: Int? = nil, waistToHeightRatio: Double? = nil) {
            self.age = age
            self.sex = sex
            self.vo2Max = vo2Max
            self.restingHeartRate = restingHeartRate
            self.sleepHours = sleepHours
            self.dailySteps = dailySteps
            self.bodyFatPercent = bodyFatPercent
            self.bmi = bmi
            self.vo2MaxAgeDays = vo2MaxAgeDays
            self.bodyCompositionAgeDays = bodyCompositionAgeDays
            self.waistToHeightRatio = waistToHeightRatio
        }
    }

    /// How much to trust the number: more factors and fresher readings mean
    /// more confidence. VO₂ max moves the estimate most, so without a recent
    /// one it can't be "high".
    public enum Confidence: String, Sendable, Equatable {
        case high, medium, low

        public var label: String {
            switch self {
            case .high: "High confidence"
            case .medium: "Medium confidence"
            case .low: "Low confidence"
            }
        }
    }

    /// Factors the estimate can use: fitness, resting heart rate, sleep, steps
    /// and one body-composition measure.
    public static let factorSlots = 5

    public static func confidence(_ inputs: Inputs, factorCount: Int) -> (Confidence, reason: String) {
        var level: Confidence = factorCount >= 5 ? .high : (factorCount >= 3 ? .medium : .low)
        var reasons: [String] = []
        if inputs.vo2Max == nil {
            if level == .high { level = .medium }
            reasons.append("no VO₂ max yet (the biggest factor)")
        } else if let days = inputs.vo2MaxAgeDays, days > 90 {
            level = level == .high ? .medium : .low
            reasons.append("VO₂ max is \(days / 30) months old")
        }
        if let days = inputs.bodyCompositionAgeDays, days > 90 {
            if level == .high { level = .medium }
            reasons.append("body fat/BMI is \(days / 30) months old")
        }
        if factorCount < 5 { reasons.append("\(factorCount) of \(factorSlots) factors measured") }
        guard !reasons.isEmpty else { return (level, "Based on recent readings for most factors.") }
        let joined = reasons.joined(separator: "; ")
        let reason = joined.prefix(1).uppercased() + String(joined.dropFirst()) + "."
        return (level, reason)
    }

    public struct Factor: Sendable, Equatable, Identifiable {
        public var name: String
        /// Positive adds years, negative takes them away.
        public var years: Double
        public var detail: String
        public var id: String { name }
    }

    /// Half-width of the range shown with the estimate, in years. No composite
    /// "age" is validated to the year; watch VO₂ max alone is off by ~10% in
    /// fit people (app choice from the audit).
    public static let uncertaintyYears = 5

    public struct Result: Sendable, Equatable {
        /// Whole years (rounded).
        public var bodyAge: Double
        public var age: Int
        /// Biggest effect first: what's moving your body age.
        public var factors: [Factor]
        public var confidence: Confidence = .medium
        public var confidenceReason: String = ""
        /// Negative = younger than your age.
        public var difference: Double { bodyAge - Double(age) }
        /// Body age as a whole number.
        public var years: Int { Int(bodyAge.rounded()) }
        /// The factor adding the most years, if any adds 0.05 years or more (shown as at least +0.1 y).
        public var topAgeingFactor: Factor? {
            factors.filter { $0.years >= 0.05 }.max { $0.years < $1.years }
        }
        /// The ±5-year range around the estimate, never below 18.
        public var range: ClosedRange<Int> {
            max(18, years - BodyAge.uncertaintyYears)...(years + BodyAge.uncertaintyYears)
        }
        /// e.g. "about 34 (29–39)"
        public var rangeLabel: String {
            "about \(years) (\(range.lowerBound)–\(range.upperBound))"
        }
    }

    /// Most years fitness and body composition may add together (see the
    /// type's notes: body size is counted once). The app's choice.
    public static let bodySizeAndFitnessCapYears = 12.0

    /// Years by body-fat % (men; women are 10 points higher): −0.5 up to the
    /// healthy line (20%), then each band's figure at its middle: +1 at 22.5%
    /// (band 20-25), +2.5 at 27.5% (25-30), +4.5 from 32.5% (over 30). An app
    /// heuristic, as before (no mortality study by body-fat %); only the
    /// steps became lines.
    static func bodyFatPoints(sex: BiologicalSex) -> [(x: Double, y: Double)] {
        let shift = sex == .male ? 0.0 : 10.0
        return [(20 + shift, -0.5), (22.5 + shift, 1), (27.5 + shift, 2.5), (32.5 + shift, 4.5)]
    }

    /// Years by BMI: the Global BMI Mortality Collaboration's hazards for
    /// never-smokers (Lancet 2016) turned into years, each at the middle of
    /// its band (16.75 for 15-18.5: 1.51; 19.25: 1.13; 26.25: 1.07; 28.75:
    /// 1.20; 32.5: 1.45; 37.5: 1.94; 45 for 40 and over: 2.76), flat at 1.0
    /// across 20-25. The band figures are the study's; the lines between are
    /// the app's.
    static let bmiHazardPoints: [(x: Double, y: Double)] = [
        (16.75, gompertzYears(hazard: 1.51)), (19.25, gompertzYears(hazard: 1.13)), (20, 0), (25, 0),
        (26.25, gompertzYears(hazard: 1.07)), (28.75, gompertzYears(hazard: 1.20)), (32.5, gompertzYears(hazard: 1.45)),
        (37.5, gompertzYears(hazard: 1.94)), (45, gompertzYears(hazard: 2.76)),
    ]

    /// Years by waist-to-height ratio: nothing up to 0.5, the "raised" figure
    /// (hazard 1.20, borrowed from BMI 27.5-30) at 0.55, the middle of
    /// 0.5-0.6, and the "high" figure (1.45, BMI 30-35) from 0.65. App
    /// mapping, as before; only the steps became lines.
    static let waistHazardPoints: [(x: Double, y: Double)] = [
        (WaistToHeightRatio.target, 0), (0.55, gompertzYears(hazard: 1.20)), (0.65, gompertzYears(hazard: 1.45)),
    ]

    /// Hours at or under which short sleep counts in full, and from which it
    /// doesn't count (Cappuccio 2010: short mostly under 6 h, reference 7-8 h).
    static let shortSleepHours = 6.0
    static let referenceSleepHours = 7.0

    /// Straight lines through `points` (sorted by x), flat outside them.
    static func interpolate(_ value: Double, _ points: [(x: Double, y: Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if value <= first.x { return first.y }
        if value >= last.x { return last.y }
        for (low, high) in zip(points, points.dropFirst()) where value <= high.x {
            let span = high.x - low.x
            return span > 0 ? low.y + (high.y - low.y) * (value - low.x) / span : high.y
        }
        return last.y
    }

    /// "a" or "an" before a number read aloud: "an 18-year-old", "an 81-year-old", "a 24-year-old".
    static func article(for number: Int) -> String {
        let value = abs(number)
        if value == 8 || value == 11 || value == 18 { return "an" }
        if (80...89).contains(value) || (800...899).contains(value) { return "an" }
        return "a"
    }

    /// Needs at least two factors; returns nil otherwise.
    public static func estimate(_ inputs: Inputs) -> Result? {
        var factors: [Factor] = []
        let age = Double(inputs.age)

        if let vo2 = inputs.vo2Max, vo2 > 10 {
            let median = Biomarkers.medianVO2Max(age: inputs.age, sex: inputs.sex)
            let goodFloor = Biomarkers.goodVO2MaxFraction * median
            let fitnessAge = Biomarkers.fitnessAge(vo2Max: vo2, age: inputs.age, sex: inputs.sex)
            let years: Double
            if vo2 >= median {
                years = clamp((fitnessAge - age) * 0.6, -12, 0)
            } else if vo2 >= goodFloor {
                years = 0
            } else {
                let edgeAge = Biomarkers.fitnessAge(vo2Max: goodFloor, age: inputs.age, sex: inputs.sex)
                years = clamp((fitnessAge - edgeAge) * 0.6, 0, 12)
            }
            let detail = abs(years) < 0.05
                ? "VO₂ max \(format(vo2)), about typical for your age (\(format(median)))"
                : "VO₂ max \(format(vo2)) is typical of \(article(for: Int(fitnessAge.rounded()))) \(Int(fitnessAge.rounded()))-year-old"
            factors.append(Factor(name: Self.fitnessFactorName, years: years, detail: detail))
        }
        if let rhr = inputs.restingHeartRate, rhr > 30 {
            let years = clamp(gompertzYears(hazard: pow(1.09, (rhr - 60) / 10)), -2, 4)
            factors.append(Factor(name: "Resting heart rate", years: years, detail: "\(Int(rhr.rounded())) bpm (2-week average)"))
        }
        if let hours = inputs.sleepHours, hours > 2 {
            // In full at 6 h or less, none from 7 h, a straight line between (see the type's notes).
            let share = clamp((referenceSleepHours - hours) / (referenceSleepHours - shortSleepHours), 0, 1)
            let years = gompertzYears(hazard: 1.12) * share
            let detail = hours >= 9
                ? "\(format(hours)) h a night. Regularly sleeping 9 h+ can be a sign of poor sleep or illness; worth mentioning to a doctor if you still feel tired"
                : "\(format(hours)) h a night"
            factors.append(Factor(name: "Sleep", years: years, detail: detail))
        }
        if let steps = inputs.dailySteps, steps > 0 {
            let (reference, plateau) = inputs.age < 60 ? (7000.0, 10_000.0) : (6000.0, 8000.0)
            let years = clamp(-(min(steps, plateau) - reference) / 1000 * 0.6, -2.5, 4)
            factors.append(Factor(name: "Daily steps", years: years, detail: "\(Int(steps.rounded()).formatted()) a day (30-day average)"))
        }
        var bodySizeFactor: String?
        if let ratio = inputs.waistToHeightRatio, WaistToHeightRatio.plausibleRatios.contains(ratio) {
            // Waist-to-height ratio (Ashwell 2012 bands; hazards borrowed from the BMI table, see `waistHazardPoints`).
            bodySizeFactor = "Waist-to-height"
            factors.append(Factor(name: "Waist-to-height", years: interpolate(ratio, waistHazardPoints),
                                  detail: "\(String(format: "%.2f", ratio)) (\(WaistToHeightRatio.category(ratio).rawValue.lowercased()); under 0.5 is the target)"))
        } else if let fat = inputs.bodyFatPercent, fat > 3, fat < 60 {
            bodySizeFactor = "Body fat"
            factors.append(Factor(name: "Body fat", years: interpolate(fat, bodyFatPoints(sex: inputs.sex)), detail: "\(format(fat))%"))
        } else if let bmi = inputs.bmi, bmi > 12 {
            bodySizeFactor = "BMI"
            factors.append(Factor(name: "BMI", years: interpolate(bmi, bmiHazardPoints), detail: format(bmi)))
        }

        // Body size is counted once: fitness (per kg) and body composition
        // together add at most `bodySizeAndFitnessCapYears`; the excess comes
        // off the body-composition factor.
        if let name = bodySizeFactor,
           let fitness = factors.first(where: { $0.name == Self.fitnessFactorName })?.years, fitness > 0,
           let index = factors.firstIndex(where: { $0.name == name }), factors[index].years > 0 {
            let room = max(0, bodySizeAndFitnessCapYears - fitness)
            if factors[index].years > room {
                factors[index].years = room
                factors[index].detail += ". Counted in part: a low VO₂ max per kg already reflects body size"
            }
        }
        // To the 0.1 shown, and never "−0.0".
        for index in factors.indices {
            let rounded = (factors[index].years * 10).rounded() / 10
            factors[index].years = rounded == 0 ? 0 : rounded
        }

        guard factors.count >= 2 else { return nil }
        let total = clamp(factors.map(\.years).reduce(0, +), -20, 20)
        let bodyAge = max(18, age + total)
        let trust = Self.confidence(inputs, factorCount: factors.count)
        // Whole years: the composite isn't validated finer than that (audit, problem 8).
        return Result(bodyAge: bodyAge.rounded(), age: inputs.age, factors: factors.sorted { abs($0.years) > abs($1.years) },
                      confidence: trust.0, confidenceReason: trust.reason)
    }

    static let fitnessFactorName = "Fitness (VO₂ max)"

    /// Years added by a mortality hazard ratio, if risk doubles every 8 years.
    static func gompertzYears(hazard: Double) -> Double {
        8 * log2(hazard)
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }

    static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
