import Foundation
import Testing
@testable import AppCore

struct RecoveryCalculatorTests {
    let calculator = RecoveryCalculator()
    let today = Date(timeIntervalSince1970: 1_800_000_000)

    /// 14 nights alternating around HRV 60 ms and RHR 55 bpm.
    var history: [DailyVitals] {
        (1...14).map { day in
            let wobble = day.isMultiple(of: 2) ? 1.0 : -1.0
            return DailyVitals(
                date: today.addingTimeInterval(Double(-day) * 86_400),
                hrvMilliseconds: 60 + 5 * wobble,
                restingHeartRate: 55 + wobble
            )
        }
    }

    @Test func averageNightIsModerate() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 60, restingHeartRate: 55),
            history: history,
            sleepScore: 75
        ))
        #expect(result.status == .moderate)
        #expect(result.isCalibrated)
    }

    /// One great night with a 7-day HRV average still inside the normal range
    /// stays in the moderate band (the trend sets the band; the night moves
    /// the number within it).
    @Test func oneGreatNightWithinNormalTrendStaysModerate() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 75, restingHeartRate: 52),
            history: history,
            sleepScore: 90
        ))
        #expect(result.hrvTrend?.status == .within)
        #expect(result.bandFollowsTrend)
        #expect(result.status == .moderate)
        #expect(result.score >= 55)
        #expect(result.score <= RecoveryCalculator.moderateBand.upperBound)
        #expect((result.hrvChangePercent ?? 0) > 20)
    }

    @Test func oneBadNightWithinNormalTrendIsLowModerate() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 45, restingHeartRate: 60),
            history: history,
            sleepScore: 55
        ))
        #expect(result.hrvTrend?.status == .within)
        #expect(result.status == .moderate)
        #expect(result.score <= 45)
        #expect(result.score >= RecoveryCalculator.moderateBand.lowerBound)
    }

    @Test func weekOfLowHRVIsBelowNormalRangeAndAnEasyDay() throws {
        let lowWeek = (1...6).map { day in
            DailyVitals(date: today.addingTimeInterval(Double(-day) * 86_400), hrvMilliseconds: 48, restingHeartRate: 56)
        }
        let older = history.map { DailyVitals(date: $0.date.addingTimeInterval(-7 * 86_400), hrvMilliseconds: $0.hrvMilliseconds, restingHeartRate: $0.restingHeartRate) }
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 50, restingHeartRate: 56),
            history: lowWeek + older,
            sleepScore: 75
        ))
        let trend = try #require(result.hrvTrend)
        #expect(trend.status == .below)
        #expect(trend.nights == 7)
        #expect(result.status == .low)
        #expect(result.score <= RecoveryCalculator.lowBand.upperBound)
        #expect(result.status.label == "Easy day")
    }

    /// A week above the normal range is "high" only when resting heart rate
    /// and sleep agree.
    @Test func weekAboveNormalRangeIsHighUnlessRHROrSleepDisagree() throws {
        let highWeek = (1...6).map { day in
            DailyVitals(date: today.addingTimeInterval(Double(-day) * 86_400), hrvMilliseconds: 75, restingHeartRate: 54)
        }
        let older = history.map { DailyVitals(date: $0.date.addingTimeInterval(-7 * 86_400), hrvMilliseconds: $0.hrvMilliseconds, restingHeartRate: $0.restingHeartRate) }
        let high = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 76, restingHeartRate: 54),
            history: highWeek + older,
            sleepScore: 80
        ))
        #expect(high.hrvTrend?.status == .above)
        #expect(high.status == .high)
        #expect(high.score >= RecoveryCalculator.highBand.lowerBound)

        let raisedRHR = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 76, restingHeartRate: 60),
            history: highWeek + older,
            sleepScore: 80
        ))
        #expect(raisedRHR.hrvTrend?.status == .above)
        #expect(raisedRHR.status == .moderate)

        let badSleep = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 76, restingHeartRate: 54),
            history: highWeek + older,
            sleepScore: 50
        ))
        #expect(badSleep.status == .moderate)
    }

    @Test func scoresScaleIntoTheirBand() {
        #expect(RecoveryCalculator.scale(1, into: RecoveryCalculator.moderateBand) == 34)
        #expect(RecoveryCalculator.scale(99, into: RecoveryCalculator.moderateBand) == 66)
        #expect(RecoveryCalculator.scale(99, into: RecoveryCalculator.lowBand) == 33)
        #expect(RecoveryCalculator.scale(1, into: RecoveryCalculator.highBand) == 67)
        #expect(RecoveryCalculator.status(for: 33) == .low)
        #expect(RecoveryCalculator.status(for: 34) == .moderate)
        #expect(RecoveryCalculator.status(for: 67) == .high)
    }

    /// Without an HRV trend (no HRV at all) the score alone sets the band, as before.
    @Test func withoutHRVTheScoreSetsTheBand() throws {
        let noHRV = history.map { DailyVitals(date: $0.date, hrvMilliseconds: nil, restingHeartRate: $0.restingHeartRate) }
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: 52),
            history: noHRV,
            sleepScore: 90
        ))
        #expect(result.hrvTrend == nil)
        #expect(!result.bandFollowsTrend)
        #expect(result.status == .high)
    }

    @Test func sleepIsComparedWithYourOwnBaseline() throws {
        let tonight = DailyVitals(date: today, hrvMilliseconds: 60, restingHeartRate: 55)
        let population = try #require(calculator.score(today: tonight, history: history, sleepScore: 75))
        #expect(population.sleepBaselineNights == 0)
        #expect(population.contributors.first { $0.id == "sleep" }?.effect == .neutral)

        // 75 is a great night for someone who usually scores 60.
        let own = try #require(calculator.score(today: tonight, history: history, sleepScore: 75,
                                                sleepScoreHistory: Array(repeating: 60, count: 30)))
        #expect(own.sleepBaselineNights == 30)
        #expect(own.contributors.first { $0.id == "sleep" }?.effect == .raises)
        #expect(own.score > population.score)

        // Fewer than 14 nights: still the population anchor.
        let early = try #require(calculator.score(today: tonight, history: history, sleepScore: 75,
                                                  sleepScoreHistory: Array(repeating: 60, count: 10)))
        #expect(early.sleepBaselineNights == 0)
        #expect(early.score == population.score)
    }

    @Test func sleepingHeartRateReplacesHealthKitOnlyWithEnoughNights() throws {
        var sleeping: [Date: Double] = [:]
        for day in 0...14 {
            sleeping[today.addingTimeInterval(Double(-day) * 86_400)] = 50
        }
        let swapped = RecoveryCalculator.preferSleepingHeartRate(history, sleeping: sleeping, minimumNights: 15)
        #expect(swapped.source == .sleeping)
        #expect(swapped.vitals.count == 15)
        #expect(swapped.vitals.allSatisfy { $0.restingHeartRate == 50 })
        #expect(swapped.vitals.first.map { Calendar.current.isDate($0.date, inSameDayAs: today) } == true)
        // HRV is untouched.
        #expect(swapped.vitals.compactMap(\.hrvMilliseconds).count == 14)

        var fewNights: [Date: Double] = [:]
        for day in 0..<5 {
            fewNights[today.addingTimeInterval(Double(-day) * 86_400)] = 50
        }
        let few = RecoveryCalculator.preferSleepingHeartRate(history, sleeping: fewNights, minimumNights: 15)
        #expect(few.source == .healthKit)
        #expect(few.vitals == history)

        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 60, restingHeartRate: 53),
            history: Array(swapped.vitals.dropFirst()),
            sleepScore: nil,
            restingHeartRateSource: swapped.source
        ))
        #expect(result.restingHeartRateSource == .sleeping)
        #expect(result.contributors.first { $0.id == "rhr" }?.name == "Sleeping heart rate")
    }

    @Test func notCalibratedWithoutHistory() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 60, restingHeartRate: 55),
            history: Array(history.prefix(2)),
            sleepScore: 80
        ))
        #expect(!result.isCalibrated)
        #expect(result.hrvChangePercent == nil)
    }

    @Test func nothingToScore() {
        let result = calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: nil),
            history: [],
            sleepScore: nil
        )
        #expect(result == nil)
    }
}

