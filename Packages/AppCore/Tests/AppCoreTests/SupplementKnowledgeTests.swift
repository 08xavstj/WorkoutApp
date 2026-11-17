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

    @Test func shortSummaryIsOneSentenceWithoutCitations() {
        let claim = SupplementKnowledge.Claim(purpose: "x", evidence: .strong,
                                              summary: "More work in repeated efforts (ISSN 2017). Little effect on endurance (Smith 2020).")
        #expect(claim.shortSummary == "More work in repeated efforts.")
        let one = SupplementKnowledge.Claim(purpose: "y", evidence: .weak, summary: "Small effects; no gain in trained lifters (Jakubowski 2020).")
        #expect(one.shortSummary == "Small effects; no gain in trained lifters.")
    }

    @Test func unknownAndPartialNamesDontMatch() {
        #expect(SupplementKnowledge.match("Metoprolol") == nil)
        // A salt form, not creatine.
        #expect(SupplementKnowledge.match("Doxycycline Monohydrate") == nil)
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

    /// Stress and sleep were "moderate" until the evidence audit (should-change 5):
    /// the pooled certainty was rated low and the trials are small and maker-funded,
    /// which is this file's definition of weak.
    @Test func ashwagandhaIsWeakForStressSleepAndStrength() throws {
        let entry = try #require(SupplementKnowledge.match("ashwagandha"))
        let strength = try #require(entry.claims.first { $0.purpose.contains("Strength") })
        let stress = try #require(entry.claims.first { $0.purpose.contains("Stress") })
        let sleep = try #require(entry.claims.first { $0.purpose.contains("Sleep") })
        #expect(strength.evidence == .weak)
        #expect(stress.evidence == .weak)
        #expect(sleep.evidence == .weak)
        #expect(entry.evidence == .weak)
        #expect(entry.cautions.contains { $0.localizedCaseInsensitiveContains("liver") })
        #expect(entry.cautions.contains { $0.localizedCaseInsensitiveContains("pregnancy") })
        #expect(entry.cautions.contains { $0.localizedCaseInsensitiveContains("thyroid") })
    }

    /// Evidence audit M6: the old "Heart and general health: moderate" claim
    /// is split, and the atrial-fibrillation risk is a caution (Gencer 2021).
    @Test func omega3SplitsHeartClaimsAndWarnsOfAtrialFibrillation() throws {
        let entry = try #require(SupplementKnowledge.match("fish oil"))
        func grade(_ purpose: String) -> SupplementKnowledge.Evidence? { entry.claims.first { $0.purpose == purpose }?.evidence }
        #expect(grade("Triglycerides") == .moderate)
        #expect(grade("Heart events in people at high risk (prescription EPA)") == .moderate)
        #expect(grade("Heart health in healthy people") == SupplementKnowledge.Evidence.none)
        #expect(grade("Heart and general health") == nil)
        #expect(entry.expect.hasPrefix("No felt effect. In healthy people, trials haven't shown fewer heart events"))
        #expect(entry.cautions.contains { $0.contains("atrial fibrillation") && $0.contains("Gencer 2021") })
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
