import Foundation
import Testing
@testable import AppCore

struct FunctionalTestsTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func ageGates() {
        #expect(FunctionalTest.available(age: 30) == [.pushUps])
        #expect(FunctionalTest.available(age: 44) == [.pushUps])
        #expect(FunctionalTest.available(age: 45) == [.pushUps, .sittingRising])
        #expect(FunctionalTest.available(age: 49) == [.pushUps, .sittingRising])
        #expect(FunctionalTest.available(age: 50) == [.pushUps, .sittingRising, .oneLegStand])
        #expect(FunctionalTest.available(age: 80) == FunctionalTest.allCases)
    }

    @Test(arguments: [
        (45, FunctionalTest.Interpretation.Standing.top),
        (41, .top),
        (40, .middle),
        (10, .middle),
        (9, .low),
        (0, .low),
    ])
    func pushUpGroupsForMen(count: Int, expected: FunctionalTest.Interpretation.Standing) {
        let result = FunctionalTest.interpret(.pushUps, value: Double(count), age: 34, sex: .male)
        #expect(result.standing == expected)
        #expect(result.detail.contains("one study"))
        #expect(result.detail.contains("Linked with, in one cohort"))
    }

    @Test func pushUpsHaveNoComparisonForWomen() {
        let result = FunctionalTest.interpret(.pushUps, value: 45, age: 34, sex: .female)
        #expect(result.standing == .noComparison)
        #expect(!result.detail.contains("96%"))
        #expect(FunctionalTest.interpret(.pushUps, value: 45, age: 70, sex: .female).ageNote == nil)
    }

    @Test func pushUpsCarryAnAgeNoteOutsideTheFirefighterCohort() {
        // Yang 2019: men aged 21 to 66.
        #expect(FunctionalTest.pushUps.cohortAges == 21...66)
        #expect(FunctionalTest.interpret(.pushUps, value: 30, age: 34, sex: .male).ageNote == nil)
        #expect(FunctionalTest.interpret(.pushUps, value: 30, age: 66, sex: .male).ageNote == nil)
        let older = FunctionalTest.interpret(.pushUps, value: 30, age: 72, sex: .male)
        #expect(older.ageNote?.contains("21-66") == true)
        #expect(FunctionalTest.interpret(.pushUps, value: 30, age: 19, sex: .male).ageNote != nil)
    }

    @Test(arguments: [
        (10.0, 4), (9.5, 3), (8.5, 3), (8.0, 2), (7.5, 1), (4.5, 1), (4.0, 0), (0.0, 0),
    ])
    func sittingRisingGroups(score: Double, group: Int) {
        #expect(FunctionalTest.sittingRisingGroup(score) == group)
    }

    @Test func sittingRisingInterpretation() {
        let top = FunctionalTest.interpret(.sittingRising, value: 10, age: 55, sex: .male)
        #expect(top.standing == .top)
        #expect(top.ageNote == nil)
        let low = FunctionalTest.interpret(.sittingRising, value: 3, age: 55, sex: .female)
        #expect(low.standing == .low)
        #expect(low.detail.contains("42.1%"))
        let middle = FunctionalTest.interpret(.sittingRising, value: 8, age: 45, sex: .male)
        #expect(middle.standing == .middle)
        #expect(middle.detail.contains("11.1%"))
        // 45 is shown (the doc's "from 45") but below the cohort's 46.
        #expect(middle.ageNote != nil)
    }

    @Test func sittingRisingScore() {
        #expect(FunctionalTest.sittingRisingScore(sitSupports: 0, sitUnsteady: 0, riseSupports: 0, riseUnsteady: 0) == 10)
        #expect(FunctionalTest.sittingRisingScore(sitSupports: 1, sitUnsteady: 1, riseSupports: 2, riseUnsteady: 0) == 6.5)
        // A part never goes below 0.
        #expect(FunctionalTest.sittingRisingScore(sitSupports: 7, sitUnsteady: 0, riseSupports: 0, riseUnsteady: 0) == 5)
    }

    @Test func oneLegStand() {
        #expect(FunctionalTest.interpret(.oneLegStand, value: 1, age: 60, sex: .male).standing == .top)
        let unable = FunctionalTest.interpret(.oneLegStand, value: 0, age: 60, sex: .male)
        #expect(unable.standing == .low)
        #expect(unable.detail.contains("1.84"))
        #expect(FunctionalTest.interpret(.oneLegStand, value: 1, age: 80, sex: .male).ageNote != nil)
    }

    @Test func validation() {
        #expect(FunctionalTest.pushUps.validated(32.4) == 32)
        #expect(FunctionalTest.pushUps.validated(-1) == nil)
        #expect(FunctionalTest.sittingRising.validated(7.3) == 7.5)
        #expect(FunctionalTest.sittingRising.validated(11) == nil)
        #expect(FunctionalTest.oneLegStand.validated(1) == 1)
        #expect(FunctionalTest.oneLegStand.validated(0.5) == nil)
        #expect(FunctionalTest.pushUps.validated(.nan) == nil)
    }

    @Test func yearlyDueAndTrend() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 9))!
        let later = calendar.date(byAdding: .day, value: 364, to: start)!
        let year = calendar.date(byAdding: .day, value: 365, to: start)!
        let results = [
            FunctionalTest.Result(test: .pushUps, date: start, value: 25),
            FunctionalTest.Result(test: .pushUps, date: calendar.date(byAdding: .day, value: -400, to: start)!, value: 20),
            FunctionalTest.Result(test: .sittingRising, date: start, value: 9),
        ]
        #expect(!FunctionalTest.isDue(.pushUps, results: results, now: later, calendar: calendar))
        #expect(FunctionalTest.isDue(.pushUps, results: results, now: year, calendar: calendar))
        #expect(FunctionalTest.isDue(.oneLegStand, results: results, now: start, calendar: calendar))
        #expect(FunctionalTest.change(.pushUps, results: results) == 5)
        #expect(FunctionalTest.change(.sittingRising, results: results) == nil)
    }
}
