import Foundation
import Testing
@testable import AppCore

/// Personal calorie and macro numbers (docs/research/calories.md).
struct TrainingStatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Sessions over the last `days` days on the given weekdays of a `cycle`-day pattern.
    func sessions(days: Int, cycle: Int = 7, on slots: Set<Int>, skippingRecent: Int = 0) -> [Date] {
        (skippingRecent..<days).filter { slots.contains($0 % cycle) }.map { now.addingTimeInterval(-Double($0) * 86_400 - 3600) }
    }

    @Test func noHistoryIsUntrained() {
        #expect(TrainingStatus.estimate(sessionDates: [], now: now) == .untrained)
    }

    @Test func threeMonthsIsNovice() {
        #expect(TrainingStatus.estimate(sessionDates: sessions(days: 90, on: [0, 2, 4, 6]), now: now) == .novice)
    }

    @Test func aYearOfFourDaysAWeekIsIntermediate() {
        // Helms 2014's "resistance-trained" means more than 6 months.
        #expect(TrainingStatus.estimate(sessionDates: sessions(days: 365, on: [0, 2, 4, 6]), now: now) == .intermediate)
    }

    @Test func thirtyMonthsIsAdvanced() {
        #expect(TrainingStatus.estimate(sessionDates: sessions(days: 913, on: [0, 2, 4]), now: now) == .advanced)
    }

    @Test func underTwiceAWeekStaysNovice() {
        // 1.5 sessions a week for a year: regular, but under the 2-a-week line.
        #expect(TrainingStatus.estimate(sessionDates: sessions(days: 365, cycle: 14, on: [0, 4, 9]), now: now) == .novice)
    }

    @Test func eightWeeksOffIsUntrained() {
        #expect(TrainingStatus.estimate(sessionDates: sessions(days: 800, on: [0, 2, 4], skippingRecent: 60), now: now) == .untrained)
    }

    @Test func orderIsByExperience() {
        #expect(TrainingStatus.untrained < .novice && TrainingStatus.intermediate < .advanced)
        #expect(!TrainingStatus.novice.isTrained)
        #expect(TrainingStatus.intermediate.isTrained && TrainingStatus.advanced.isTrained)
    }
}

struct PersonalRestingEnergyTests {
    let calc = EnergyCalculator()
    let man = EnergyCalculator.Body(weightKg: 74, heightCm: 183, age: 25, sex: .male)

    @Test func tenHaafForTrainedPeopleAged18To35() {
        // ten Haaf & Weijs 2014: (49.940×74 + 2459.053×1.83 − 34.014×25 + 799.257 + 122.502) kJ / 4.184 ≈ 1,976 kcal.
        var lifter = man
        lifter.trainingStatus = .intermediate
        let result = calc.bmr(lifter)
        #expect(result.method == EnergyCalculator.tenHaafMethod)
        #expect(abs(result.kcal - 1975.9) < 0.5)
        // Women: no sex term.
        let woman = EnergyCalculator.Body(weightKg: 60, heightCm: 165, age: 30, sex: .female, trainingStatus: .advanced)
        #expect(abs(calc.bmr(woman).kcal - 1471.3) < 0.5)
    }

    @Test func mifflinOtherwise() {
        // Untrained, unknown, novice, outside 18-35, or no height: Mifflin-St Jeor (Frankenfield 2005).
        // 10×74 + 6.25×183 − 5×25 + 5 = 1,763.75
        #expect(calc.bmr(man).method == "Mifflin-St Jeor")
        #expect(abs(calc.bmr(man).kcal - 1763.75) < 0.01)
        var novice = man
        novice.trainingStatus = .novice
        #expect(calc.bmr(novice).method == "Mifflin-St Jeor")
        var older = man
        older.trainingStatus = .advanced
        older.age = 45
        #expect(calc.bmr(older).method == "Mifflin-St Jeor")
        var noHeight = man
        noHeight.trainingStatus = .advanced
        noHeight.heightCm = nil
        #expect(calc.bmr(noHeight).method == "Mifflin-St Jeor (estimated height)")
    }

