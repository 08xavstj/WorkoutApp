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

    @Test func habitProgressCountsDaysEachWay() throws {
        let days = (0..<10).map { index -> CheckInDay in
            var evening = EveningCheckIn(day: start)
            evening.sauna = index < 4
            return CheckInDay(morning: start.addingTimeInterval(Double(index) * 86_400), evening: evening, checkIn: nil,
                              hrv: 50, restingHeartRate: 60, sleepScore: 80)
        }
        let sauna = try #require(CheckInInsights.progress(days).first { $0.name == "Sauna" })
        #expect(sauna.daysWith == 4)
        #expect(sauna.daysWithout == 6)
        #expect(sauna.text == "4/7 days")
        // Never seen: not listed.
        #expect(!CheckInInsights.progress(days).contains { $0.name == "Nicotine" })
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

struct CheckInProgressFilterTests {
    let progress = [
        CheckInInsights.FactorProgress(name: "Any alcohol", daysWith: 4, daysWithout: 9, needed: 7),
        CheckInInsights.FactorProgress(name: "2+ drinks", daysWith: 2, daysWithout: 9, needed: 7),
        CheckInInsights.FactorProgress(name: "Late caffeine", daysWith: 3, daysWithout: 9, needed: 7),
    ]

    /// "HRV 6% lower after any alcohol" and "Still collecting: Any alcohol 4/7" never show together.
    @Test func progressCoveredByAPatternIsDropped() {
        let alcohol = CheckInInsights.Insight(factor: "Any alcohol", outcome: .hrv, percentChange: -6,
                                              daysWith: 8, daysWithout: 20, isGood: false)
        let left = CheckInInsights.uncovered(progress, by: [alcohol])
        #expect(left.map(\.name) == ["Late caffeine"])
        #expect(CheckInInsights.uncovered(progress, by: []).count == 3)
    }
}

struct EveningCheckInDoneTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func time(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func aDrinkLoggedOnItsOwnIsNotTheCheckIn() {
        var evening = EveningCheckIn(day: time(day: 16, 0))
        evening.alcohol = [AlcoholEntry(kind: .beer, millilitres: 355, abv: 5)]
        evening.syncDrinksFromAlcohol()
        #expect(evening.drinks == 1)
        #expect(!evening.isDone)
        // The drinks log emptied again: still not the check-in.
        evening.alcohol = []
        evening.syncDrinksFromAlcohol()
        #expect(!evening.isDone)
        // Saving the form marks it done, drinks or not.
        evening.completed = true
        #expect(evening.isDone)
    }

    @Test func recordsFromBeforeTheFlagCountWhenAnythingButDrinksWasAnswered() throws {
        var old = EveningCheckIn(day: time(day: 15, 0))
        old.stress = 2
        #expect(old.isDone)
        var caffeine = EveningCheckIn(day: time(day: 15, 0))
        caffeine.caffeineMg = 95
        #expect(caffeine.isDone)
        #expect(!EveningCheckIn(day: time(day: 15, 0)).isDone)
        // A record saved before `completed` existed still decodes.
        let legacy = Data(#"{"day":0,"drinks":2,"stress":3}"#.utf8)
        let decoded = try JSONDecoder().decode(EveningCheckIn.self, from: legacy)
        #expect(decoded.completed == nil)
        #expect(decoded.isDone)
        // And the flag survives a round trip.
        var done = EveningCheckIn(day: time(day: 15, 0))
        done.completed = true
        let again = try JSONDecoder().decode(EveningCheckIn.self, from: JSONEncoder().encode(done))
        #expect(again.completed == true)
    }

    @Test func beforeFourTheEveningIsStillYesterdays() {
        #expect(EveningCheckIn.day(for: time(day: 16, 21, 30), calendar: calendar) == time(day: 16, 0))
        #expect(EveningCheckIn.day(for: time(day: 17, 0, 30), calendar: calendar) == time(day: 16, 0))
        #expect(EveningCheckIn.day(for: time(day: 17, 3, 59), calendar: calendar) == time(day: 16, 0))
        #expect(EveningCheckIn.day(for: time(day: 17, 4), calendar: calendar) == time(day: 17, 0))
    }
}
