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
