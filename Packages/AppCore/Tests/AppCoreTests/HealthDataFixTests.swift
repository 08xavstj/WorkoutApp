import Foundation
import Testing
@testable import AppCore

/// QA round 1: HRV measure choice, night timing, sleep sources, light band,
/// nutrient coverage and dose parsing.
struct HRVSelectionTests {
    let calendar = Calendar(identifier: .gregorian)
    let today = Calendar(identifier: .gregorian).startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    func night(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    func sdnnNights(_ count: Int, value: Double = 50) -> [DailyVitals] {
        (0..<count).map { DailyVitals(date: night($0), hrvMilliseconds: value, restingHeartRate: 55) }
    }

    @Test func oneTypedReadingKeepsSDNN() {
        let selection = DailyVitals.resolvingHRV(sdnnNights(31), overnightRMSSD: [night(0): 70], today: today, calendar: calendar)
        #expect(selection.metric == .sdnn)
        #expect(selection.vitals.count == 31)
        #expect(selection.vitals.allSatisfy { $0.hrvMilliseconds == 50 })
    }

    @Test func oldReadingsOutsideTheWindowDontCount() {
        var old: [Date: Double] = [:]
        for day in 40..<60 { old[night(day)] = 70 }
        let selection = DailyVitals.resolvingHRV(sdnnNights(31), overnightRMSSD: old, today: today, calendar: calendar)
        #expect(selection.metric == .sdnn)
        #expect(selection.rmssdNights == 0)
    }

    @Test func rmssdTakesOverAtFourteenNightsAndFillsGapsFromSDNN() {
        var rmssd: [Date: Double] = [:]
        for day in 1...14 { rmssd[night(day)] = 40 } // ratio 40/50 = 0.8
        let thirteen = DailyVitals.resolvingHRV(sdnnNights(31), overnightRMSSD: rmssd.filter { $0.key != night(14) },
                                                today: today, calendar: calendar)
        #expect(thirteen.metric == .sdnn)

        let selection = DailyVitals.resolvingHRV(sdnnNights(31), overnightRMSSD: rmssd, today: today, calendar: calendar)
        #expect(selection.metric == .rmssd)
        // Today has SDNN only: converted with the personal ratio, never blank.
        let todayValue = selection.vitals.first { $0.date == today }?.hrvMilliseconds
        #expect(abs((todayValue ?? 0) - 40) < 0.001)
        #expect(selection.vitals.allSatisfy { $0.hrvMilliseconds != nil })
    }

    @Test func garminOnlyUsesRMSSDRightAway() {
        let health = (0..<10).map { DailyVitals(date: night($0), hrvMilliseconds: nil, restingHeartRate: 52) }
        let selection = DailyVitals.resolvingHRV(health, overnightRMSSD: [night(0): 62, night(1): 58], today: today, calendar: calendar)
        #expect(selection.metric == .rmssd)
        #expect(selection.vitals.first?.hrvMilliseconds == 62)
        #expect(selection.vitals.first?.restingHeartRate == 52)
    }

    @Test func cameraReadingsStayOutOfOvernightBaselines() {
        let selection = DailyVitals.resolvingHRV(sdnnNights(20), overnightRMSSD: [:], morningHRV: [night(0): 90],
                                                 today: today, calendar: calendar)
        #expect(selection.metric == .sdnn)
        #expect(selection.vitals.first?.hrvMilliseconds == 50)

        let noWatch = (0..<5).map { DailyVitals(date: night($0), hrvMilliseconds: nil, restingHeartRate: nil) }
        let cameraOnly = DailyVitals.resolvingHRV(noWatch, overnightRMSSD: [:], morningHRV: [night(0): 90, night(1): 80],
                                                  today: today, calendar: calendar)
        #expect(cameraOnly.metric == .morningRMSSD)
        #expect(cameraOnly.vitals.compactMap(\.hrvMilliseconds) == [90, 80])
    }

    @Test func nothingAtAll() {
        let selection = DailyVitals.resolvingHRV([], overnightRMSSD: [:], calendar: calendar)
        #expect(selection.metric == nil)
        #expect(selection.vitals.isEmpty)
    }
}

struct RecoveryTimingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }
    var midnight: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }
    func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }

    @Test func stillAsleepAfterMidnightIsNotScored() {
        #expect(!RecoveryTiming.nightIsOver(now: at(2), wake: nil, asleepHours: nil, tracksSleep: true, calendar: calendar))
        // A short wake at 1 am isn't the morning.
        #expect(!RecoveryTiming.nightIsOver(now: at(1.5), wake: at(1), asleepHours: 1.5, tracksSleep: true, calendar: calendar))
    }

    @Test func wakingEndsTheNight() {
        #expect(RecoveryTiming.nightIsOver(now: at(7), wake: at(6.5), asleepHours: 7, tracksSleep: true, calendar: calendar))
        #expect(RecoveryTiming.nightIsOver(now: at(3.5), wake: at(3), asleepHours: 4, tracksSleep: true, calendar: calendar))
    }

    @Test func fallbackHours() {
        #expect(RecoveryTiming.nightIsOver(now: at(5), wake: nil, asleepHours: nil, tracksSleep: false, calendar: calendar))
        #expect(!RecoveryTiming.nightIsOver(now: at(9), wake: nil, asleepHours: nil, tracksSleep: true, calendar: calendar))
        #expect(RecoveryTiming.nightIsOver(now: at(12.5), wake: nil, asleepHours: nil, tracksSleep: true, calendar: calendar))
    }
}

struct SleepingHeartRateHysteresisTests {
    let today = Calendar.current.startOfDay(for: .now)

