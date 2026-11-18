import Foundation
import Testing
@testable import AppCore

struct ShareCardsTests {
    func split(_ index: Int, seconds: Double, partial: Bool = false) -> CardioRoute.Split {
        CardioRoute.Split(index: index, meters: partial ? 400 : 1000, seconds: seconds, averageBpm: nil,
                          elevationChange: nil, isPartial: partial)
    }

    @Test func caloriesAreARangeOfPlusMinusTwentyPercent() {
        #expect(ShareCards.calorieRange(500) == 400...600)
        #expect(ShareCards.calorieRange(333) == 270...400)
        #expect(ShareCards.calorieRange(nil) == nil)
        #expect(ShareCards.calorieRange(0) == nil)
        #expect(ShareCards.calorieRange(.nan) == nil)
        #expect(ShareCards.calorieText(500)?.hasPrefix("≈ 400–600") == true)
    }

    @Test func allWholeSplitsWhenTheyFit() {
        let splits = [split(1, seconds: 300), split(2, seconds: 290), split(3, seconds: 120, partial: true)]
        #expect(ShareCards.topSplits(splits).map(\.index) == [1, 2])
    }

    @Test func fastestSplitsInRouteOrderWhenThereAreMany() {
        let seconds: [Double] = [300, 280, 310, 270, 305, 290, 285, 320]
        let splits = seconds.enumerated().map { split($0.offset + 1, seconds: $0.element) }
        // Fastest five: 270 (4), 280 (2), 285 (7), 290 (6), 300 (1).
        #expect(ShareCards.topSplits(splits).map(\.index) == [1, 2, 4, 6, 7])
        #expect(ShareCards.topSplits(splits, maximum: 2).map(\.index) == [2, 4])
    }

    @Test func zoneFractionsSumToOne() {
        let fractions = ShareCards.zoneFractions([10, 20, 10, 0, 0])
        #expect(fractions == [0.25, 0.5, 0.25, 0, 0])
        #expect(ShareCards.zoneFractions([0, 0]) == nil)
        #expect(ShareCards.zoneFractions([]) == nil)
        #expect(ShareCards.zoneFractions([.nan, 5]) == [0, 1])
    }

    @Test func trimmedRoutesShowRoundedDistanceAndMatchingPace() {
        #expect(ShareCards.distanceText(meters: 5_037, miles: false, trimmed: true) == "5.0 km")
        #expect(ShareCards.distanceText(meters: 5_037, miles: false, trimmed: false) == "5.04 km")
        #expect(ShareCards.shownDistanceMeters(5_037, miles: false, trimmed: true) == 5_000)
        #expect(ShareCards.shownDistanceMeters(5_037, miles: false, trimmed: false) == 5_037)
        #expect(abs(ShareCards.shownDistanceMeters(5_037, miles: true, trimmed: true) - 3.1 * CardioSummary.metersPerMile) < 1e-6)
    }

    @Test func topExercisesKeepRecordsAndSessionOrder() {
        let results = (0..<7).map { index in
            WorkoutSummary.ExerciseResult(index: index, exerciseID: "e\(index)", name: "E\(index)", workingSets: 3, stages: 0,
                                          reps: 24, volumeKg: Double(index) * 100, groups: [], bestSet: nil,
                                          estimatedOneRepMaxKg: 0)
        }
        // Volume order: 6, 5, 4, 3, 2...; exercise 0 has a record.
        let top = ShareCards.topExercises(results, withRecords: [0])
        #expect(top.map(\.index) == [0, 3, 4, 5, 6])
        #expect(ShareCards.topExercises(Array(results.prefix(3))).count == 3)
    }

    @Test func muscleShades() {
        #expect(ShareCards.shade(sets: 0) == .none)
        #expect(ShareCards.shade(sets: 0.5) == .some)
        #expect(ShareCards.shade(sets: 2) == .worked)
        #expect(ShareCards.shade(sets: .nan) == .none)
    }

    @Test func weeklySummaryAgainstWHO() {
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        var week = WeeklyShareSummary(weekStart: monday, trainingDays: 3, cardioSessions: 2, cardioMinutes: 70,
                                      moderateMinutes: 100, vigorousMinutes: 20, strengthDays: 2, sleepRegularity: 81)
        #expect(week.activeMinutes == 140)
        #expect(week.activeBand == .below)
        #expect(week.activeLine == "140 of 150 min (WHO 150–300)")
        #expect(week.strengthMet == true)
        #expect(week.strengthLine == "2 of 2 strength days")
        #expect(week.sleepLine?.hasPrefix("Sleep regularity 81 of 100") == true)
        week.vigorousMinutes = 30
        #expect(week.activeBand == .within)
        week.moderateMinutes = 400
        #expect(week.activeBand == .above)
        #expect(week.activeFraction == 1)
        week.strengthDays = 1
        #expect(week.strengthMet == false)
        week.moderateMinutes = nil
        #expect(week.activeMinutes == nil)
        #expect(week.activeBand == nil)
        #expect(week.activeLine == nil)
        week.strengthDays = nil
        #expect(week.strengthMet == nil)
    }

    @Test func weeklyBandEdges() {
        let monday = Date(timeIntervalSince1970: 0)
        let at150 = WeeklyShareSummary(weekStart: monday, trainingDays: 0, cardioSessions: 0, cardioMinutes: 0,
                                       moderateMinutes: 150, vigorousMinutes: 0)
        #expect(at150.activeBand == .within)
        let at300 = WeeklyShareSummary(weekStart: monday, trainingDays: 0, cardioSessions: 0, cardioMinutes: 0,
                                       moderateMinutes: 100, vigorousMinutes: 100)
        #expect(at300.activeBand == .within)
        #expect(at300.activeFraction == 300.0 / 360.0)
    }
}