    @Test func cunninghamForTrainedPeopleWithClinicalBodyFat() {
        // Cunningham 1980: 500 + 22 × lean mass; 74 kg at 13% → 64.4 kg lean → 1,916 kcal.
        let clinic = EnergyCalculator.Body(weightKg: 74, heightCm: 183, age: 25, sex: .male, bodyFatPercent: 13,
                                           bodyFatIsClinical: true, trainingStatus: .intermediate)
        let result = calc.bmr(clinic)
        #expect(result.method == EnergyCalculator.cunninghamMethod)
        #expect(abs(result.kcal - 1916.36) < 0.5)
        // A scale reading never switches the equation; the training status still picks ten Haaf.
        var scale = clinic
        scale.bodyFatIsClinical = false
        #expect(calc.bmr(scale).method == EnergyCalculator.tenHaafMethod)
    }

    @Test func estimateUsesTrainingStatus() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = HeartRateProfile(age: 25, sex: .male, restingHeartRate: 55)
        var lifter = man
        lifter.trainingStatus = .advanced
        let result = calc.estimate(body: lifter, profile: profile, heartRate: [], strengthSessions: [],
                                   stepsOutsideWorkouts: 0, intake: nil, dayStart: start, now: start.addingTimeInterval(86_400))
        #expect(result.bmrMethod == EnergyCalculator.tenHaafMethod)
        #expect(abs(result.restingFullDay - 1975.9) < 0.5)
    }
}

struct PersonalRateTests {
    let lose = Goals(weight: .lose, weeklyRatePercent: 1.0, focuses: [.muscle])
    let gain = Goals(weight: .gain, weeklyRatePercent: 0.5, focuses: [.muscle])

    @Test func generalLimitsWithoutPersonalData() {
        // Helms 2014; Garthe 2011 (loss); Iraki 2019 (gain).
        let loss = GoalPlanner.maximumWeeklyRate(goals: lose, sex: .male, age: nil, bodyFatPercent: nil, trainingStatus: nil)
        #expect(loss.percent == 1.0 && loss.reason == .general)
        #expect(GoalPlanner.maximumWeeklyRate(goals: gain, sex: .male, age: nil, bodyFatPercent: nil, trainingStatus: nil).percent == 0.5)
        #expect(GoalPlanner.maximumWeeklyRate(goals: Goals(weight: .maintain), sex: .male, age: 30, bodyFatPercent: 20, trainingStatus: nil).percent == 0)
    }

    @Test func leanerMeansSlowerLoss() {
        // Forbes 2000; Garthe 2011 (0.7%/wk kept lean mass in lean athletes); Helms 2014.
        func limit(_ sex: BiologicalSex, _ fat: Double) -> GoalPlanner.RateLimit {
            GoalPlanner.maximumWeeklyRate(goals: lose, sex: sex, age: 30, bodyFatPercent: fat, trainingStatus: .intermediate)
        }
        #expect(limit(.male, 20).percent == 1.0)
        #expect(limit(.male, 13).percent == 0.75)
        #expect(limit(.male, 13).reason == .lean)
        #expect(limit(.male, 8).percent == 0.5)
        #expect(limit(.male, 8).reason == .veryLean)
        // Women's cut-offs sit about 8 points higher (essential fat).
        #expect(limit(.female, 25).percent == 1.0)
        #expect(limit(.female, 20).percent == 0.75)
        #expect(limit(.female, 16).percent == 0.5)
    }

    @Test func olderAdultsLoseSlower() {
        // Villareal 2017: about 9% in 26 weeks with lifting in over-65s.
        let limit = GoalPlanner.maximumWeeklyRate(goals: lose, sex: .male, age: 70, bodyFatPercent: 28, trainingStatus: nil)
        #expect(limit.percent == 0.5)
        #expect(limit.reason == .olderAdult)
        #expect(limit.message.contains("Villareal 2017"))
        #expect(GoalPlanner.maximumWeeklyRate(goals: lose, sex: .female, age: 64, bodyFatPercent: 35, trainingStatus: nil).percent == 1.0)
    }

    @Test func advancedLiftersGainSlower() {
        // Iraki 2019: novice/intermediate 0.25-0.5%/wk; advanced more conservative.
        let advanced = GoalPlanner.maximumWeeklyRate(goals: gain, sex: .male, age: 30, bodyFatPercent: nil, trainingStatus: .advanced)
        #expect(advanced.percent == 0.25)
        #expect(advanced.reason == .advancedLifter)
        #expect(GoalPlanner.maximumWeeklyRate(goals: gain, sex: .female, age: 30, bodyFatPercent: nil, trainingStatus: .novice).percent == 0.5)
    }

