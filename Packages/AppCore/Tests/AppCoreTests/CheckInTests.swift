import Foundation
import Testing
@testable import AppCore

struct CheckInTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func morning(sore areas: [MorningCheckIn.BodyArea], level: Int) -> MorningCheckIn {
        var checkIn = MorningCheckIn(day: start)
        checkIn.soreAreas = areas
        checkIn.soreness = level
        return checkIn
    }

    @Test func soreLegsSuggestUpperBody() {
        #expect(CheckInCoaching.focus(for: morning(sore: [.legs, .glutes], level: 7)) == .upper)
        #expect(CheckInCoaching.focus(for: morning(sore: [.chest, .arms], level: 6)) == .lower)
        #expect(CheckInCoaching.focus(for: morning(sore: [.legs, .chest], level: 7)) == nil)
        #expect(CheckInCoaching.focus(for: morning(sore: [.legs], level: 3)) == nil)
    }

    @Test func feverMeansRest() {
        var checkIn = MorningCheckIn(day: start)
        checkIn.symptoms = [.fever]
        #expect(CheckInCoaching.advice(for: checkIn)?.hasPrefix("Fever") == true)
    }

    @Test func alcoholLowersHRVInsight() throws {
        var days: [CheckInDay] = []
        for index in 0..<18 {
            var evening = EveningCheckIn(day: start)
            let drank = index < 8
            evening.drinks = drank ? 3 : 0
            let wobble = index.isMultiple(of: 2) ? 2.0 : -2.0
            days.append(CheckInDay(morning: start.addingTimeInterval(Double(index) * 86_400), evening: evening, checkIn: nil,
                                   hrv: (drank ? 40 : 50) + wobble, restingHeartRate: 60 + wobble, sleepScore: 80))
        }
        let insights = CheckInInsights.analyze(days)
        let hrv = try #require(insights.first { $0.factor == "2+ drinks" && $0.outcome == .hrv })
        #expect(abs(hrv.percentChange - -20) < 0.001)
        #expect(hrv.isGood == false)
        #expect(hrv.daysWith == 8)
        // Resting HR only wobbles, so no insight for it.
        #expect(!insights.contains { $0.outcome == .restingHeartRate })
    }

    @Test func smallNoisyDifferencesAreNotShown() {
        var days: [CheckInDay] = []
        for index in 0..<16 {
            var evening = EveningCheckIn(day: start)
            evening.drinks = index < 8 ? 3 : 0
            // Means differ by 1 ms against a ±8 ms day-to-day swing.
            let wobble = [8.0, -8.0, 5.0, -5.0][index % 4]
            days.append(CheckInDay(morning: start.addingTimeInterval(Double(index) * 86_400), evening: evening, checkIn: nil,
                                   hrv: (index < 8 ? 49 : 50) + wobble, restingHeartRate: nil, sleepScore: nil))
        }
        #expect(!CheckInInsights.analyze(days).contains { $0.outcome == .hrv })
    }

    @Test func tTestPValues() {
        // t = 2.0 with large df: two-sided p ≈ 0.0455.
        let p = CheckInInsights.welchPValue(meanA: 0.02, varA: 1, nA: 10_000, meanB: 0, varB: 0.000001, nB: 10_000)
        #expect(abs(p - 0.0455) < 0.002)
        #expect(abs(CheckInInsights.regularizedIncompleteBeta(x: 0.5, a: 2, b: 2) - 0.5) < 1e-6)
    }

    @Test func needsEnoughDaysOnBothSides() {
        var evening = EveningCheckIn(day: start)
        evening.drinks = 3
        let days = (0..<2).map { CheckInDay(morning: start.addingTimeInterval(Double($0) * 86_400), evening: evening, checkIn: nil, hrv: 40, restingHeartRate: nil, sleepScore: nil) }
        #expect(CheckInInsights.analyze(days).isEmpty)
        #expect(CheckInInsights.daysUntilReady(days) == 12)
    }
}
