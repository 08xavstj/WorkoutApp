import Foundation
import Testing
@testable import AppCore

struct SleepRegularityTests {
    /// Noon on the first day.
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    func night(_ day: Int, startHour: Double, hours: Double) -> DateInterval {
        let start = base.addingTimeInterval(Double(day) * 86_400 + (startHour - 12) * 3600)
        return DateInterval(start: start, duration: hours * 3600)
    }

    @Test func identicalDaysScore100() throws {
        let nights = (0..<7).map { night($0, startHour: 23, hours: 8) }
        let sri = try #require(SleepRegularity.index(asleep: nights, start: base, days: 7))
        #expect(abs(sri - 100) < 0.001)
    }

    @Test func shiftedNightsScoreLower() throws {
        // 11 pm-7 am, then 2 am-10 am, alternating: 6 of every 24 h differ.
        let nights = (0..<7).map { night($0, startHour: $0.isMultiple(of: 2) ? 23 : 26, hours: 8) }
        let sri = try #require(SleepRegularity.index(asleep: nights, start: base, days: 7))
        #expect(abs(sri - 50) < 1)
    }

    @Test func missingNightsDontCountAsAwake() throws {
        // Night 3 wasn't recorded: pairs touching it are skipped, the rest are identical.
        let nights = (0..<8).filter { $0 != 3 }.map { night($0, startHour: 23, hours: 8) }
        let sri = try #require(SleepRegularity.index(asleep: nights, start: base, days: 8))
        #expect(abs(sri - 100) < 0.001)
    }

    @Test func needsFiveNights() {
        let nights = (0..<4).map { night($0, startHour: 23, hours: 8) }
        #expect(SleepRegularity.index(asleep: nights, start: base, days: 4) == nil)
    }
}

struct SleepDebtTests {
    @Test func twoWeeksShortIsHighAndCapped() throws {
        let debt = try #require(SleepDebt.compute(nightlyHours: Array(repeating: 6, count: 14), needHours: 8))
        #expect(debt.hours == 20)
        #expect(debt.level == .high)
        #expect(debt.extraMinutesPerNight == 60)
        #expect(debt.paybackNights == 14)
    }

    @Test func longNightsPayItBack() throws {
        let debt = try #require(SleepDebt.compute(nightlyHours: [6, 6, 6, 6, 10, 10], needHours: 8))
        #expect(debt.hours == 4)
        #expect(debt.level == .moderate)
        #expect(debt.extraMinutesPerNight == 45)
        #expect(debt.paybackNights == 6)
        #expect(debt.plan != nil)
    }

    @Test func caughtUpHasNoPlan() throws {
        let debt = try #require(SleepDebt.compute(nightlyHours: [8, 8.5, 7.8, 8, 9], needHours: 8))
        #expect(debt.level == .none)
        #expect(debt.plan == nil)
    }

    @Test func needsFiveNights() {
        #expect(SleepDebt.compute(nightlyHours: [6, 6, 6, 6], needHours: 8) == nil)
    }
}

struct BeatToBeatTests {
    /// Beats alternating 0.98 s and 1.02 s apart: successive differences of 40 ms.
    func beats(_ count: Int, gapAt: Int? = nil) -> [BeatToBeat.Beat] {
        var time = 0.0
        var result = [BeatToBeat.Beat(time: 0, precededByGap: false)]
        for index in 1...count {
            time += index.isMultiple(of: 2) ? 0.98 : 1.02
            result.append(BeatToBeat.Beat(time: time, precededByGap: index == gapAt))
        }
        return result
    }

    @Test func rmssdOfAlternatingBeats() throws {
        let value = try #require(BeatToBeat.rmssd(beats(200)))
        #expect(abs(value - 40) < 0.01)
    }

    @Test func gapsAreSkipped() throws {
        let value = try #require(BeatToBeat.rmssd(beats(200, gapAt: 100)))
        #expect(abs(value - 40) < 0.01)
    }

    @Test func ectopicBeatIsDropped() throws {
        var series = beats(200)
        // A premature beat: one interval of 0.6 s then a long one.
        series[101].time -= 0.4
        let value = try #require(BeatToBeat.rmssd(series))
        #expect(abs(value - 40) < 0.01)
    }

    @Test func needsThreeMinutes() {
        #expect(BeatToBeat.rmssd(beats(60)) == nil)
    }
}

struct RecoveryContributorTests {
    let today = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func explainsHighRecovery() throws {
        let history = (1...14).map { day in
            DailyVitals(date: today.addingTimeInterval(Double(-day) * 86_400),
                        hrvMilliseconds: 60 + (day.isMultiple(of: 2) ? 5 : -5),
                        restingHeartRate: 55 + (day.isMultiple(of: 2) ? 1 : -1))
        }
        let result = try #require(RecoveryCalculator().score(
            today: DailyVitals(date: today, hrvMilliseconds: 75, restingHeartRate: 52),
            history: history, sleepScore: 90
        ))
        let hrv = try #require(result.contributors.first { $0.id == "hrv" })
        #expect(hrv.effect == .raises)
        #expect(result.contributors.first { $0.id == "rhr" }?.effect == .raises)
        #expect(result.contributors.first { $0.id == "sleep" }?.effect == .raises)
        // Sorted by how much each moved the score.
        let weights = result.contributors.map(\.weight)
        #expect(weights == weights.sorted(by: >))
    }
}
