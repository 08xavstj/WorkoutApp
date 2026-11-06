import Testing
@testable import AppCore

struct MicronutrientSupplementTests {
    @Test func dosesBecomeNutrientAmounts() throws {
        let d = try #require(Micronutrients.supplementAmount(.init(name: "Vitamin D", dose: "2000 IU")))
        #expect(d.nutrient == .vitaminD)
        #expect(d.amount == 50) // 40 IU = 1 µg
        let mg = try #require(Micronutrients.supplementAmount(.init(name: "Magnesium glycinate", dose: "300 mg")))
        #expect(mg.nutrient == .magnesium && mg.amount == 300)
        let b12 = try #require(Micronutrients.supplementAmount(.init(name: "Vitamin B12", dose: "1 mg")))
        #expect(b12.amount == 1000)
        #expect(Micronutrients.supplementAmount(.init(name: "Creatine", dose: "5 g")) == nil)
        #expect(Micronutrients.supplementAmount(.init(name: "Vitamin D", dose: "one tablet")) == nil)
        #expect(Micronutrients.supplementAmount(.init(name: "Multivitamin", dose: "1000 mg")) == nil)
    }

    @Test func takenDosesAverageOverTheWeek() {
        let taken = Array(repeating: Micronutrients.SupplementDose(name: "Vitamin D", dose: "2000 IU"), count: 7)
            + [Micronutrients.SupplementDose(name: "Magnesium", dose: "300 mg")]
        let averages = Micronutrients.supplementAverages(taken, days: 7)
        #expect(averages[.vitaminD] == 50)
        #expect(abs((averages[.magnesium] ?? 0) - 300.0 / 7) < 0.0001)
    }

    @Test func supplementsCountTowardTheFinding() throws {
        let findings = Micronutrients.assess(averages: [.vitaminD: 3, .zinc: 10], supplements: [.vitaminD: 50],
                                             daysLogged: 7, sex: .male, age: 40)
        let d = try #require(findings.first { $0.nutrient == .vitaminD })
        #expect(d.average == 53)
        #expect(d.fromSupplements == 50)
        #expect(d.kind == .ok)
        #expect(findings.first { $0.nutrient == .zinc }?.fromSupplements == 0)
    }

    @Test func tooHighIsSeparate() {
        let findings = Micronutrients.assess(averages: [.sodium: 3200, .zinc: 10], daysLogged: 7, sex: .male)
        #expect(Micronutrients.tooHigh(findings).map(\.nutrient) == [.sodium])
    }
}

struct LabGuidelineNoteTests {
    @Test func vitaminDBetweenTheLinesSaysBoth() {
        let note = LabMarkers.guidelineNote(markerID: "vitaminD", value: 24, unit: "ng/mL", labLow: 30)
        #expect(note == "Below the lab's range; above the 20 ng/mL IOM line. Guidelines differ.")
        #expect(LabMarkers.guidelineNote(markerID: "vitaminD", value: 15, unit: "ng/mL", labLow: 30) == nil)
        #expect(LabMarkers.guidelineNote(markerID: "vitaminD", value: 35, unit: "ng/mL", labLow: 30) == nil)
        #expect(LabMarkers.guidelineNote(markerID: "ferritin", value: 25, unit: "ng/mL", labLow: 30) == nil)
    }
}
