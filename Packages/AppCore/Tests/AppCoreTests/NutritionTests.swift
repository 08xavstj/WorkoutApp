import Foundation
import Testing
@testable import AppCore

struct NutritionTests {
    @Test func proteinTargetIsOnePointSixGramsPerKilo() {
        #expect(NutritionTargets.proteinGrams(bodyMassKg: 80) == 128)
        #expect(NutritionTargets.proteinGrams(bodyMassKg: nil) == nil)
        #expect(NutritionTargets.proteinGrams(bodyMassKg: 0) == nil)
    }

    @Test func fibreTargetIsTheReynoldsRange() {
        // Reynolds et al., Lancet 2019: 25-29 g a day; the "low" line is 20 g.
        #expect(NutritionTargets.fiberTargetGrams == 25...29)
        #expect(NutritionTargets.fiberStatus(grams: 12) == .low)
        #expect(NutritionTargets.fiberStatus(grams: 22) == .nearTarget)
        #expect(NutritionTargets.fiberStatus(grams: 25) == .onTarget)
        #expect(NutritionTargets.fiberStatus(grams: 40) == .onTarget)
        #expect(NutritionTargets.fiberStatus(grams: nil) == nil)
        #expect(NutritionTargets.fiberTargetText(goals: nil).hasPrefix("25-29 g"))
        #expect(NutritionTargets.fiberTargetText(goals: Goals(weight: .gain)).hasPrefix("25-35 g"))
        #expect(NutritionTargets.fiberTargetText(goals: Goals(weight: .lose)).contains("full"))
    }

    @Test func proteinPerMealIsPointFourPerKgTimesFour() throws {
        // Schoenfeld & Aragon 2018: 0.4 g/kg × 4 meals; Moore 2015; Kerksick 2017.
        let lifter = Goals(weight: .maintain, focuses: [.muscle])
        let spread = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: lifter))
        #expect(spread.grams == 32)
        #expect(spread.meals == 4)
        // Three logged meals: the dose rises so the day still reaches 1.6 g/kg (0.53 g/kg, under the 0.55 ceiling).
        let three = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: lifter, loggedMeals: 3))
        #expect(three.meals == 3)
        #expect(three.grams == 43)
        // Two logged meals is still shown as the 4-meal target (not a 2-meal plan).
        #expect(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: lifter, loggedMeals: 2)?.meals == 4)
        // Endurance / health only: 3 meals of about 0.3 g/kg (nutrition.md).
        let endurance = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: Goals(weight: .maintain, focuses: [.endurance])))
        #expect(endurance.grams == 24)
        #expect(endurance.meals == 3)
        // Losing weight counts as lifting (protein matters most in a deficit); no goal defaults to the lifter spread.
        #expect(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: Goals(weight: .lose, focuses: [.health]))?.grams == 32)
        #expect(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: nil)?.meals == 4)
        #expect(NutritionTargets.proteinPerMeal(bodyMassKg: nil, goals: lifter) == nil)
    }

    @Test func carbsScaleWithTrainingDays() throws {
        // Burke 2011: 3-5 g/kg light days, 5-7 g/kg about an hour of moderate training; Kerksick 2017.
        let lifter = Goals(weight: .maintain, focuses: [.muscle])
        #expect(NutritionTargets.carbsPerKg(trainingDay: true, goals: lifter) == 3...5)
        #expect(NutritionTargets.carbsPerKg(trainingDay: false, goals: lifter) == 2...3)
        let endurance = Goals(weight: .maintain, focuses: [.endurance])
        #expect(NutritionTargets.carbsPerKg(trainingDay: true, goals: endurance) == 5...7)
        #expect(NutritionTargets.carbsPerKg(trainingDay: false, goals: endurance) == 3...5)
        #expect(NutritionTargets.carbsPerKg(trainingDay: true, goals: nil) == 3...5)
        let grams = try #require(NutritionTargets.carbsGrams(bodyMassKg: 80, trainingDay: true, goals: lifter))
        #expect(grams == 240...400)
        #expect(NutritionTargets.carbsGrams(bodyMassKg: nil, trainingDay: true, goals: lifter) == nil)
        let text = try #require(NutritionTargets.carbsText(bodyMassKg: 80, trainingDay: false, goals: lifter))
        #expect(text == "Carbs: about 160-240 g today (rest day), 240-400 g on training days.")
    }

    @Test func emptyDayDetection() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(NutritionDay(date: date).isEmpty)
        #expect(NutritionDay(date: date, calories: 0, proteinGrams: 0).isEmpty)
        #expect(!NutritionDay(date: date, proteinGrams: 30).isEmpty)
    }
}
