import Testing
@testable import AppCore

struct BodyAgeTests {
    @Test func fitHabitsMakeYouYounger() throws {
        let inputs = BodyAge.Inputs(age: 30, sex: .male, vo2Max: 55, restingHeartRate: 50, sleepHours: 7.5, dailySteps: 11_000)
        let result = try #require(BodyAge.estimate(inputs))
        #expect(result.bodyAge < 25)
        #expect(result.difference < 0)
        #expect(result.factors.first?.name == "Fitness (VO₂ max)")
    }

    @Test func aGoodVO2MaxNeverAddsYears() throws {
        // One reference (FRIEND) for the label and the fitness age: "Good" or
        // better can't make the body age older.
        for sex in BiologicalSex.allCases {
            for age in stride(from: 18, through: 90, by: 3) {
                let median = Biomarkers.medianVO2Max(age: age, sex: sex)
                for share in [0.95, 0.97, 1.0, 1.05, 1.09, 1.2, 1.4] {
                    let vo2 = median * share
                    let label = Biomarkers.vo2MaxLabel(vo2, age: age, sex: sex)
                    #expect(label != "Poor" && label != "Fair")
                    let result = try #require(BodyAge.estimate(BodyAge.Inputs(age: age, sex: sex, vo2Max: vo2, restingHeartRate: 60)))
                    let fitness = try #require(result.factors.first { $0.name == "Fitness (VO₂ max)" })
                    #expect(fitness.years <= 0, "\(sex) \(age) \(share)")
                }
            }
        }
    }

    @Test func aFairVO2MaxAddsYearsWithoutAJump() throws {
        let median = Biomarkers.medianVO2Max(age: 40, sex: .male)
        func years(_ share: Double) throws -> Double {
            let result = try #require(BodyAge.estimate(BodyAge.Inputs(age: 40, sex: .male, vo2Max: median * share, restingHeartRate: 60)))
            return try #require(result.factors.first { $0.name == "Fitness (VO₂ max)" }).years
        }
        #expect(try years(0.94) > 0)
        #expect(try years(0.94) < 1)
        #expect(try years(0.75) > years(0.85))
    }

    @Test func poorFitnessMakesYouOlderButIsCapped() throws {
        let inputs = BodyAge.Inputs(age: 30, sex: .male, vo2Max: 32, restingHeartRate: 80, dailySteps: 3_000, bmi: 32)
        let result = try #require(BodyAge.estimate(inputs))
        #expect(result.bodyAge > 40)
        #expect(result.bodyAge <= 50)
    }

    @Test func bodyFatIsPreferredOverBMI() throws {
        let inputs = BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, bodyFatPercent: 15, bmi: 31)
        let result = try #require(BodyAge.estimate(inputs))
        #expect(result.factors.contains { $0.name == "Body fat" })
        #expect(!result.factors.contains { $0.name == "BMI" })
    }

    @Test func waistToHeightReplacesBMIAndBodyFat() throws {
        // Ashwell 2012: WHtR beats BMI and ignores muscle, so a fresh waist reading wins.
        let inputs = BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, bodyFatPercent: 15, bmi: 31, waistToHeightRatio: 0.46)
        let result = try #require(BodyAge.estimate(inputs))
        let waist = try #require(result.factors.first { $0.name == "Waist-to-height" })
        #expect(waist.years == 0)
        #expect(waist.detail.contains("0.46"))
        #expect(!result.factors.contains { $0.name == "BMI" || $0.name == "Body fat" })
        // Raised (0.5-0.6) borrows the BMI 27.5-30 hazard; high (0.6+) the 30-35 one.
        let raised = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, waistToHeightRatio: 0.55)))
        #expect(abs((raised.factors.first { $0.name == "Waist-to-height" }?.years ?? 0) - BodyAge.gompertzYears(hazard: 1.20)) < 0.001)
        let high = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, waistToHeightRatio: 0.62)))
        #expect(abs((high.factors.first { $0.name == "Waist-to-height" }?.years ?? 0) - BodyAge.gompertzYears(hazard: 1.45)) < 0.001)
        // Without a waist reading, BMI is still the fallback.
        let fallback = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, bmi: 31)))
        #expect(fallback.factors.contains { $0.name == "BMI" })
    }

    @Test func needsAtLeastTwoFactors() {
        #expect(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .female, vo2Max: 40)) == nil)
    }

    @Test func sleepRiskIsAppliedOnceNotPerHour() throws {
        let short = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, sleepHours: 4.5)))
        let sleep = try #require(short.factors.first { $0.name == "Sleep" })
        #expect(abs(sleep.years - BodyAge.gompertzYears(hazard: 1.12)) < 0.001)
        let normal = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, sleepHours: 7.5)))
        #expect(normal.factors.first { $0.name == "Sleep" }?.years == 0)
    }

    @Test func noStepCreditPastThePlateau() throws {
        let a = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, dailySteps: 10_000)))
        let b = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 60, dailySteps: 16_000)))
        #expect(a.bodyAge == b.bodyAge)
    }

    @Test func gompertzDoublingIsEightYears() {
        #expect(abs(BodyAge.gompertzYears(hazard: 2) - 8) < 0.0001)
    }

    @Test func wholeYearsWithAFiveYearRange() throws {
        // Fit 30-year-old: −7.2 (VO₂ max 55 is far above the FRIEND median of
        // 45.2, a fitness age of 18) − 1.0 (RHR) − 1.8 (steps) ≈ 20.0, shown as
        // "about 20 (18–25)". (It was 23 on the higher HUNT3 means.)
        let inputs = BodyAge.Inputs(age: 30, sex: .male, vo2Max: 55, restingHeartRate: 50, sleepHours: 7.5, dailySteps: 11_000)
        let result = try #require(BodyAge.estimate(inputs))
        #expect(result.bodyAge == 20)
        #expect(result.bodyAge == result.bodyAge.rounded())
        #expect(result.years == 20)
        #expect(result.range == 18...25)
        #expect(result.rangeLabel == "about 20 (18–25)")
        #expect(BodyAge.uncertaintyYears == 5)
        // The range never dips below 18.
        let young = try #require(BodyAge.estimate(BodyAge.Inputs(age: 20, sex: .male, vo2Max: 60, restingHeartRate: 45, dailySteps: 12_000)))
        #expect(young.range.lowerBound == 18)
    }
}

struct OneRepMaxTests {
    @Test func countsRepsLeft() {
        // 100 x 8 at RPE 8 = 10 reps to failure.
        #expect(abs(OneRepMax.estimate(weight: 100, reps: 8, rpe: 8) - 100 * (1 + 10.0 / 30)) < 0.001)
        #expect(abs(OneRepMax.estimate(weight: 100, reps: 8, rpe: nil) - 100 * (1 + 8.0 / 30)) < 0.001)
        #expect(OneRepMax.estimate(weight: 140, reps: 1, rpe: 10) == 140)
    }

    @Test func capsHighReps() {
        #expect(OneRepMax.estimate(weight: 50, reps: 25, rpe: nil) == 50 * 1.5)
    }
}
