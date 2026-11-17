import Foundation
import Testing
@testable import AppCore

/// One HRV value per night from a watch's readings (`OvernightHRV`), with the
/// Apple Watch Series 12's five-minute readings as the case that matters.
@Suite struct OvernightHRVTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Midnight UTC.
    private var morning: Date {
        Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400))
    }

    /// Asleep 23:00 to 07:00, filed under `day`.
    private func night(_ day: Date) -> OvernightHRV.Night {
        OvernightHRV.Night(date: day, bedtime: day.addingTimeInterval(-3600), wake: day.addingTimeInterval(7 * 3600))
    }

    /// A reading every `step` minutes from `start` to `end`.
    private func readings(from start: Date, to end: Date, everyMinutes step: Double, ms: Double) -> [OvernightReading] {
        stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: step * 60).map {
            OvernightReading(date: Date(timeIntervalSince1970: $0), milliseconds: ms)
        }
    }

    @Test func meanOfTheReadingsInsideSleep() {
        let one = night(morning)
        let values = [
            OvernightReading(date: one.bedtime.addingTimeInterval(1800), milliseconds: 60),
            OvernightReading(date: one.bedtime.addingTimeInterval(7200), milliseconds: 70),
            OvernightReading(date: one.wake.addingTimeInterval(-600), milliseconds: 80),
        ]
        let result = OvernightHRV.nightly(values, nights: [one])
        #expect(result.count == 1)
        #expect(abs((result[morning] ?? 0) - 70) < 0.001)
    }

    @Test func awakeReadingsAreLeftOut() {
        let one = night(morning)
        var values = readings(from: one.bedtime, to: one.wake, everyMinutes: 5, ms: 65)
        // The evening before and the morning after, awake and lower.
        values += readings(from: one.bedtime.addingTimeInterval(-5 * 3600), to: one.bedtime.addingTimeInterval(-60), everyMinutes: 5, ms: 30)
        values += readings(from: one.wake.addingTimeInterval(60), to: one.wake.addingTimeInterval(5 * 3600), everyMinutes: 5, ms: 30)
        let result = OvernightHRV.nightly(values, nights: [one])
        #expect(abs((result[morning] ?? 0) - 65) < 0.001)
    }

    /// The reason for the change: the same sleeper on a watch that reads
    /// every few hours and on one that reads every five minutes. The old
    /// 6 pm-to-noon mean drops by a fifth on the new watch; the in-sleep mean
    /// doesn't move.
    @Test func aDenserWatchDoesNotMoveTheNight() {
        let one = night(morning)
        let windowStart = morning.addingTimeInterval(-6 * 3600)
        let windowEnd = morning.addingTimeInterval(12 * 3600)
        func samples(everyMinutes step: Double) -> [OvernightReading] {
            readings(from: windowStart, to: windowEnd, everyMinutes: step, ms: 0).map { reading in
                let asleep = reading.date >= one.bedtime && reading.date <= one.wake
                return OvernightReading(date: reading.date, milliseconds: asleep ? 70 : 35)
            }
        }
        func windowMean(_ values: [OvernightReading]) -> Double { values.map(\.milliseconds).reduce(0, +) / Double(values.count) }

        // An older watch reads asleep about every two hours and rarely awake.
        let sparse = samples(everyMinutes: 120).filter { $0.date >= one.bedtime.addingTimeInterval(-2 * 3600) && $0.date <= one.wake }
        let dense = samples(everyMinutes: 5)
        #expect(windowMean(sparse) > 60)
        #expect(windowMean(dense) < 52)

        let fromSparse = OvernightHRV.nightly(sparse, nights: [one])[morning] ?? 0
        let fromDense = OvernightHRV.nightly(dense, nights: [one])[morning] ?? 0
        #expect(abs(fromSparse - 70) < 0.001)
        #expect(abs(fromDense - 70) < 0.001)
    }

    @Test func aNightNeedsEnoughReadings() {
        let one = night(morning)
        let two = [
            OvernightReading(date: one.bedtime.addingTimeInterval(600), milliseconds: 50),
            OvernightReading(date: one.bedtime.addingTimeInterval(1200), milliseconds: 60),
        ]
        #expect(OvernightHRV.nightly(two, nights: [one]).isEmpty)
        #expect(abs((OvernightHRV.nightly(two, nights: [one], minimumReadings: 1)[morning] ?? 0) - 55) < 0.001)
    }

    @Test func eachReadingGoesToItsOwnNight() {
        let days = (0..<5).map { morning.addingTimeInterval(Double($0) * 86_400) }
        let nights = days.map(night)
        var values: [OvernightReading] = []
        for (index, one) in nights.enumerated() {
            values += readings(from: one.bedtime, to: one.wake, everyMinutes: 30, ms: 40 + Double(index) * 10)
        }
        // Handed over out of order.
        let result = OvernightHRV.nightly(values.reversed(), nights: nights.reversed())
        #expect(result.count == 5)
        for (index, day) in days.enumerated() {
            #expect(abs((result[day] ?? 0) - (40 + Double(index) * 10)) < 0.001)
        }
    }

    @Test func badReadingsAndBadNightsAreIgnored() {
        let one = night(morning)
        let values = [
            OvernightReading(date: one.bedtime.addingTimeInterval(600), milliseconds: 0),
            OvernightReading(date: one.bedtime.addingTimeInterval(1200), milliseconds: .nan),
            OvernightReading(date: one.bedtime.addingTimeInterval(1800), milliseconds: -4),
            OvernightReading(date: one.bedtime.addingTimeInterval(2400), milliseconds: 55),
        ]
        #expect(OvernightHRV.nightly(values, nights: [one], minimumReadings: 1)[morning] == 55)
        let backwards = OvernightHRV.Night(date: morning, bedtime: one.wake, wake: one.bedtime)
        #expect(OvernightHRV.nightly(values, nights: [backwards], minimumReadings: 1).isEmpty)
        #expect(OvernightHRV.nightly(values, nights: []).isEmpty)
    }

    @Test func aNightKeepsItsOldValueWithoutAnInSleepOne() {
        let yesterday = morning.addingTimeInterval(-86_400)
        let vitals = [
            DailyVitals(date: morning, hrvMilliseconds: 48, restingHeartRate: 52),
            DailyVitals(date: yesterday, hrvMilliseconds: 50, restingHeartRate: 53),
        ]
        let result = OvernightHRV.preferringSleep(vitals, asleep: [morning.addingTimeInterval(3 * 3600): 66], calendar: calendar)
        #expect(result.count == 2)
        #expect(result[0].date == morning)
        #expect(result[0].hrvMilliseconds == 66)
        #expect(result[0].restingHeartRate == 52)
        #expect(result[1].hrvMilliseconds == 50)
        #expect(OvernightHRV.preferringSleep(vitals, asleep: [:], calendar: calendar) == vitals)
    }

    @Test func aNightTheClockWindowMissedIsAdded() {
        let vitals = [DailyVitals(date: morning, hrvMilliseconds: 48, restingHeartRate: 52)]
        let earlier = morning.addingTimeInterval(-2 * 86_400)
        let result = OvernightHRV.preferringSleep(vitals, asleep: [earlier: 61, morning: .nan], calendar: calendar)
        #expect(result.map(\.date) == [morning, earlier])
        #expect(result[0].hrvMilliseconds == 48)
        #expect(result[1].hrvMilliseconds == 61)
        #expect(result[1].restingHeartRate == nil)
    }

    @Test func evenlySpacedKeepsTheEndsAndTheOrder() {
        let items = Array(0..<100)
        let picked = OvernightHRV.evenlySpaced(items, limit: 10)
        #expect(picked.count == 10)
        #expect(picked.first == 0)
        #expect(picked.last == 99)
        #expect(picked == picked.sorted())
        #expect(Set(picked).count == 10)
        #expect(OvernightHRV.evenlySpaced(items, limit: 200) == items)
        #expect(OvernightHRV.evenlySpaced(items, limit: 1) == [0])
        #expect(OvernightHRV.evenlySpaced(items, limit: 0).isEmpty)
        #expect(OvernightHRV.evenlySpaced([Int](), limit: 5).isEmpty)
    }

    /// The merge the app does with these: Apple's own nightly RMSSD first,
    /// and the beat-to-beat estimate for older nights on Apple's scale.
    @Test func olderNightsMoveToApplesScale() {
        let days = (0..<12).map { morning.addingTimeInterval(-Double($0) * 86_400) }
        var apple: [Date: Double] = [:]
        var estimate: [Date: Double] = [:]
        for (index, day) in days.enumerated() {
            estimate[day] = 50
            if index < 6 { apple[day] = 60 }
        }
        let merged = DailyVitals.mergingOvernightRMSSD(preferred: apple, other: estimate, today: morning, calendar: calendar)
        #expect(merged.usesPreferredScale)
        #expect(merged.nights.count == 12)
        for day in days { #expect(abs((merged.nights[day] ?? 0) - 60) < 0.001) }
    }
}
