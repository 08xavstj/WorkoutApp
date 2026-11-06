import Testing
@testable import AppCore

struct SupplementKnowledgeTests {
    @Test(arguments: [
        ("Creatine monohydrate 5 g", "creatine"),
        ("Creapure", "creatine"),
        ("Ashwagandha KSM-66 600mg", "ashwagandha"),
        ("KSM-66", "ashwagandha"),
        ("Sensoril", "ashwagandha"),
        ("Vitamin D3 2000 IU", "vitaminD"),
        ("Fish oil", "omega3"),
        ("Omega-3", "omega3"),
        ("Tart cherry concentrate", "tartCherry"),
        ("Beta-alanine", "betaAlanine"),
        ("Whey protein", "protein"),
        ("Melatonin 1 mg", "melatonin"),
        ("ZMA", "magnesium"),
        ("Beetroot shot", "nitrate"),
        ("C4 pre-workout", "preWorkout"),
        ("Fenugreek", "testosteroneBooster"),
        ("Turkesterone", "ecdysterone"),
        ("Multivitamin", "multivitamin"),
    ])
    func matchesNamesAndAliases(name: String, expected: String) {
        #expect(SupplementKnowledge.match(name)?.id == expected)
    }

    @Test func unknownAndPartialNamesDontMatch() {
        #expect(SupplementKnowledge.match("Metoprolol") == nil)
        #expect(SupplementKnowledge.match("") == nil)
        // "Testosterone" alone is a medication (MedicationKnowledge), not a booster.
        #expect(SupplementKnowledge.match("Testosterone") == nil)
        // Whole words only: "creat" shouldn't match creatine.
        #expect(SupplementKnowledge.match("creat") == nil)
    }

    @Test func everyEntryHasGradesCitationsAndDosing() {
        for entry in SupplementKnowledge.entries {
            #expect(!entry.claims.isEmpty, "\(entry.id) has no claims")
            #expect(entry.sources.count >= 2, "\(entry.id) needs at least two sources")
            #expect(!entry.names.isEmpty)
            #expect(entry.names.allSatisfy { $0 == $0.lowercased() })
            #expect(!entry.dose.isEmpty && !entry.timing.isEmpty && !entry.expect.isEmpty)
            #expect(!entry.cautions.isEmpty, "\(entry.id) has no cautions")
            for claim in entry.claims {
                #expect(!claim.summary.isEmpty && !claim.purpose.isEmpty)
            }
        }
        #expect(Set(SupplementKnowledge.entries.map(\.id)).count == SupplementKnowledge.entries.count)
    }

    @Test func gradesFollowThePositionStands() {
        #expect(SupplementKnowledge.match("creatine")?.evidence == .strong)
        #expect(SupplementKnowledge.match("caffeine")?.evidence == .strong)
        #expect(SupplementKnowledge.match("whey")?.evidence == .strong)
        #expect(SupplementKnowledge.match("beta alanine")?.evidence == .moderate)
        #expect(SupplementKnowledge.match("BCAA")?.evidence == .weak)
        #expect(SupplementKnowledge.match("tribulus")?.evidence == SupplementKnowledge.Evidence.none)
    }

    @Test func ashwagandhaIsModerateForStressAndWeakForStrength() throws {
        let entry = try #require(SupplementKnowledge.match("ashwagandha"))
        let strength = try #require(entry.claims.first { $0.purpose.contains("Strength") })
        let stress = try #require(entry.claims.first { $0.purpose.contains("Stress") })
        #expect(strength.evidence == .weak)
        #expect(stress.evidence == .moderate)
        #expect(entry.evidence == .moderate)
        #expect(entry.cautions.contains { $0.localizedCaseInsensitiveContains("liver") })
        #expect(entry.cautions.contains { $0.localizedCaseInsensitiveContains("pregnancy") })
        #expect(entry.cautions.contains { $0.localizedCaseInsensitiveContains("thyroid") })
    }

    @Test func evidenceOrderingAndCategories() {
        #expect(SupplementKnowledge.Evidence.none < .weak)
        #expect(SupplementKnowledge.Evidence.weak < .moderate)
        #expect(SupplementKnowledge.Evidence.moderate < .strong)
        for category in SupplementKnowledge.Category.allCases {
            #expect(!SupplementKnowledge.entries(in: category).isEmpty, "\(category.rawValue) is empty")
        }
    }
}
