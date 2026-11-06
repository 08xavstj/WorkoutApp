import Testing
@testable import AppCore

struct MicronutrientFixTests {
    @Test func magnesiumFixesCloseTheGapWithRealisticPortions() throws {
        let finding = Micronutrients.Finding(nutrient: .magnesium, average: 210, target: 400, kind: .low, effect: nil)
        let fixes = Micronutrients.fixes(for: finding)
        #expect(fixes.count == 3)
        let seeds = try #require(fixes.first { $0.food.name == "pumpkin seeds" })
        // Gap 190 mg at 550 mg/100 g = 34.5 g, rounded up to 40 g (+220 mg), under the 40 g cap.
        #expect(seeds.grams == 40)
        #expect(abs(seeds.amount - 220) < 0.01)
        #expect(seeds.closesGap)
        // Spinach can't close 190 mg within 150 g: it's capped and marked as a partial fix.
        let spinach = try #require(fixes.first { $0.food.name == "cooked spinach" })
        #expect(spinach.grams == 150)
        #expect(!spinach.closesGap)
        // Fixes that close the gap come first.
        #expect(fixes.first?.closesGap == true)
    }

    @Test func noFixesWhenAtTarget() {
        let finding = Micronutrients.Finding(nutrient: .iron, average: 18, target: 18, kind: .ok, effect: nil)
        #expect(Micronutrients.fixes(for: finding).isEmpty)
    }

    @Test func seleniumFixStaysWithinOneOrTwoBrazilNuts() throws {
        let finding = Micronutrients.Finding(nutrient: .selenium, average: 20, target: 55, kind: .low, effect: nil)
        let nuts = try #require(Micronutrients.fixes(for: finding).first { $0.food.name == "Brazil nuts" })
        // 35 µg gap = 1.8 g; rounded up to the 5 g step, never above the 10 g cap (upper limit 400 µg).
        #expect(nuts.grams == 5)
        #expect(nuts.amount + finding.average < 400)
    }

    @Test func everyNutrientHasAboutThreeUSDAFoods() {
        for nutrient in Micronutrients.Nutrient.allCases {
            let foods = Micronutrients.foodSources(nutrient)
            #expect(foods.count == 3, "\(nutrient.name) has \(foods.count) foods")
            #expect(foods.allSatisfy { $0.perHundredGrams > 0 && $0.maxGrams > 0 })
            #expect(foods.allSatisfy { $0.source == "USDA FoodData Central" })
        }
    }

    @Test func sexAndAgeTargetsFollowNIHODS() {
        #expect(Micronutrients.Nutrient.iron.target(.male) == 8)
        #expect(Micronutrients.Nutrient.iron.target(.female) == 18)
        #expect(Micronutrients.Nutrient.iron.target(.female, age: 55) == 8)
        #expect(Micronutrients.Nutrient.magnesium.target(.male) == 400)
        #expect(Micronutrients.Nutrient.magnesium.target(.male, age: 40) == 420)
        #expect(Micronutrients.Nutrient.magnesium.target(.female) == 310)
        #expect(Micronutrients.Nutrient.magnesium.target(.female, age: 40) == 320)
        #expect(Micronutrients.Nutrient.calcium.target(.female, age: 55) == 1200)
        #expect(Micronutrients.Nutrient.calcium.target(.male, age: 55) == 1000)
        #expect(Micronutrients.Nutrient.vitaminD.target(.male, age: 75) == 20)
    }

    @Test func toFixListsLowNutrientsWorstFirst() {
        let findings = Micronutrients.assess(
            averages: [.magnesium: 200, .iron: 3, .vitaminC: 100],
            daysLogged: 7, sex: .female
        )
        let toFix = Micronutrients.toFix(findings)
        #expect(toFix.map(\.nutrient) == [.iron, .magnesium])
    }

    @Test func summaryLineNamesTheWorstThree() {
        #expect(Micronutrients.summaryLine(findings: []) == nil)
        let fine = Micronutrients.assess(averages: [.vitaminC: 100], daysLogged: 5, sex: .male)
        #expect(Micronutrients.summaryLine(findings: fine) == "Vitamins and minerals near target this week")
        let low = Micronutrients.assess(averages: [.magnesium: 100, .iron: 2, .vitaminD: 2, .zinc: 1], daysLogged: 7, sex: .female)
        let line = Micronutrients.summaryLine(findings: low)
        #expect(line?.hasPrefix("4 low this week: ") == true)
        #expect(line?.hasSuffix(" and 1 more") == true)
        let two = Micronutrients.assess(averages: [.magnesium: 100, .iron: 2], daysLogged: 7, sex: .female)
        #expect(Micronutrients.summaryLine(findings: two) == "2 low this week: iron and magnesium")
    }

    @Test func athleteNotesOnlyWhereTheIOCConsensusSaysSo() {
        #expect(Micronutrients.athleteNote(.iron, sex: .female, focuses: [.endurance])?.contains("ferritin") == true)
        #expect(Micronutrients.athleteNote(.iron, sex: .male, focuses: [.muscle]) == nil)
        #expect(Micronutrients.athleteNote(.vitaminD, sex: .male, focuses: [.strength]) != nil)
        #expect(Micronutrients.athleteNote(.zinc, sex: .female, focuses: [.endurance]) == nil)
    }
}
