import Foundation
import Testing
@testable import AppCore

struct NutritionTests {
    @Test func proteinTargetIsOnePointSixGramsPerKilo() {
        #expect(NutritionTargets.proteinGrams(bodyMassKg: 80) == 128)
        #expect(NutritionTargets.proteinGrams(bodyMassKg: nil) == nil)
        #expect(NutritionTargets.proteinGrams(bodyMassKg: 0) == nil)
    }

    @Test func emptyDayDetection() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(NutritionDay(date: date).isEmpty)
        #expect(NutritionDay(date: date, calories: 0, proteinGrams: 0).isEmpty)
        #expect(!NutritionDay(date: date, proteinGrams: 30).isEmpty)
    }
}