    @Test func messagesCiteTheEvidenceAndFlagEstimates() {
        let estimated = GoalPlanner.maximumWeeklyRate(goals: lose, sex: .male, age: 30, bodyFatPercent: 13, trainingStatus: nil, bodyFatIsEstimate: true)
        #expect(estimated.message.hasPrefix("For your body fat, losing faster than 0.75% a week costs muscle"))
        #expect(estimated.message.contains("Garthe 2011"))
        #expect(estimated.message.contains("estimated from BMI"))
        let measured = GoalPlanner.maximumWeeklyRate(goals: lose, sex: .male, age: 30, bodyFatPercent: 13, trainingStatus: nil)
        #expect(!measured.message.contains("estimated from BMI"))
    }

    @Test func calorieTargetCapsTheRate() {
        // 74 kg, 13% fat, picked 1%/wk: capped at 0.75% → 0.555 kg × 7,700 / 7 ≈ 610 kcal a day.
        let capped = GoalPlanner.calorieTarget(maintenance: 2800, bodyMassKg: 74, goals: lose, sex: .male,
                                               age: 25, bodyFatPercent: 13, trainingStatus: .intermediate)
        #expect(abs(capped - 2189.5) < 0.01)
        // Without personal data the general 1% limit applies (unchanged behaviour).
        #expect(abs(GoalPlanner.calorieTarget(maintenance: 2800, bodyMassKg: 74, goals: lose, sex: .male) - 1986) < 0.01)
    }

    @Test func rateOptionsHideFasterRates() {
        #expect(GoalPlanner.rateOptions(for: .lose, maximum: 0.5) == [0.25, 0.5])
        #expect(GoalPlanner.rateOptions(for: .lose, maximum: 0.75) == [0.25, 0.5, 0.75])
        #expect(GoalPlanner.rateOptions(for: .lose, maximum: 0.1) == [0.25])
        #expect(GoalPlanner.rateOptions(for: .gain, maximum: 0.25) == [0.25])
        #expect(GoalPlanner.rateOptions(for: .lose) == [0.25, 0.5, 0.75, 1.0])
    }

    @Test func cappedGoalsKeepSlowerRates() {
        let limit = GoalPlanner.RateLimit(percent: 0.5, reason: .veryLean, weight: .lose)
        #expect(GoalPlanner.cappedGoals(lose, limit: limit).weeklyRatePercent == 0.5)
        let slow = Goals(weight: .lose, weeklyRatePercent: 0.25)
        #expect(GoalPlanner.cappedGoals(slow, limit: limit) == slow)
    }

    @Test func bodyFatFromBMIIsDeurenberg() throws {
        // Deurenberg 1991: 1.2 × BMI + 0.23 × age − 10.8 × male − 5.4.
        let man = try #require(GoalPlanner.estimatedBodyFatPercent(weightKg: 74, heightCm: 183, age: 25, sex: .male))
        #expect(abs(man - 16.07) < 0.05)
        let woman = try #require(GoalPlanner.estimatedBodyFatPercent(weightKg: 68, heightCm: 165, age: 45, sex: .female))
        #expect(abs(woman - 34.92) < 0.05)
        #expect(GoalPlanner.estimatedBodyFatPercent(weightKg: 74, heightCm: nil, age: 25, sex: .male) == nil)
    }
}

struct PersonalProteinAndCycleTests {
    @Test func olderAdultsGetPointFourPerMeal() throws {
        // Moore 2015: ~0.40 g/kg per meal in older vs ~0.24 in younger men; 3 × 0.4 = 1.2 g/kg (PROT-AGE 2013).
        let health = Goals(weight: .maintain, focuses: [.health])
        let older = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: health, age: 70))
        #expect(older.grams == 32)
        #expect(older.meals == 3)
        let younger = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: health, age: 40))
        #expect(younger.grams == 24)
        // Lifters already get 0.4 g/kg at any age.
        #expect(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: Goals(weight: .maintain, focuses: [.muscle]), age: 70)?.grams == 32)
    }

    @Test func lutealNoteOnlyForWomenInTheWindow() {
        // Benton 2020; Hurtová 2026: small luteal rise, so a note, not a target change.
        #expect(CycleEnergy.note(sex: .female, daysSinceLastPeriod: 15)?.contains("target stays the same") == true)
        #expect(CycleEnergy.note(sex: .female, daysSinceLastPeriod: 3) == nil)
        #expect(CycleEnergy.note(sex: .female, daysSinceLastPeriod: 30) == nil)
        #expect(CycleEnergy.note(sex: .female, daysSinceLastPeriod: nil) == nil)
        #expect(CycleEnergy.note(sex: .male, daysSinceLastPeriod: 15) == nil)
    }
}
