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

    @Test func gompertzDoublingIsEightYears() {
        #expect(abs(BodyAge.gompertzYears(hazard: 2) - 8) < 0.0001)
    }
}