    func sleeping(_ nights: Int) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for day in 0..<nights { result[today.addingTimeInterval(Double(-day) * 86_400)] = 50 }
        return result
    }

    @Test func switchesAtFifteenAndStaysUntilBelowTen() {
        let vitals = [DailyVitals(date: today, hrvMilliseconds: 60, restingHeartRate: 58)]
        #expect(RecoveryCalculator.preferSleepingHeartRate(vitals, sleeping: sleeping(12), minimumNights: 15).source == .healthKit)
        #expect(RecoveryCalculator.preferSleepingHeartRate(vitals, sleeping: sleeping(15), minimumNights: 15).source == .sleeping)
        #expect(RecoveryCalculator.preferSleepingHeartRate(vitals, sleeping: sleeping(12), minimumNights: 15, current: .sleeping).source == .sleeping)
        #expect(RecoveryCalculator.preferSleepingHeartRate(vitals, sleeping: sleeping(10), minimumNights: 15, current: .sleeping).source == .sleeping)
        #expect(RecoveryCalculator.preferSleepingHeartRate(vitals, sleeping: sleeping(9), minimumNights: 15, current: .sleeping).source == .healthKit)
    }
}

struct SleepOnlyRecoveryTests {
    @Test func noHRVOrHeartRateIsLabelledSleepOnly() throws {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let history = (1...20).map { DailyVitals(date: today.addingTimeInterval(Double(-$0) * 86_400), hrvMilliseconds: nil, restingHeartRate: nil) }
        let result = try #require(RecoveryCalculator().score(
            today: DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: nil),
            history: history, sleepScore: 80
        ))
        #expect(result.isSleepOnly)
        #expect(!result.isCalibrated)
        #expect(result.contributors.contains { $0.id == "sleepOnly" })

        let withHRV = try #require(RecoveryCalculator().score(
            today: DailyVitals(date: today, hrvMilliseconds: 60, restingHeartRate: nil),
            history: history, sleepScore: 80
        ))
        #expect(!withHRV.isSleepOnly)
    }
}

struct SleepSourceTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

    @Test func awakeningsSeenByTwoTrackersCountOnce() throws {
        let watch: [SleepSample] = [
            SleepSample(stage: .core, start: at(0), end: at(3), source: "Watch"),
            SleepSample(stage: .awake, start: at(3), end: at(3.2), source: "Watch"),
            SleepSample(stage: .deep, start: at(3.2), end: at(4.5), source: "Watch"),
            SleepSample(stage: .awake, start: at(4.5), end: at(4.7), source: "Watch"),
            SleepSample(stage: .rem, start: at(4.7), end: at(7), source: "Watch"),
        ]
        let ring: [SleepSample] = [
            SleepSample(stage: .core, start: at(0), end: at(3.05), source: "Ring"),
            SleepSample(stage: .awake, start: at(3.05), end: at(3.25), source: "Ring"),
            SleepSample(stage: .core, start: at(3.25), end: at(4.5), source: "Ring"),
            SleepSample(stage: .awake, start: at(4.5), end: at(4.7), source: "Ring"),
            SleepSample(stage: .core, start: at(4.7), end: at(6), source: "Ring"),
        ]
        let single = try #require(SleepCalculator().score(samples: watch))
        let both = try #require(SleepCalculator().score(samples: watch + ring))
        #expect(single.interruptions == 2)
        #expect(both.interruptions == 2)
        // Stages come from the watch (more staged time), not a union of both.
        #expect(abs(both.deep - single.deep) < 1)
        #expect(abs(both.core - single.core) < 1)
        #expect(abs(both.rem - single.rem) < 1)
    }
}

struct LightBandTests {
    @Test func liftingHeartRateIsLightNotAZone() {
        let profile = HeartRateProfile(age: 40, sex: .male, restingHeartRate: 60, maxHeartRateOverride: 180)
        #expect(profile.zone(for: 110) == nil)
        #expect(profile.isLight(110))
        #expect(!profile.isLight(90)) // 25% of reserve
        #expect(!profile.isLight(120)) // 50%: zone 1
        #expect(profile.zone(for: 120) == 1)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<31).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: 110) }
        #expect(abs(profile.lightMinutes(samples) - 30) < 0.001)
        #expect(abs(profile.heartRate(atReserve: 0.3) - 96) < 0.001)
    }
}

struct NutrientCoverageAndDoseTests {
    @Test func patchyNutrientIsNotTracked() {
        #expect(NutrientCoverage.average([100, 100, 100], loggedDays: 7) == nil)
        #expect(NutrientCoverage.average([100, 100, 100, 100, 100, 100], loggedDays: 7) == 100)
        #expect(NutrientCoverage.average([], loggedDays: 7) == nil)
    }

    @Test func creatineDoseIsReadInGrams() {
        #expect(DoseText.grams("20 g") == 20)
        #expect(DoseText.grams("5g") == 5)
        #expect(DoseText.grams("120 mg") == 0.12)
        #expect(DoseText.grams("4 x 5 g") == 20)
        #expect(DoseText.grams("one scoop") == nil)
        #expect(DoseText.isCreatineLoading("20 g"))
        #expect(!DoseText.isCreatineLoading("120 mg"))
        #expect(!DoseText.isCreatineLoading("5 g"))
        #expect(!DoseText.isCreatineLoading(""))
    }
}

struct AsleepStartTests {
    @Test func asleepStartIgnoresInBedTime() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }
        let result = try #require(SleepCalculator().score(samples: [
            SleepSample(stage: .inBed, start: at(-0.5), end: at(8.2)),
            SleepSample(stage: .core, start: at(0), end: at(8)),
        ]))
        #expect(result.bedtime == at(-0.5))
        #expect(result.asleepStart == at(0))
        #expect(result.asleepEnd == at(8))
    }
}
