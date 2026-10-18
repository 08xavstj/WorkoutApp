import Testing
@testable import AppCore

struct MedicationKnowledgeTests {
    @Test(arguments: [
        ("Metoprolol succinate 25 mg", "betaBlocker"),
        ("Vyvanse", "stimulant"),
        ("ozempic 0.5mg", "glp1"),
        ("LEXAPRO", "ssri"),
        ("Cipro 500", "fluoroquinolone"),
        ("Depo Testosterone", "testosterone"),
    ])
    func matchesGenericAndBrandNames(name: String, expected: String) {
        #expect(MedicationKnowledge.match(name)?.id == expected)
    }

    @Test func unknownNamesDontMatch() {
        #expect(MedicationKnowledge.match("Vitamin D3") == nil)
        #expect(MedicationKnowledge.match("") == nil)
    }

    @Test func partialWordsDontMatch() {
        // "pro" shouldn't match "prozac"; whole words only.
        #expect(MedicationKnowledge.match("pro") == nil)
    }

    @Test func glp1RaisesProtein() throws {
        let glp1 = try #require(MedicationKnowledge.match("Wegovy"))
        #expect(glp1.proteinGramsPerKg == 2.0)
        #expect(NutritionTargets.proteinGrams(bodyMassKg: 80, gramsPerKg: 2.0) == 160)
    }

    @Test func everyClassHasSourcesAndNames() {
        for drug in MedicationKnowledge.classes {
            #expect(!drug.sources.isEmpty, "\(drug.id) has no sources")
            #expect(!drug.names.isEmpty)
            #expect(drug.names.allSatisfy { $0 == $0.lowercased() })
        }
        #expect(Set(MedicationKnowledge.classes.map(\.id)).count == MedicationKnowledge.classes.count)
    }
}
