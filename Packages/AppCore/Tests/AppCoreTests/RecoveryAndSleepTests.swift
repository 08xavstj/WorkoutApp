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

    /// One great night reads as a great night even though the 7-day HRV
    /// average is still inside the normal range: the trend no longer squeezes
    /// the number into 34-66.
    @Test func oneGreatNightReadsRecovered() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 75, restingHeartRate: 52),
            history: history,
            sleepScore: 90
        ))
        #expect(result.hrvTrend?.status == .within)
        #expect(!result.bandFollowsTrend)
        #expect(result.status == .high)
        #expect(result.score >= RecoveryCalculator.highBand.lowerBound)
        #expect((result.hrvChangePercent ?? 0) > 20)
    }

    /// A clearly bad night is an easy day straight away, without waiting for
    /// the 7-day average to fall.
    @Test func oneBadNightReadsLow() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 45, restingHeartRate: 60),
            history: history,
            sleepScore: 55
        ))
        #expect(result.hrvTrend?.status == .within)
        #expect(result.status == .low)
        #expect(result.score <= RecoveryCalculator.lowBand.upperBound)
    }

    @Test func aUsualNightScoresTheUsualScore() throws {
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 59.8, restingHeartRate: 55),
            history: history,
            sleepScore: 75
        ))
        #expect(abs(result.score - RecoveryCalculator.usualScore) <= 2)
        #expect(RecoveryCalculator.usualScore == 57)
    }

    /// No cliffs: stepping last night's HRV up never lowers the score, and no
    /// 2 ms step moves it more than a few points.
    @Test func theScoreMovesSmoothlyWithLastNight() throws {
        var previous: Int?
        for hrv in stride(from: 40.0, through: 80.0, by: 2.0) {
            let result = try #require(calculator.score(
                today: DailyVitals(date: today, hrvMilliseconds: hrv, restingHeartRate: 55),
                history: history,
                sleepScore: 75
            ))
            if let previous {
                #expect(result.score >= previous, "HRV \(hrv)")
                #expect(result.score - previous <= 8, "HRV \(hrv)")
            }
            previous = result.score
        }
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
        #expect(result.bandFollowsTrend)
        #expect(result.score <= RecoveryCalculator.moderateBand.upperBound)
        #expect(result.status.label == "Easy day")
    }

    /// A week above the normal range reads high; a raised heart rate or a bad
    /// night pulls the number down by its weight, with no special rule.
    @Test func weekAboveNormalRangeReadsHighAndOtherSignalsStillCount() throws {
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
        #expect(raisedRHR.score < high.score)

        let badSleep = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 76, restingHeartRate: 54),
            history: highWeek + older,
            sleepScore: 50
        ))
        #expect(badSleep.score < high.score)
    }

    /// The trial rule: a 7-day average below your normal range is an easy
    /// day even after one very good night, and the number can't read "Recovered".
    @Test func trendBelowNormalIsAnEasyDayEvenAfterAGoodNight() throws {
        let lowWeek = (1...6).map { day in
            DailyVitals(date: today.addingTimeInterval(Double(-day) * 86_400), hrvMilliseconds: 46, restingHeartRate: 55)
        }
        let older = history.map { DailyVitals(date: $0.date.addingTimeInterval(-7 * 86_400), hrvMilliseconds: $0.hrvMilliseconds, restingHeartRate: $0.restingHeartRate) }
        let result = try #require(calculator.score(
            today: DailyVitals(date: today, hrvMilliseconds: 70, restingHeartRate: 50),
            history: lowWeek + older,
            sleepScore: 95
        ))
        #expect(result.hrvTrend?.status == .below)
        #expect(result.bandFollowsTrend)
        #expect(result.status == .low)
        #expect(result.score <= RecoveryCalculator.moderateBand.upperBound)
    }

    /// A simulated year of nights (HRV, heart rate and sleep moving partly
    /// together, with week-long drifts): the score uses the whole scale, most
    /// days are normal, and "Recovered" isn't a rarity. Before November 2026
    /// 78% of these days fell in 34-66 and 7% read "Recovered".
    @Test func aYearOfNightsUsesTheWholeScale() throws {
        var generator = SimFixtures.SplitMix(state: 42)
        func normal() -> Double {
            let first = Double.random(in: 1e-9...1, using: &generator)
            let second = Double.random(in: 0...1, using: &generator)
            return (-2 * log(first)).squareRoot() * cos(2 * .pi * second)
        }
        var vitals: [DailyVitals] = []
        var sleeps: [Int] = []
        var scores: [Int] = []
        var statuses: [RecoveryCalculator.Status: Int] = [:]
        var drift = 0.0
        for day in 0..<400 {
            drift = 0.6 * drift + 0.48 * normal()
            let night = normal()
            let hrv = exp(log(48) + 0.18 * (0.5 * drift + 0.6 * night + 0.6 * normal()))
            let heartRate = 54 - 2.5 * (0.5 * drift + 0.5 * night + 0.7 * normal())
            let sleep = Int(min(100, max(30, 78 + 9 * (0.3 * drift + 0.5 * night + 0.8 * normal()))))
            let tonight = DailyVitals(date: today.addingTimeInterval(Double(day) * 86_400), hrvMilliseconds: hrv, restingHeartRate: heartRate)
            if day >= 40 {
                let result = try #require(calculator.score(today: tonight, history: vitals, sleepScore: sleep, sleepScoreHistory: sleeps))
                scores.append(result.score)
                statuses[result.status, default: 0] += 1
            }
            vitals.append(tonight)
            sleeps.append(sleep)
        }
        let sorted = scores.sorted()
        let total = Double(scores.count)
        let median = sorted[sorted.count / 2]
        #expect((50...64).contains(median), "median \(median)")
        #expect(sorted[sorted.count / 20] < 40, "5th percentile \(sorted[sorted.count / 20])")
        #expect(sorted[sorted.count * 19 / 20] > 75, "95th percentile \(sorted[sorted.count * 19 / 20])")
        let share = statuses.mapValues { Double($0) / total }
        #expect((0.40...0.65).contains(share[.moderate] ?? 0), "normal \(share[.moderate] ?? 0)")
        #expect((0.20...0.40).contains(share[.high] ?? 0), "recovered \(share[.high] ?? 0)")
        #expect((0.08...0.25).contains(share[.low] ?? 0), "easy \(share[.low] ?? 0)")
    }

    @Test func howItWorksNamesTheWeightsAndTheScale() {
        let text = calculator.howItWorks.joined(separator: " ")
        #expect(text.contains("35%") && text.contains("20%") && text.contains("25%"))
        #expect(text.contains("about 57"))
        #expect(text.contains("Under 34") && text.contains("67 or more"))
    }

    @Test func bandCutOffs() {
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

    /// A few points off your usual is normal, not "lowering" (round-4 bug:
    /// 97 after a usual 99 read as sleep pulling recovery down).
    @Test func smallSleepChangesAreNeutral() throws {
        let tonight = DailyVitals(date: today, hrvMilliseconds: 60, restingHeartRate: 55)
        let usual = Array(repeating: 99, count: 30)
        let slight = try #require(calculator.score(today: tonight, history: history, sleepScore: 97,
                                                   sleepScoreHistory: usual))
        let sleep = try #require(slight.contributors.first { $0.id == "sleep" })
        #expect(sleep.effect == .neutral)
        #expect(sleep.note == RecoveryCalculator.withinNormalNote)

        let clear = try #require(calculator.score(today: tonight, history: history, sleepScore: 85,
                                                  sleepScoreHistory: usual))
        #expect(clear.contributors.first { $0.id == "sleep" }?.effect == .lowers)
        #expect(RecoveryCalculator.sleepEffect(change: -7.9, z: -2) == .neutral)
        #expect(RecoveryCalculator.sleepEffect(change: 8, z: 1) == .raises)
    }

    @Test func detailsUseMinusSignsAndUnits() throws {
        let tonight = DailyVitals(date: today, hrvMilliseconds: 57, restingHeartRate: 56)
        let result = try #require(calculator.score(today: tonight, history: history, sleepScore: nil))
        let hrv = try #require(result.contributors.first { $0.id == "hrv" })
        #expect(hrv.detail.contains("\u{2212}"))
        #expect(!hrv.detail.contains("-"))
        let rhr = try #require(result.contributors.first { $0.id == "rhr" })
        #expect(rhr.detail.contains("bpm vs your usual"))
        #expect(rhr.detail.hasSuffix(" bpm"))
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

    @Test func awakeBeforeFallingAsleepIsNotAWakeUp() throws {
        let night = [
            SleepSample(stage: .core, start: at(0), end: at(3)),
            SleepSample(stage: .awake, start: at(3), end: at(3.25)),
            SleepSample(stage: .core, start: at(3.25), end: at(7.5)),
        ]
        // 20 minutes lying awake before sleep and 10 after the final wake.
        let edges = [
            SleepSample(stage: .awake, start: at(-1.0 / 3), end: at(0)),
            SleepSample(stage: .awake, start: at(7.5), end: at(7.5 + 1.0 / 6)),
        ]
        let inBedEdges = edges.map { SleepSample(stage: .inBed, start: $0.start, end: $0.end) }
        let alone = try #require(calculator.score(samples: night))
        let withEdges = try #require(calculator.score(samples: night + edges))
        let withInBed = try #require(calculator.score(samples: night + inBedEdges))
        #expect(alone.interruptions == 1)
        #expect(withEdges.interruptions == 1)
        // Same time in bed either way, so the score is the same: before the
        // fix the two edge spans counted as wake-ups and cost interruption points.
        #expect(withEdges.score == withInBed.score)
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

    /// Full marks at need, a gentle slope to 7 h, a steeper one below it
    /// (Watson 2015: 7 h minimum).
    @Test func durationFallsFasterUnderSevenHours() {
        let hour = 3600.0
        let need = 7.5 * hour
        #expect(SleepCalculator.durationScore(asleep: 8 * hour, need: need) == 1)
        #expect(SleepCalculator.durationScore(asleep: need, need: need) == 1)
        #expect(abs(SleepCalculator.durationScore(asleep: 7 * hour, need: need) - 0.9) < 0.001)
        #expect(abs(SleepCalculator.durationScore(asleep: 6 * hour, need: need) - 0.55) < 0.001)
        #expect(SleepCalculator.durationScore(asleep: 4 * hour, need: need) == 0)
        // 6 h 59 m vs 7 h 30 m no longer score the same.
        let short = SleepCalculator.durationScore(asleep: 7 * hour - 60, need: need)
        #expect(short < 0.9)
        // A need under 7 h: every hour short is below the minimum.
        #expect(abs(SleepCalculator.durationScore(asleep: 5.5 * hour, need: 6.5 * hour) - 0.65) < 0.001)
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
        // 5.6 h asleep with three wakings: 70% of 8 h in bed earns nothing,
        // 80% of 7 h earns two thirds. (Wake time sits inside the night, since
        // in-bed time outside the main sleep is clipped.)
        func night(awakeHours: Double) -> [SleepSample] {
            var samples: [SleepSample] = []
            var t = 0.0
            for block in 0..<4 {
                samples.append(SleepSample(stage: .core, start: at(t), end: at(t + 1.4)))
                t += 1.4
                if block < 3 {
                    samples.append(SleepSample(stage: .awake, start: at(t), end: at(t + awakeHours / 3)))
                    t += awakeHours / 3
                }
            }
            return samples
        }
        let seventy = night(awakeHours: 2.4)
        let eighty = night(awakeHours: 1.4)
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

    // Changed on purpose (QA round 1): one typed reading used to wipe every
    // night's Apple Health HRV. Now SDNN stays until RMSSD covers 14 of 30 nights.
    @Test func manualOnlyKeepsHealthHRVUntilRMSSDCoversTheWindow() {
        let earlier = morning.addingTimeInterval(-86_400)
        let health = [
            DailyVitals(date: morning, hrvMilliseconds: 60, restingHeartRate: 52),
            DailyVitals(date: earlier, hrvMilliseconds: 62, restingHeartRate: 53),
        ]
        let merged = DailyVitals.merging(health, manualHRV: [morning: 48], manualOnlyHRV: true, calendar: calendar)
        #expect(merged.first { $0.date == morning }?.hrvMilliseconds == 60)
        #expect(merged.first { $0.date == earlier }?.hrvMilliseconds == 62)
        #expect(merged.first { $0.date == earlier }?.restingHeartRate == 53)
    }

    @Test func manualOnlyNightsAreAddedNewestFirst() {
        let earlier = morning.addingTimeInterval(-86_400)
        let merged = DailyVitals.merging([], manualHRV: [earlier: 50, morning: 55], calendar: calendar)
        #expect(merged.map(\.hrvMilliseconds) == [55, 50])
        #expect(merged[0].restingHeartRate == nil)
    }
}

@Suite("Two devices' overnight HRV on one scale")
struct OvernightRMSSDMergeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let today = Date(timeIntervalSince1970: 1_800_000_000)
    private func night(_ daysAgo: Int) -> Date { calendar.startOfDay(for: today.addingTimeInterval(Double(-daysAgo) * 86_400)) }

    @Test("A new ring doesn't join the watch's baseline until nights overlap")
    func newRingWaits() {
        let watch = Dictionary(uniqueKeysWithValues: (3..<30).map { (night($0), 40.0) })
        let ring = Dictionary(uniqueKeysWithValues: (0..<3).map { (night($0), 62.0) })
        let merged = DailyVitals.mergingOvernightRMSSD(preferred: ring, other: watch, today: today, calendar: calendar)
        #expect(!merged.usesPreferredScale)
        #expect(merged.nights == watch)
    }

    @Test("With five shared nights the watch's nights are scaled to the ring's")
    func scaledByYourOwnRatio() throws {
        let watch = Dictionary(uniqueKeysWithValues: (0..<30).map { (night($0), 40.0) })
        let ring = Dictionary(uniqueKeysWithValues: (0..<5).map { (night($0), 60.0) })
        let merged = DailyVitals.mergingOvernightRMSSD(preferred: ring, other: watch, today: today, calendar: calendar)
        #expect(merged.usesPreferredScale)
        #expect(merged.nights.count == 30)
        #expect(merged.nights[night(2)] == 60)
        let older = try #require(merged.nights[night(20)])
        #expect(abs(older - 60) < 0.001)
    }

    @Test("Without shared nights the device with the longer recent record is used alone")
    func noOverlapSwitchesWhenTheRingHasMoreNights() {
        let watch = Dictionary(uniqueKeysWithValues: (16..<30).map { (night($0), 40.0) })
        let ring = Dictionary(uniqueKeysWithValues: (0..<16).map { (night($0), 60.0) })
        let merged = DailyVitals.mergingOvernightRMSSD(preferred: ring, other: watch, today: today, calendar: calendar)
        #expect(merged.usesPreferredScale)
        #expect(merged.nights == ring)
    }

    @Test("One device alone passes through")
    func single() {
        let watch = [night(1): 40.0, night(2): 0, night(3): 42.0]
        #expect(DailyVitals.mergingOvernightRMSSD(preferred: [:], other: watch, calendar: calendar).nights == [night(1): 40.0, night(3): 42.0])
        #expect(DailyVitals.mergingOvernightRMSSD(preferred: watch, other: [:], calendar: calendar).usesPreferredScale)
    }
}
