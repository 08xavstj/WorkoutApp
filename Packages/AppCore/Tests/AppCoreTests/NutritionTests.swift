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

    @Test func emptyDayDetection() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(NutritionDay(date: date).isEmpty)
        #expect(NutritionDay(date: date, calories: 0, proteinGrams: 0).isEmpty)
        #expect(!NutritionDay(date: date, proteinGrams: 30).isEmpty)
    }
}