struct SleepCalculatorTests {
    let calculator = SleepCalculator()
    let bedtime = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ hours: Double) -> Date { bedtime.addingTimeInterval(hours * 3600) }

    @Test func goodNightScoresHigh() throws {
        let samples = [
            SleepSample(stage: .core, start: at(0), end: at(2)),
            SleepSample(stage: .deep, start: at(2), end: at(3.5)),
            SleepSample(stage: .rem, start: at(3.5), end: at(5.5)),
            SleepSample(stage: .core, start: at(5.5), end: at(8))
        ]
        let result = try #require(calculator.score(samples: samples))
        #expect(result.score >= 90)
        #expect(result.asleep == 8 * 3600)
        #expect(result.interruptions == 0)
    }

    @Test func afternoonNapIsNotPartOfTheNight() throws {
        let night = [
            SleepSample(stage: .core, start: at(0), end: at(4)),
            SleepSample(stage: .deep, start: at(4), end: at(5)),
            SleepSample(stage: .core, start: at(5), end: at(8)),
        ]
        let nap = SleepSample(stage: .core, start: at(14), end: at(14.7))
        let alone = try #require(calculator.score(samples: night))
        let withNap = try #require(calculator.score(samples: night + [nap]))
        #expect(withNap.asleep == 8 * 3600)
        #expect(withNap.wakeTime == at(8))
        #expect(withNap.score == alone.score)
    }

    @Test func sessionsSplitOnLongGaps() {
        let intervals = [
            DateInterval(start: at(0), end: at(3)),
            DateInterval(start: at(3.5), end: at(7)),
            DateInterval(start: at(2), end: at(3.2)), // overlapping second source
            DateInterval(start: at(13), end: at(14)),
        ]
        let sessions = SleepSessions.sessions(intervals)
        #expect(sessions.count == 2)
        #expect(abs((SleepSessions.main(intervals)?.asleep ?? 0) - 6.7 * 3600) < 1)
        #expect(SleepSessions.main(intervals)?.end == at(7))
    }

    @Test func shortBrokenNightScoresLow() throws {
        let samples = [
            SleepSample(stage: .core, start: at(0), end: at(1.5)),
            SleepSample(stage: .awake, start: at(1.5), end: at(2.5)),
            SleepSample(stage: .core, start: at(2.5), end: at(4)),
            SleepSample(stage: .awake, start: at(4), end: at(4.5)),
            SleepSample(stage: .core, start: at(4.5), end: at(5))
        ]
        let result = try #require(calculator.score(samples: samples))
        #expect(result.score < 60)
        #expect(result.interruptions == 2)
    }

    @Test func overlappingSourcesAreNotDoubleCounted() throws {
        let watch = SleepSample(stage: .core, start: at(0), end: at(7))
        let phone = SleepSample(stage: .unspecified, start: at(0), end: at(7))
        let result = try #require(calculator.score(samples: [watch, phone, watch]))
        #expect(result.asleep == 7 * 3600)
    }

    @Test func sleepNeedIsNotTiedToStrain() {
        #expect(calculator.sleepNeed(previousDayStrain: 86) == 8 * 3600)
        #expect(calculator.sleepNeed(previousDayStrain: nil) == 8 * 3600)
    }

    @Test func efficiencyGetsFullMarksFrom85Percent() throws {
        // 7 h asleep in 8 h in bed (87.5%) scores the same as 7 h with no wake time.
        let solid = [SleepSample(stage: .core, start: at(0), end: at(7))]
        let withWake = [
            SleepSample(stage: .core, start: at(0), end: at(3.5)),
            SleepSample(stage: .awake, start: at(3.5), end: at(4)),
            SleepSample(stage: .core, start: at(4), end: at(7.5)),
            SleepSample(stage: .inBed, start: at(0), end: at(8)),
        ]
        let a = try #require(calculator.score(samples: solid))
        let b = try #require(calculator.score(samples: withWake))
        // b loses only the interruption, not efficiency.
        #expect(a.score - b.score <= 2)
    }

    @Test func regularScheduleScoresHigherThanIrregular() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let base = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 23))!
        let regular = (0..<7).map { day in
            let bed = base.addingTimeInterval(Double(day) * 86_400 + Double(day % 2) * 600)
            return SleepConsistency.Night(bedtime: bed, wake: bed.addingTimeInterval(8 * 3600))
        }
        let irregular = (0..<7).map { day in
            let bed = base.addingTimeInterval(Double(day) * 86_400 + Double(day % 3) * 5400 - 5400)
            return SleepConsistency.Night(bedtime: bed, wake: bed.addingTimeInterval(7 * 3600))
        }
        let good = try #require(SleepConsistency.score(regular, calendar: calendar))
        let bad = try #require(SleepConsistency.score(irregular, calendar: calendar))
        #expect(good == 100)
        #expect(bad < 50)
        #expect(SleepConsistency.score(Array(regular.prefix(3)), calendar: calendar) == nil)
    }

    @Test func lateWakeTimesNearNoonDontWrap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let base = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 4))!
        // Asleep 4:00, waking at 11:50 or 12:10 on alternate days.
        let nights = (0..<6).map { day in
            let bed = base.addingTimeInterval(Double(day) * 86_400)
            return SleepConsistency.Night(bedtime: bed, wake: bed.addingTimeInterval(7 * 3600 + 50 * 60 + Double(day % 2) * 1200))
        }
        let spread = try #require(SleepConsistency.spreadMinutes(nights, calendar: calendar))
        #expect(spread < 10)
        #expect(SleepConsistency.score(nights, calendar: calendar) == 100)
    }

    @Test func consistencyCountsInTheSleepScore() throws {
        let samples = [SleepSample(stage: .core, start: at(0), end: at(8))]
        let steady = try #require(calculator.score(samples: samples, consistency: 100))
        let erratic = try #require(calculator.score(samples: samples, consistency: 0))
        #expect(steady.score - erratic.score == 15)
    }

    @Test func noSleepReturnsNil() {
        #expect(calculator.score(samples: []) == nil)
        #expect(calculator.score(samples: [SleepSample(stage: .inBed, start: at(0), end: at(8))]) == nil)
    }

    /// SRI 85+ is full marks, 50 or under none (Windred 2024: median 81).
    @Test func regularityMapsTheRealWorldRange() {
        #expect(SleepCalculator.regularityScore(sri: 100) == 1)
        #expect(SleepCalculator.regularityScore(sri: 85) == 1)
        #expect(abs(SleepCalculator.regularityScore(sri: 67) - 17.0 / 35) < 0.001)
        #expect(SleepCalculator.regularityScore(sri: 50) == 0)
        #expect(SleepCalculator.regularityScore(sri: 30) == 0)
    }

    /// 0-1 awakenings good, 4+ poor (Ohayon 2017).
    @Test func interruptionsFollowTheNSFIndicator() {
        #expect(SleepCalculator.interruptionScore(0) == 1)
        #expect(SleepCalculator.interruptionScore(1) == 1)
        #expect(SleepCalculator.interruptionScore(2) == 0.5)
        #expect(SleepCalculator.interruptionScore(3) == 0.5)
        #expect(SleepCalculator.interruptionScore(4) == 0)
        #expect(SleepCalculator.interruptionScore(7) == 0)
    }

    @Test func efficiencyIsZeroAt70Percent() throws {
        // 5.6 h asleep: 70% of 8 h in bed earns nothing, 80% of 7 h earns two thirds.
        let seventy = [SleepSample(stage: .core, start: at(0), end: at(5.6)), SleepSample(stage: .inBed, start: at(0), end: at(8))]
        let eighty = [SleepSample(stage: .core, start: at(0), end: at(5.6)), SleepSample(stage: .inBed, start: at(0), end: at(7))]
        let a = try #require(calculator.score(samples: seventy))
        let b = try #require(calculator.score(samples: eighty))
        #expect(abs(a.efficiency - 0.7) < 0.001)
        #expect(b.score - a.score >= 15)
    }

    @Test func restorativeTargetFallsWithAge() throws {
        #expect(SleepCalculator.restorativeShareTarget(age: 30) == 0.40)
        #expect(SleepCalculator.restorativeShareTarget(age: 45) == 0.35)
        #expect(SleepCalculator.restorativeShareTarget(age: 65) == 0.30)
        // Deep + REM at 31% of the night: full marks at 65, not at 30.
        let samples = [
            SleepSample(stage: .core, start: at(0), end: at(5.5)),
            SleepSample(stage: .deep, start: at(5.5), end: at(6.5)),
            SleepSample(stage: .rem, start: at(6.5), end: at(8)),
        ]
        var young = SleepCalculator()
        young.age = 30
        var older = SleepCalculator()
        older.age = 65
        let a = try #require(young.score(samples: samples))
        let b = try #require(older.score(samples: samples))
        #expect(b.score > a.score)
        let unknownAge = try #require(calculator.score(samples: samples))
        #expect(unknownAge.score == a.score)
    }
}

