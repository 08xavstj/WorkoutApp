import Foundation
import Testing
@testable import AppCore

struct WaistToHeightRatioTests {
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test func ratioAndBands() throws {
        // Ashwell 2012 / Browning 2010: under 0.5 healthy, 0.5-0.6 raised, over 0.6 high; under 0.4 low.
        let ratio = try #require(WaistToHeightRatio.ratio(waistCm: 85, heightCm: 180))
        #expect(abs(ratio - 0.4722) < 0.001)
        #expect(WaistToHeightRatio.category(0.39) == .low)
        #expect(WaistToHeightRatio.category(0.40) == .healthy)
        #expect(WaistToHeightRatio.category(0.499) == .healthy)
        #expect(WaistToHeightRatio.category(0.5) == .raised)
        #expect(WaistToHeightRatio.category(0.6) == .high)
        #expect(WaistToHeightRatio.target == 0.5)
        #expect(WaistToHeightRatio.waistAtTarget(heightCm: 180) == 90)
        #expect(WaistToHeightRatio.ratio(waistCm: 85, heightCm: 0) == nil)
    }

    @Test func adviceFollowsTheGoal() {
        #expect(WaistToHeightRatio.advice(.healthy, goals: Goals(weight: .gain)).contains("bulk"))
        #expect(WaistToHeightRatio.advice(.healthy, goals: Goals(weight: .lose)).contains("stalls"))
        #expect(WaistToHeightRatio.advice(.raised, goals: Goals(weight: .gain)).contains("recomp"))
        #expect(WaistToHeightRatio.advice(.high, goals: nil).contains("doctor"))
    }

    @Test func monthlyCadence() throws {
        let measured = utc.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 9))!
        let due = try #require(WaistToHeightRatio.nextDue(lastMeasured: measured, calendar: utc))
        #expect(due == utc.date(from: DateComponents(year: 2027, month: 2, day: 9))!)
        #expect(!WaistToHeightRatio.isDue(lastMeasured: measured, now: measured.addingTimeInterval(20 * 86_400), calendar: utc))
        #expect(WaistToHeightRatio.isDue(lastMeasured: measured, now: due, calendar: utc))
        #expect(WaistToHeightRatio.isDue(lastMeasured: nil, calendar: utc))
        // Body age treats a waist reading as current for 90 days.
        #expect(WaistToHeightRatio.isFresh(measured, now: measured.addingTimeInterval(90 * 86_400), calendar: utc))
        #expect(!WaistToHeightRatio.isFresh(measured, now: measured.addingTimeInterval(91 * 86_400), calendar: utc))
    }

    @Test func lengthUnits() {
        #expect(abs(LengthUnit.inches.toCentimeters(33) - 83.82) < 0.001)
        #expect(abs(LengthUnit.inches.display(83.82) - 33) < 0.001)
        #expect(LengthUnit.centimeters.toCentimeters(84) == 84)
        #expect(LengthUnit.centimeters.format(84.4) == "84 cm")
        #expect(LengthUnit.inches.format(83.82) == "33 in")
    }
}

struct GripStrengthTests {
    @Test func sarcopeniaCutoffs() {
        // EWGSOP2 (Cruz-Jentoft 2019): under 27 kg men, under 16 kg women.
        #expect(GripStrength.sarcopeniaCutoffKg(sex: .male) == 27)
        #expect(GripStrength.sarcopeniaCutoffKg(sex: .female) == 16)
        #expect(GripStrength.reading(kg: 26, age: 30, sex: .male) == .belowCutoff)
        #expect(GripStrength.reading(kg: 15, age: 30, sex: .female) == .belowCutoff)
    }

