import Foundation
import Testing
@testable import AppCore

struct BloodTestScheduleTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    var now: Date { date(2026, 11, 17) }

    func result(_ marker: String, _ value: Double, _ unit: String, _ on: Date, _ status: LabMarkers.Status? = .inRange) -> BloodTestSchedule.Result {
        BloodTestSchedule.Result(markerID: marker, value: value, unit: unit, date: on, status: status)
    }

    func schedule(_ results: [BloodTestSchedule.Result], typed: [BloodTestSchedule.Check: Date] = [:], age: Int, at: Date? = nil)
        -> [BloodTestSchedule.Check: BloodTestSchedule.Due] {
        let list = BloodTestSchedule.schedule(results: results, testedOn: typed, age: age, now: at ?? now, calendar: calendar)
        return Dictionary(uniqueKeysWithValues: list.map { ($0.check, $0) })
    }

    // MARK: Ages on the boundaries

    @Test func nothingOnFileAtThirtyMeansLipidsAndLpaNowGlucoseNotYet() {
        let due = schedule([], age: 30)
        #expect(due[.lipids]?.isDue == true)
        #expect(due[.lipids]?.askForApoB == true)
        #expect(due[.lpa]?.isDue == true)
        #expect(due[.glucose] == nil)
        #expect(BloodTestSchedule.summary(Array(due.values).sorted { $0.check.rawValue < $1.check.rawValue }) != nil)
    }

    @Test func glucoseStartsAtExactlyThirtyFive() {
        #expect(schedule([], age: 34)[.glucose] == nil)
        #expect(schedule([], age: 35)[.glucose]?.isDue == true)
    }

    @Test func lipidsStartAtTwentyAndLpaAtEighteen() {
        let seventeen = schedule([], age: 17)
        #expect(seventeen.isEmpty)
        let eighteen = schedule([], age: 18)
        #expect(eighteen[.lpa]?.isDue == true)
        #expect(eighteen[.lipids] == nil)
        #expect(schedule([], age: 19)[.lipids] == nil)
        #expect(schedule([], age: 20)[.lipids]?.isDue == true)
    }

    // MARK: Intervals

    @Test func normalLipidPanelIsDueFiveYearsLaterToTheDay() {
        let tested = date(2022, 3, 10)
        let results = [result("ldl", 95, "mg/dL", tested), result("hdl", 55, "mg/dL", tested), result("apoB", 80, "mg/dL", tested)]
        let lipids = schedule(results, age: 30)[.lipids]
        #expect(lipids?.dueDate == calendar.startOfDay(for: date(2027, 3, 10)))
        #expect(lipids?.isDue == false)
        #expect(lipids?.askForApoB == false)
        #expect(lipids?.line == "Up to date.")
        // The day before and the day itself.
        #expect(schedule(results, age: 30, at: date(2027, 3, 9))[.lipids]?.isDue == false)
        #expect(schedule(results, age: 30, at: date(2027, 3, 10, hour: 0))[.lipids]?.isDue == true)
    }

    @Test func raisedLdlShortensTheIntervalToAYear() {
        let tested = date(2025, 11, 1)
        let results = [result("ldl", 162, "mg/dL", tested, .high), result("hdl", 50, "mg/dL", tested)]
        let lipids = schedule(results, age: 30)[.lipids]
        #expect(lipids?.raised == true)
        #expect(lipids?.dueDate == calendar.startOfDay(for: date(2026, 11, 1)))
        #expect(lipids?.isDue == true)
        #expect(lipids?.line.contains("outside the range") == true)
        #expect(lipids?.line.contains("ApoB") == true)
    }

    @Test func lowHdlCountsAsRaisedButLowLdlDoesNot() {
        let tested = date(2026, 6, 1)
        #expect(schedule([result("hdl", 35, "mg/dL", tested, .low)], age: 30)[.lipids]?.raised == true)
        #expect(schedule([result("ldl", 50, "mg/dL", tested, .low)], age: 30)[.lipids]?.raised == false)
    }

    @Test func onlyTheNewestPanelDecidesTheInterval() {
        let results = [
            result("ldl", 165, "mg/dL", date(2023, 1, 5), .high),
            result("ldl", 98, "mg/dL", date(2025, 2, 5)),
        ]
        let lipids = schedule(results, age: 30)[.lipids]
        #expect(lipids?.raised == false)
        #expect(lipids?.dueDate == calendar.startOfDay(for: date(2030, 2, 5)))
    }

    @Test func prediabetesHbA1cMeansYearlyEvenBeforeThirtyFive() {
        let tested = date(2026, 2, 1)
        for (value, unit) in [(5.7, "%"), (39.0, "mmol/mol")] {
            let glucose = schedule([result("hba1c", value, unit, tested)], age: 31)[.glucose]
            #expect(glucose?.raised == true, "\(value) \(unit)")
            #expect(glucose?.dueDate == calendar.startOfDay(for: date(2027, 2, 1)))
        }
        // Just under the lines: nothing before 35, every 3 years from 35.
        #expect(schedule([result("hba1c", 5.6, "%", tested)], age: 31)[.glucose] == nil)
        #expect(schedule([result("hba1c", 5.6, "%", tested)], age: 40)[.glucose]?.dueDate == calendar.startOfDay(for: date(2029, 2, 1)))
    }

    @Test func fastingGlucoseLinesFollowTheADA() {
        #expect(BloodTestSchedule.inPrediabetesRange(markerID: "glucose", value: 100, unit: "mg/dL"))
        #expect(!BloodTestSchedule.inPrediabetesRange(markerID: "glucose", value: 99, unit: "mg/dL"))
        #expect(BloodTestSchedule.inPrediabetesRange(markerID: "glucose", value: 5.6, unit: "mmol/L"))
        #expect(!BloodTestSchedule.inPrediabetesRange(markerID: "glucose", value: 5.5, unit: "mmol/L"))
        #expect(!BloodTestSchedule.inPrediabetesRange(markerID: "ldl", value: 200, unit: "mg/dL"))
    }

    // MARK: Lp(a) once

    @Test func lpaIsDoneForGoodOnceAnyResultIsOnFile() {
        let results = [result("lpa", 72, "mg/dL", date(2012, 4, 1), .high)]
        let lpa = schedule(results, age: 30)[.lpa]
        #expect(lpa?.isDue == false)
        #expect(lpa?.dueDate == nil)
        // Decades later, still not due.
        #expect(schedule(results, age: 60, at: date(2045, 1, 1))[.lpa]?.isDue == false)
    }

    @Test func aTypedTestDateWithoutValuesCountsAsTested() {
        let due = schedule([], typed: [.lpa: date(2019, 5, 1), .lipids: date(2024, 5, 1)], age: 30)
        #expect(due[.lpa]?.isDue == false)
        #expect(due[.lipids]?.lastTested == date(2024, 5, 1))
        #expect(due[.lipids]?.dueDate == calendar.startOfDay(for: date(2029, 5, 1)))
    }

    @Test func aNewerTypedDateClearsAnOldRaisedFlag() {
        let results = [result("ldl", 170, "mg/dL", date(2025, 1, 1), .high)]
        let lipids = schedule(results, typed: [.lipids: date(2026, 9, 1)], age: 30)[.lipids]
        #expect(lipids?.raised == false)
        #expect(lipids?.dueDate == calendar.startOfDay(for: date(2031, 9, 1)))
    }

    // MARK: A realistic run of years

    @Test func aDecadeOfTestsFollowsTheRules() {
        // 30: first panel, LDL high → yearly. 31: back in range → 5 years. Lp(a) once at 30.
        var results = [
            result("ldl", 150, "mg/dL", date(2026, 1, 10), .high),
            result("lpa", 20, "mg/dL", date(2026, 1, 10)),
        ]
        var due = schedule(results, age: 30, at: date(2026, 6, 1))
        #expect(due[.lipids]?.dueDate == calendar.startOfDay(for: date(2027, 1, 10)))
        #expect(due[.lpa]?.isDue == false)
        results.append(result("ldl", 118, "mg/dL", date(2027, 1, 20), .inRange))
        due = schedule(results, age: 31, at: date(2027, 2, 1))
        #expect(due[.lipids]?.dueDate == calendar.startOfDay(for: date(2032, 1, 20)))
        #expect(BloodTestSchedule.summary(Array(due.values)) == nil)
        // 35: glucose becomes due with nothing on file.
        due = schedule(results, age: 35, at: date(2031, 3, 1))
        #expect(due[.glucose]?.isDue == true)
        #expect(BloodTestSchedule.summary(BloodTestSchedule.schedule(results: results, age: 35, now: date(2031, 3, 1), calendar: calendar)) == "HbA1c is due")
    }

    @Test func summaryListsEverythingDue() {
        let list = BloodTestSchedule.schedule(results: [], age: 40, now: now, calendar: calendar)
        #expect(BloodTestSchedule.summary(list) == "Cholesterol panel, Lp(a) and HbA1c are due")
    }
}
