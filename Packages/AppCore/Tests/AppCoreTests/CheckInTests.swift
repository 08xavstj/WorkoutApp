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
        for index in 0..<10 {
            var evening = EveningCheckIn(day: start)
            evening.drinks = index < 4 ? 3 : 0
            days.append(CheckInDay(morning: start.addingTimeInterval(Double(index) * 86_400), evening: evening, checkIn: nil,
                                   hrv: index < 4 ? 40 : 50, restingHeartRate: 60, sleepScore: 80))
        }
        let insights = CheckInInsights.analyze(days)
        let hrv = try #require(insights.first { $0.factor == "2+ drinks" && $0.outcome == .hrv })
        #expect(abs(hrv.percentChange - -20) < 0.001)
        #expect(hrv.isGood == false)
        #expect(hrv.daysWith == 4)
        // Resting HR and sleep didn't change, so no insight for them.
        #expect(!insights.contains { $0.outcome == .restingHeartRate })
    }

    @Test func needsEnoughDaysOnBothSides() {
        var evening = EveningCheckIn(day: start)
        evening.drinks = 3
        let days = (0..<2).map { CheckInDay(morning: start.addingTimeInterval(Double($0) * 86_400), evening: evening, checkIn: nil, hrv: 40, restingHeartRate: nil, sleepScore: nil) }
        #expect(CheckInInsights.analyze(days).isEmpty)
        #expect(CheckInInsights.daysUntilReady(days) == 12)
    }
}