    @Test func ageBandsAreTheBohannonRange() {
        // Men in their 20s-40s: about 45-55 kg average (Bohannon 2006, as cited in the report).
        for age in [25, 35, 45] {
            let band = GripStrength.band(age: age, sex: .male)
            #expect(band.mean >= 45 && band.mean <= 55)
        }
        #expect(GripStrength.band(age: 75, sex: .male).mean < GripStrength.band(age: 35, sex: .male).mean)
        #expect(GripStrength.band(age: 35, sex: .female).mean < GripStrength.band(age: 35, sex: .male).mean)
        #expect(GripStrength.reading(kg: 50, age: 30, sex: .male) == .average)
        #expect(GripStrength.reading(kg: 40, age: 30, sex: .male) == .belowAverage)
        #expect(GripStrength.reading(kg: 65, age: 30, sex: .male) == .aboveAverage)
        #expect(GripStrength.reading(kg: 32, age: 30, sex: .female) == .average)
        #expect(GripStrength.advice(.belowCutoff, age: 30, sex: .male).contains("doctor"))
        #expect(GripStrength.advice(.average, age: 30, sex: .male).contains("kg"))
    }

    @Test func twiceAYear() throws {
        let measured = Date(timeIntervalSince1970: 1_800_000_000)
        let due = try #require(GripStrength.nextDue(lastMeasured: measured))
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: measured), to: due).day
        #expect(days == 182)
        #expect(!GripStrength.isDue(lastMeasured: measured, now: measured.addingTimeInterval(100 * 86_400)))
        #expect(GripStrength.isDue(lastMeasured: measured, now: measured.addingTimeInterval(183 * 86_400)))
        #expect(GripStrength.isDue(lastMeasured: nil))
    }
}

struct StopBangTests {
    @Test func eightQuestionsAndBands() {
        #expect(StopBang.questions.count == 8)
        #expect(StopBang.questions.map(\.letter) == ["S", "T", "O", "P", "B", "A", "N", "G"])
        // Chung 2016: 0-2 low, 3-4 intermediate, 5-8 high.
        #expect(StopBang.risk(score: 0) == .low)
        #expect(StopBang.risk(score: 2) == .low)
        #expect(StopBang.risk(score: 3) == .intermediate)
        #expect(StopBang.risk(score: 4) == .intermediate)
        #expect(StopBang.risk(score: 5) == .high)
        #expect(StopBang.risk(score: 8) == .high)
    }

    @Test func scoreCountsYesAnswers() {
        let answers = ["snoring": true, "tired": true, "gender": true, "bmi": false, "unknown": true]
        #expect(StopBang.score(answers) == 3)
        #expect(StopBang.advice(StopBang.risk(score: 3)).contains("sleep study"))
        #expect(StopBang.advice(StopBang.risk(score: 6)).contains("sleep study"))
        #expect(!StopBang.advice(.low).contains("sleep study"))
    }

    @Test func profileFillsInAgeSexAndBMI() {
        let answers = StopBang.profileAnswers(age: 52, sex: .male, bmi: 36)
        #expect(answers["age"] == true)
        #expect(answers["gender"] == true)
        #expect(answers["bmi"] == true)
        let young = StopBang.profileAnswers(age: 30, sex: .female, bmi: nil)
        #expect(young["age"] == false)
        #expect(young["gender"] == false)
        #expect(young["bmi"] == nil)
    }

    @Test func yearlyOrWhenBloodPressureRises() {
        let answered = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(StopBang.isDue(lastAnswered: nil))
        #expect(!StopBang.isDue(lastAnswered: answered, now: answered.addingTimeInterval(200 * 86_400)))
        #expect(StopBang.isDue(lastAnswered: answered, now: answered.addingTimeInterval(366 * 86_400)))
        // Elevated home BP re-asks early unless "pressure" was already a yes.
        #expect(StopBang.isDue(lastAnswered: answered, lastAnswers: ["pressure": false], bloodPressureElevated: true,
                               now: answered.addingTimeInterval(30 * 86_400)))
        #expect(!StopBang.isDue(lastAnswered: answered, lastAnswers: ["pressure": true], bloodPressureElevated: true,
                                now: answered.addingTimeInterval(30 * 86_400)))
    }
}
