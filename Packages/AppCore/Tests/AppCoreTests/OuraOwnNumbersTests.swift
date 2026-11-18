import Foundation
import Testing
@testable import AppCore

struct OuraOwnNumbersTests {
    @Test func scopesOnlyGrowWhenThePanelIsOn() {
        #expect(Oura.requestedScopes(ownNumbers: false) == "daily")
        #expect(Oura.requestedScopes(ownNumbers: true) == "daily spo2 heart_health")
        #expect(Oura.requestedScopes(ownNumbers: true, heartHealth: false) == "daily spo2")
        #expect(Oura.needsReconnect(grantedScope: "daily", required: Oura.requestedScopes(ownNumbers: true)))
        #expect(!Oura.needsReconnect(grantedScope: "daily spo2 heart_health", required: Oura.requestedScopes(ownNumbers: true)))
        #expect(!Oura.needsReconnect(grantedScope: "daily", required: Oura.requestedScopes(ownNumbers: false)))
    }

    @Test func decodesTheAPIShapes() throws {
        let json = """
        {"data": [{"id": "a", "day": "2026-11-17", "stress_high": 2700, "recovery_high": 5400, "day_summary": "restored"}], "next_token": null}
        """
        let page = try JSONDecoder().decode(Oura.Page<Oura.DailyStress>.self, from: Data(json.utf8))
        #expect(page.data.first == Oura.DailyStress(day: "2026-11-17", stressHigh: 2700, recoveryHigh: 5400, daySummary: "restored"))
        let age = try JSONDecoder().decode(Oura.CardiovascularAge.self, from: Data(#"{"day": "2026-11-17", "vascular_age": 31}"#.utf8))
        #expect(age.vascularAge == 31)
        let vo2 = try JSONDecoder().decode(Oura.VO2Max.self, from: Data(#"{"id": "x", "day": "2026-11-16", "timestamp": "2026-11-16T07:00:00+00:00", "vo2_max": 46.5}"#.utf8))
        #expect(vo2.vo2Max == 46.5)
        let spo2 = try JSONDecoder().decode(Oura.DailySpO2.self, from: Data(#"{"id": "y", "day": "2026-11-17", "spo2_percentage": {"average": 96.2}, "breathing_disturbance_index": 7}"#.utf8))
        #expect(spo2.breathingDisturbanceIndex == 7)
        let score = try JSONDecoder().decode(Oura.DailyScore.self, from: Data(#"{"id": "z", "day": "2026-11-17", "score": null, "contributors": {}}"#.utf8))
        #expect(score.score == nil)
    }

    @Test func rowsShowTheLatestKnownValue() {
        var numbers = OuraOwnNumbers()
        numbers.readiness = [Oura.DailyScore(day: "2026-11-16", score: 70), Oura.DailyScore(day: "2026-11-17", score: 82),
                             Oura.DailyScore(day: "2026-11-18", score: nil)]
        numbers.cardiovascularAge = [Oura.CardiovascularAge(day: "2026-11-17", vascularAge: 30)]
        numbers.resilience = [Oura.DailyResilience(day: "2026-11-17", level: "solid")]
        numbers.stress = [Oura.DailyStress(day: "2026-11-17", stressHigh: 2700, recoveryHigh: nil, daySummary: "stressful")]
        let rows = numbers.rows(age: 34)
        #expect(rows.map(\.id) == [.readiness, .stress, .resilience, .cardiovascularAge])
        #expect(rows[0].value == "82")
        #expect(rows[0].day == "2026-11-17")
        #expect(rows[0].recent == [70, 82])
        #expect(rows[1].value == "Stressful · 45 min high stress")
        #expect(rows[2].value == "Solid")
        #expect(rows[3].value == "30 years (-4 vs your age)")
        #expect(OuraOwnNumbers().rows().isEmpty)
    }

    @Test func mergeReplacesDaysAndDropsOldOnes() {
        var held = OuraOwnNumbers()
        held.sleep = [Oura.DailyScore(day: "2026-09-01", score: 60), Oura.DailyScore(day: "2026-11-17", score: 70)]
        var fresh = OuraOwnNumbers()
        fresh.sleep = [Oura.DailyScore(day: "2026-11-17", score: 75), Oura.DailyScore(day: "2026-11-18", score: 80)]
        held.merge(fresh, cutoffDay: "2026-10-01")
        #expect(held.sleep == [Oura.DailyScore(day: "2026-11-17", score: 75), Oura.DailyScore(day: "2026-11-18", score: 80)])
    }

    @Test func olderFilesDecode() throws {
        let decoded = try JSONDecoder().decode(OuraOwnNumbers.self, from: Data(#"{"readiness": [{"day": "2026-11-17", "score": 80}]}"#.utf8))
        #expect(decoded.readiness.count == 1)
        #expect(decoded.vo2Max.isEmpty)
    }

    @Test func everyMetricExplainsItsEvidence() {
        for metric in OuraOwnNumbers.Metric.allCases {
            #expect(!metric.title.isEmpty)
            #expect(!metric.evidence.isEmpty)
        }
    }
}
