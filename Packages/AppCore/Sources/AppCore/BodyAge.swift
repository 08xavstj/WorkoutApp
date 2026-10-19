import Foundation

/// A "body age" estimate: your age, moved up or down by measurements that
/// research links with how long people live. It's a motivating summary, not a
/// medical test.
///
/// How each factor turns into years:
/// - Fitness (VO₂ max) is the biggest. "Fitness age" from the HUNT study
///   (Nes et al., Med Sci Sports Exerc 2014): the age at which an average healthy person has your
///   VO₂ max. Average VO₂ max falls about 0.40 ml/kg/min a year for men
///   (54.4 at 25) and 0.30 for women (43.0 at 25). It counts at 60 % weight
///   because the other factors overlap with it (the 60% is the app's choice).
/// - Mortality hazards from the other studies become years with the Gompertz
///   rule that the risk of dying doubles about every 8 years:
///   years = 8 × log2(hazard ratio) ("effective age", Spiegelhalter, BMC Med
///   Inform Decis Mak 2016).
///   - Resting heart rate: hazard 1.09 per 10 bpm above 60 (Zhang et al. 2016),
///     about 1 year per 10 bpm.
///   - Sleep: short sleep (mostly defined as under 6 h) had hazard 1.12 vs
///     7-8 h (Cappuccio et al., Sleep 2010). That compares whole groups, so
///     it's applied once (about 1.3 years), not per missing hour. Long sleep
///     (9 h+) is linked with higher risk too, but is thought to be a sign of
///     ill health rather than a cause, so it adds no years and is flagged instead.
///   - Steps: risk falls up to about 8-10k steps a day under 60 and 6-8k from
///     60, then flattens (Paluch et al., Lancet Public Health 2022). About 0.6
///     years per 1,000 steps from 7,000 (6,000 from age 60), with no extra
///     credit past the plateau.
///   - BMI hazards (never-smokers, vs 22.5-25) from the Global BMI Mortality
///     Collaboration (Lancet 2016). Body-fat bands are an app heuristic (no
///     mortality study by body-fat %), used because BMI overrates muscular people.
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

        public init(age: Int, sex: BiologicalSex, vo2Max: Double? = nil, restingHeartRate: Double? = nil,
                    sleepHours: Double? = nil, dailySteps: Double? = nil, bodyFatPercent: Double? = nil, bmi: Double? = nil) {
            self.age = age
            self.sex = sex
            self.vo2Max = vo2Max
            self.restingHeartRate = restingHeartRate
            self.sleepHours = sleepHours
            self.dailySteps = dailySteps
            self.bodyFatPercent = bodyFatPercent
            self.bmi = bmi
        }
    }

    public struct Factor: Sendable, Equatable, Identifiable {
        public var name: String
        /// Positive adds years, negative takes them away.
        public var years: Double
        public var detail: String
        public var id: String { name }
    }

    public struct Result: Sendable, Equatable {
        public var bodyAge: Double
        public var age: Int
        public var factors: [Factor]
        /// Negative = younger than your age.
        public var difference: Double { bodyAge - Double(age) }
    }

    /// Needs at least two factors; returns nil otherwise.
    public static func estimate(_ inputs: Inputs) -> Result? {
        var factors: [Factor] = []
        let age = Double(inputs.age)

        if let vo2 = inputs.vo2Max, vo2 > 10 {
            let (atTwentyFive, perYear) = inputs.sex == .male ? (54.4, 0.40) : (43.0, 0.30)
            let fitnessAge = 25 + (atTwentyFive - vo2) / perYear
            let years = clamp((fitnessAge - age) * 0.6, -12, 12)
            factors.append(Factor(name: "Fitness (VO₂ max)", years: years,
                                  detail: "VO₂ max \(format(vo2)) is typical of a \(Int(max(18, fitnessAge).rounded()))-year-old"))
        }
        if let rhr = inputs.restingHeartRate, rhr > 30 {
            let years = clamp(gompertzYears(hazard: pow(1.09, (rhr - 60) / 10)), -2, 4)
            factors.append(Factor(name: "Resting heart rate", years: years, detail: "\(Int(rhr.rounded())) bpm"))
        }
        if let hours = inputs.sleepHours, hours > 2 {
            let years = hours < 6 ? gompertzYears(hazard: 1.12) : 0
            let detail = hours >= 9
                ? "\(format(hours)) h a night. Regularly sleeping 9 h+ can be a sign of poor sleep or illness; worth mentioning to a doctor if you still feel tired"
                : "\(format(hours)) h a night"
            factors.append(Factor(name: "Sleep", years: years, detail: detail))
        }
        if let steps = inputs.dailySteps, steps > 0 {
            let (reference, plateau) = inputs.age < 60 ? (7000.0, 10_000.0) : (6000.0, 8000.0)
            let years = clamp(-(min(steps, plateau) - reference) / 1000 * 0.6, -2.5, 4)
            factors.append(Factor(name: "Daily steps", years: years, detail: "\(Int(steps.rounded())) a day"))
        }
        if let fat = inputs.bodyFatPercent, fat > 3, fat < 60 {
            let (healthy, high, veryHigh) = inputs.sex == .male ? (20.0, 25.0, 30.0) : (30.0, 35.0, 40.0)
            let years: Double = fat <= healthy ? -0.5 : (fat <= high ? 1 : (fat <= veryHigh ? 2.5 : 4.5))
            factors.append(Factor(name: "Body fat", years: years, detail: "\(format(fat))%"))
        } else if let bmi = inputs.bmi, bmi > 12 {
            let hazard: Double
            switch bmi {
            case ..<18.5: hazard = 1.51
            case ..<20: hazard = 1.13
            case ..<25: hazard = 1.0
            case ..<27.5: hazard = 1.07
            case ..<30: hazard = 1.20
            case ..<35: hazard = 1.45
            case ..<40: hazard = 1.94
            default: hazard = 2.76
            }
            factors.append(Factor(name: "BMI", years: gompertzYears(hazard: hazard), detail: format(bmi)))
        }

        guard factors.count >= 2 else { return nil }
        let total = clamp(factors.map(\.years).reduce(0, +), -20, 20)
        let bodyAge = max(18, age + total)
        return Result(bodyAge: (bodyAge * 10).rounded() / 10, age: inputs.age, factors: factors.sorted { abs($0.years) > abs($1.years) })
    }

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
