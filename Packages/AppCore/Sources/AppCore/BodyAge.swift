import Foundation

/// A "body age" estimate: your age, moved up or down by measurements that
/// research links with how long people live. It's a motivating summary, not a
/// medical test.
///
/// How each factor turns into years:
/// - Fitness (VO₂ max) is the biggest. "Fitness age" from the HUNT study
///   (Nes et al. 2013): the age at which an average healthy person has your
///   VO₂ max. Average VO₂ max falls about 0.40 ml/kg/min a year for men
///   (54.4 at 25) and 0.30 for women (43.0 at 25). It counts at 60 % weight
///   because the other factors overlap with it.
/// - Mortality hazards from the other studies become years with the Gompertz
///   rule that the risk of dying doubles about every 8 years:
///   years = 8 × log2(hazard ratio).
///   - Resting heart rate: hazard 1.09 per 10 bpm above 60 (Zhang et al. 2016),
///     about 1 year per 10 bpm.
///   - Sleep: under 7 h, hazard 1.12 for under 6 h (Cappuccio et al. 2010),
///     about 1.3 years per missing hour. Over 9 h, hazard 1.30.
///   - Steps: risk keeps falling up to about 8-10k steps a day (Paluch et al.
///     2022). About 0.6 years per 1,000 steps from 7,000, capped.
///   - Body fat (or BMI if body fat is unknown): BMI hazards from the Global
///     BMI Mortality Collaboration (2016). BMI overrates muscular people, so
///     body fat is preferred.
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
            let years: Double
            if hours < 7 {
                years = min(3, (7 - hours) * gompertzYears(hazard: 1.12))
            } else if hours > 9 {
                years = min(3, (hours - 9) * gompertzYears(hazard: 1.30))
            } else {
                years = -0.5
            }
            factors.append(Factor(name: "Sleep", years: years, detail: "\(format(hours)) h a night"))
        }
        if let steps = inputs.dailySteps, steps > 0 {
            let years = clamp(-(steps - 7000) / 1000 * 0.6, -2.5, 4)
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
            case ..<25: hazard = 1.0
            case ..<27.5: hazard = 1.07
            case ..<30: hazard = 1.20
            case ..<35: hazard = 1.45
            default: hazard = 1.94
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
