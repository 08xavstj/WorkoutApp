import Foundation
import Testing
@testable import AppCore

struct HealthDataCheckTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 18 Nov 2026, 9 am.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))! }

    func daysAgo(_ days: Int, hour: Int = 3) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    @Test func nothingIsNone() {
        #expect(HealthDataCheck.status(newest: nil, cadence: .nightly, now: now, calendar: calendar) == .none)
    }

    @Test func lastNightIsCurrent() {
        #expect(HealthDataCheck.status(newest: daysAgo(0), cadence: .nightly, now: now, calendar: calendar) == .current)
        // The night before still counts (a morning that hasn't synced yet).
        #expect(HealthDataCheck.status(newest: daysAgo(2), cadence: .nightly, now: now, calendar: calendar) == .current)
    }

    @Test func nightlyThreeNightsOldIsLate() {
        #expect(HealthDataCheck.status(newest: daysAgo(3), cadence: .nightly, now: now, calendar: calendar) == .late(days: 3))
    }

    @Test func continuousAllowsOneDay() {
        #expect(HealthDataCheck.status(newest: daysAgo(1), cadence: .continuous, now: now, calendar: calendar) == .current)
        #expect(HealthDataCheck.status(newest: daysAgo(2), cadence: .continuous, now: now, calendar: calendar) == .late(days: 2))
    }

    @Test func occasionalIsCurrentAnywhereInTheWindow() {
        #expect(HealthDataCheck.status(newest: daysAgo(25), cadence: .occasional, now: now, calendar: calendar) == .current)
    }

    @Test func olderThanTheWindowIsNone() {
        #expect(HealthDataCheck.status(newest: daysAgo(31), cadence: .occasional, now: now, calendar: calendar) == .none)
    }

    @Test func aFutureReadingIsIgnored() {
        #expect(HealthDataCheck.status(newest: now.addingTimeInterval(3600), cadence: .continuous, now: now, calendar: calendar) == .none)
    }

    @Test func noneNamesTheHealthSwitch() throws {
        let text = try #require(HealthDataCheck.advice(status: .none, cadence: .nightly, healthName: "Respiratory Rate"))
        #expect(text.contains("Respiratory Rate"))
        #expect(text.contains("Privacy & Security › Health › Tensile"))
    }

    @Test func noAlertsIsTheUsualAnswer() throws {
        let text = try #require(HealthDataCheck.advice(status: .none, cadence: .alert, healthName: "High Heart Rate Notifications"))
        #expect(text.contains("usual"))
    }

    @Test func currentNeedsNoAdvice() {
        #expect(HealthDataCheck.advice(status: .current, cadence: .nightly, healthName: "Respiratory Rate") == nil)
    }

    @Test func lateNightlyMentionsWearingItToBed() throws {
        let text = try #require(HealthDataCheck.advice(status: .late(days: 4), cadence: .nightly, healthName: "Respiratory Rate"))
        #expect(text.contains("4 nights"))
    }
}

struct BreathingRateNightTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18))! }

    /// An Apple Watch night: a reading every few minutes from 11 pm to 6:30 am.
    func watchNight(morning: Date, value: Double) -> [(date: Date, value: Double, device: BaselineDevice, source: String)] {
        let start = morning.addingTimeInterval(-3600)
        return stride(from: 0.0, through: 7.5 * 3600, by: 300).map {
            (date: start.addingTimeInterval($0), value: value, device: .watch, source: "com.apple.health.watch")
        }
    }

    @Test func watchReadingsGiveLastNight() {
        let readings = (0..<20).flatMap { offset in
            watchNight(morning: calendar.date(byAdding: .day, value: -offset, to: today)!, value: 14 + Double(offset % 3) * 0.5)
        }
        let means = OneDeviceBaseline.nightlyMeans(readings, calendar: calendar)
        #expect(means.watch.count == 20)
        let choice = OneDeviceBaseline.choose(ring: means.ring, watch: means.watch, latest: today, calendar: calendar)
        #expect(choice.device == .watch)
        #expect(choice.night(today, calendar: calendar)?.value == 14)
    }

    @Test func aRingWithoutLastNightFallsBackToTheWatchForShowing() {
        // The ring carries the baseline (30 nights) but hasn't synced last night; the watch has it.
        var ring: [Date: Double] = [:]
        for offset in 1...30 { ring[calendar.date(byAdding: .day, value: -offset, to: today)!] = 15 }
        let watch = [today: 13.5]
        let choice = OneDeviceBaseline.choose(ring: ring, watch: watch, latest: today, calendar: calendar)
        #expect(choice.device == .ring)
        #expect(choice.nights[today] == nil)
        let shown = choice.night(today, calendar: calendar)
        #expect(shown?.value == 13.5)
        #expect(shown?.device == .watch)
    }

    @Test func theBaselineDeviceWinsWhenItHasTheNight() {
        var ring: [Date: Double] = [:]
        for offset in 0...20 { ring[calendar.date(byAdding: .day, value: -offset, to: today)!] = 15 }
        let choice = OneDeviceBaseline.choose(ring: ring, watch: [today: 13], latest: today, calendar: calendar)
        #expect(choice.night(today, calendar: calendar)?.device == .ring)
    }
}