struct ManualHRVTests {
    let calendar = Calendar(identifier: .gregorian)
    let morning = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func manualHRVFillsMissingNights() {
        let health = [DailyVitals(date: morning, hrvMilliseconds: nil, restingHeartRate: 52)]
        let merged = DailyVitals.merging(health, manualHRV: [morning: 48], calendar: calendar)
        #expect(merged.count == 1)
        #expect(merged[0].hrvMilliseconds == 48)
        #expect(merged[0].restingHeartRate == 52)
    }

    @Test func healthDataWinsOverManualEntry() {
        let health = [DailyVitals(date: morning, hrvMilliseconds: 60, restingHeartRate: 52)]
        let merged = DailyVitals.merging(health, manualHRV: [morning: 48], calendar: calendar)
        #expect(merged[0].hrvMilliseconds == 60)
    }

    @Test func manualOnlyDropsHealthHRV() {
        let earlier = morning.addingTimeInterval(-86_400)
        let health = [
            DailyVitals(date: morning, hrvMilliseconds: 60, restingHeartRate: 52),
            DailyVitals(date: earlier, hrvMilliseconds: 62, restingHeartRate: 53),
        ]
        let merged = DailyVitals.merging(health, manualHRV: [morning: 48], manualOnlyHRV: true, calendar: calendar)
        #expect(merged.first { $0.date == morning }?.hrvMilliseconds == 48)
        #expect(merged.first { $0.date == earlier }?.hrvMilliseconds == nil)
        #expect(merged.first { $0.date == earlier }?.restingHeartRate == 53)
    }

    @Test func manualOnlyNightsAreAddedNewestFirst() {
        let earlier = morning.addingTimeInterval(-86_400)
        let merged = DailyVitals.merging([], manualHRV: [earlier: 50, morning: 55], calendar: calendar)
        #expect(merged.map(\.hrvMilliseconds) == [55, 50])
        #expect(merged[0].restingHeartRate == nil)
    }
}
