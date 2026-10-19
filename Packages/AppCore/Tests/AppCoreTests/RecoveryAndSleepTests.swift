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

    @Test func highHRVAndLowRestingHeartRateIsHigh() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 75, restingHeartRate: 52),
            history: history,
            sleepScore: 90
        ))
        #expect(result.status == .high)
        #expect((result.hrvChangePercent ?? 0) > 20)
    }

    @Test func lowHRVAndHighRestingHeartRateIsLow() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 45, restingHeartRate: 60),
            history: history,
            sleepScore: 55
        ))
        #expect(result.status == .low)
    }

    @Test func weekOfLowHRVIsBelowNormalRange() throws {
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

    @Test func hardDayRaisesSleepNeed() {
        #expect(calculator.sleepNeed(previousDayStrain: 86) > calculator.sleepNeed(previousDayStrain: 38))
        #expect(calculator.sleepNeed(previousDayStrain: nil) == 8 * 3600)
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
