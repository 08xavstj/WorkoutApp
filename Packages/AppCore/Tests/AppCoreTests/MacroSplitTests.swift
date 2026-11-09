import Foundation
import Testing
@testable import AppCore

struct MacroSplitTests {
    private let cut = Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle])

    @Test func deepCutCapsProteinSoCarbsAndFatFit() throws {
        // 74 kg, 15% fat, losing, 1,700 kcal. The goal target is 2.6 g/kg lean mass = 164 g
        // (Helms 2014 midpoint), which leaves carbs under 2 g/kg. Protein steps down to the
        // bottom of the Helms range (2.3 g/kg FFM = 145 g); fat holds 0.7 g/kg, carbs take the rest.
        let split = try #require(MacroSplit.make(calorieTarget: 1700, bodyMassKg: 74, bodyFatPercent: 15, heightCm: 183,
                                                 goals: cut, sex: .male, trainingStatus: .intermediate))
        #expect(split.proteinGramsUncapped == 164)
        #expect(split.proteinWasCapped)
        #expect(split.proteinGrams >= 145 && split.proteinGrams <= 155)
        #expect(split.carbsFloorGrams == 148)
        #expect(split.carbsGrams >= 148)
        #expect(split.fatFloorGrams == 52)
        #expect(split.fatGrams >= 52)
        let kcal = split.proteinGrams * 4 + split.carbsGrams * 4 + split.fatGrams * 9
        #expect(abs(kcal - 1700) < 15)
        #expect(split.proteinPercentOfCalories > 30 && split.proteinPercentOfCalories < 37)
        #expect(!split.tooFewCaloriesForFloors)
        // The line names the same carb and fat targets the bars fill to, with the floor beside them.
        #expect(split.summaryLine == "Protein 145 g · Carbs about \(Int(split.carbsGrams)) g (at least 148) · Fat at least 52 g")
        #expect(split.carbsGrams > 150)
        #expect(split.capNote?.contains("164 g") == true)
    }

    @Test func withoutBodyFatTheStepDownIsTwoGramsPerKilo() throws {
        // Phillips & Van Loon 2011: 1.8-2.0 g/kg in energy restriction.
        let split = try #require(MacroSplit.make(calorieTarget: 1700, bodyMassKg: 74, bodyFatPercent: nil, heightCm: 183,
                                                 goals: cut, sex: .male, trainingStatus: nil))
        #expect(split.proteinGramsUncapped == 163)
        #expect(split.proteinGrams == 148)
        #expect(split.carbsGrams >= 148 && split.fatGrams >= 52)
    }

    @Test func plentyOfCaloriesLeavesProteinAlone() throws {
        // 80 kg lifter gaining on 2,800 kcal: 1.6 g/kg = 128 g (Morton 2018), fat at 25% of
        // calories (inside Helms 2014's 15-30%), carbs the rest.
        let gain = Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.muscle])
        let split = try #require(MacroSplit.make(calorieTarget: 2800, bodyMassKg: 80, bodyFatPercent: 12, heightCm: 180,
                                                 goals: gain, sex: .male, trainingStatus: .advanced))
        #expect(!split.proteinWasCapped)
        #expect(split.proteinGrams == 128)
        #expect(split.fatGrams == 78)
        #expect(split.carbsGrams > 380)
        // Fat above its 56 g floor shows both numbers.
        #expect(split.summaryLine.hasSuffix("Fat about 78 g (at least 56)"))
        #expect(split.capNote == nil)
        #expect(!split.tooFewCaloriesForFloors)
    }

    @Test func tooFewCaloriesHoldsProteinAtMortonMinimumAndFlags() throws {
        // 1,200 kcal: even 1.6 g/kg (118 g) plus the fat floor leaves carbs well under 2 g/kg.
        let split = try #require(MacroSplit.make(calorieTarget: 1200, bodyMassKg: 74, bodyFatPercent: 15, heightCm: 183,
                                                 goals: cut, sex: .male, trainingStatus: .intermediate))
        #expect(split.tooFewCaloriesForFloors)
        #expect(split.proteinGrams == 118)
        #expect(split.fatGrams == 52)
        #expect(split.carbsGrams < split.carbsFloorGrams)
        #expect(split.capNote?.contains("too little") == true)
        // The carb floor doesn't fit, so the line shows only what does.
        #expect(split.summaryLine.contains("Carbs about \(Int(split.carbsGrams)) g ·"))
        #expect(!split.summaryLine.contains("at least 148"))
    }

    @Test func medicationFloorIsKeptEvenWhenItBreaksTheCarbFloor() throws {
        // A 2.0 g/kg medication floor (148 g) on 1,400 kcal: protein stays at 148 and the day is flagged.
        let split = try #require(MacroSplit.make(calorieTarget: 1400, bodyMassKg: 74, bodyFatPercent: 15, heightCm: 183,
                                                 goals: cut, sex: .male, trainingStatus: nil, minimumProteinPerKg: 2.0))
        #expect(split.proteinGrams == 148)
        #expect(split.tooFewCaloriesForFloors)
    }

    @Test func nonLiftersGetTheRDACarbFloor() throws {
        // Institute of Medicine 2005: 130 g a day.
        let health = Goals(weight: .maintain, focuses: [.health])
        let split = try #require(MacroSplit.make(calorieTarget: 2000, bodyMassKg: 70, bodyFatPercent: nil, heightCm: 170,
                                                 goals: health, sex: .female, trainingStatus: .untrained))
        #expect(split.carbsFloorGrams == 130)
        // Protein 1.2 g/kg is the goal's own target, not a cut: no "too few calories", fat not pinned to its floor.
        #expect(!split.tooFewCaloriesForFloors)
        #expect(split.capNote == nil)
        #expect(split.fatGrams > split.fatFloorGrams)
        #expect(!MacroSplit.isLifting(goals: health, trainingStatus: .advanced))
        #expect(MacroSplit.isLifting(goals: nil, trainingStatus: .novice))
        #expect(!MacroSplit.isLifting(goals: nil, trainingStatus: .untrained))
    }

    @Test func needsWeightAndCalories() {
        #expect(MacroSplit.make(calorieTarget: nil, bodyMassKg: 74, bodyFatPercent: nil, heightCm: nil, goals: cut, sex: .male, trainingStatus: nil) == nil)
        #expect(MacroSplit.make(calorieTarget: 1700, bodyMassKg: nil, bodyFatPercent: nil, heightCm: nil, goals: cut, sex: .male, trainingStatus: nil) == nil)
    }
}
