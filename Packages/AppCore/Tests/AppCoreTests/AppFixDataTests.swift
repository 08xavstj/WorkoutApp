import Foundation
import Testing
@testable import AppCore

/// QA round 1 (data fixes): safe JSON files, deterministic HRV per morning,
/// DST-safe regularity, late-wake recovery timing, new-user muscular load.
struct SafeJSONFileTests {
    struct Box: Codable, Equatable { var items: [Int] }

    /// A fresh folder per test.
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "safejson-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func missingFileStartsEmptyAndMaySave() throws {
        let file = SafeJSONFile(url: try folder().appending(path: "a.json"))
        let loaded = file.load(Box.self)
        #expect(loaded.state == .missing)
        #expect(loaded.value == nil)
        #expect(loaded.state.canSave)
    }

    @Test func savesAndKeepsTheLastGoodFileAsBackup() throws {
        let file = SafeJSONFile(url: try folder().appending(path: "a.json"))
        try file.save(Box(items: [1]))
        try file.save(Box(items: [1, 2]))
        #expect(file.load(Box.self).value == Box(items: [1, 2]))
        let backup = try JSONDecoder().decode(Box.self, from: Data(contentsOf: file.backupURL))
        #expect(backup == Box(items: [1]))
    }

    @Test func corruptFileIsMovedAsideAndTheBackupUsed() throws {
        let dir = try folder()
        let file = SafeJSONFile(url: dir.appending(path: "a.json"))
        try file.save(Box(items: [1]))
        try file.save(Box(items: [1, 2]))
        try Data("{ not json".utf8).write(to: file.url)
        let loaded = file.load(Box.self)
        #expect(loaded.state == .restoredFromBackup)
        #expect(loaded.value == Box(items: [1]))
        // The bad file is kept, not deleted, and no longer in the way.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("a.json.corrupt-") })
        // The good copy is back in place for the next launch.
        #expect(file.load(Box.self).value == Box(items: [1]))
        // Saving the restored value now doesn't replace the good backup with the bad file.
        try file.save(Box(items: [1, 3]))
        #expect(file.load(Box.self).value == Box(items: [1, 3]))
        let backup = try JSONDecoder().decode(Box.self, from: Data(contentsOf: file.backupURL))
        #expect(backup == Box(items: [1]))
    }

    @Test func corruptWithoutBackupIsKeptAside() throws {
        let dir = try folder()
        let file = SafeJSONFile(url: dir.appending(path: "a.json"))
        try Data("[1, 2".utf8).write(to: file.url)
        let loaded = file.load(Box.self)
        #expect(loaded.state == .corrupt)
        #expect(loaded.state.canSave)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("a.json.corrupt-") })
    }

    @Test func unreadableFileMustNotBeSaved() {
        #expect(!SafeJSONFile.ReadState.unavailable.canSave)
        #expect(SafeJSONFile.ReadState.restoredFromBackup.canSave)
    }

    @Test func deletedFileIsAResetNotARestore() throws {
        // Demo reset deletes the files; the backup must not bring them back.
        let file = SafeJSONFile(url: try folder().appending(path: "a.json"))
        try file.save(Box(items: [1]))
        try file.save(Box(items: [2]))
        try FileManager.default.removeItem(at: file.url)
        #expect(file.load(Box.self).state == .missing)
    }
}

struct HRVPerMorningTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    @Test func latestReadingOfAMorningWinsEveryTime() throws {
        let morning = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        // Beat-to-beat keyed at midnight, a typed Garmin value at 7:30 the same morning.
        let rmssd: [Date: Double] = [morning: 40, morning.addingTimeInterval(7.5 * 3600): 55]
        for _ in 0..<20 {
            let selection = DailyVitals.resolvingHRV([], overnightRMSSD: rmssd, today: morning, calendar: calendar)
            #expect(selection.vitals.count == 1)
            #expect(selection.vitals.first?.hrvMilliseconds == 55)
            let merged = DailyVitals.merging([], manualHRV: rmssd, calendar: calendar)
            #expect(merged.first?.hrvMilliseconds == 55)
        }
    }

    @Test func healthStillWinsOverTypedInTheOldMerge() {
        let morning = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let health = [DailyVitals(date: morning, hrvMilliseconds: 30, restingHeartRate: 55)]
        let merged = DailyVitals.merging(health, manualHRV: [morning.addingTimeInterval(3600): 50, morning.addingTimeInterval(7200): 60],
                                         calendar: calendar)
        #expect(merged.first?.hrvMilliseconds == 30)
    }
}

struct SleepRegularityDSTTests {
    @Test func calendarDaysKeepNightsAlignedAcrossADaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // US clocks go back on Sunday 1 November 2026.
        let firstMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28)))
        var intervals: [DateInterval] = []
        for night in 0..<8 {
            let morning = try #require(calendar.date(byAdding: .day, value: night, to: firstMorning))
            let evening = try #require(calendar.date(byAdding: .day, value: -1, to: morning))
            let bed = try #require(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: evening))
            let wake = try #require(calendar.date(bySettingHour: 7, minute: 0, second: 0, of: morning))
            intervals.append(DateInterval(start: bed, end: wake))
        }
        let dayBefore = try #require(calendar.date(byAdding: .day, value: -1, to: firstMorning))
        let start = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayBefore))
        let days = 8
        // Only the one 25-hour day can differ; every other pair lines up at the same clock time.
        let byCalendar = try #require(SleepRegularity.score(asleep: intervals, start: start, days: days, calendar: calendar))
        let fixed = try #require(SleepRegularity.score(asleep: intervals, start: start, days: days))
        #expect(byCalendar >= 97)
        #expect(byCalendar >= fixed)
        #expect(SleepRegularity.calendarDays(from: start, to: start.addingTimeInterval(8 * 86_400 + 3600), calendar: calendar) == 8)
    }
}

struct LateWakeRecoveryTimingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }
    var midnight: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }
    func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }

    @Test func daySleeperWaitsPastNoon() {
        // Usually wakes at 4 pm after a night shift: not scored at 1 pm, scored after 6 pm.
        #expect(!RecoveryTiming.nightIsOver(now: at(13), wake: nil, asleepHours: nil, tracksSleep: true,
                                            usualWakeMinutes: 16 * 60, calendar: calendar))
        #expect(RecoveryTiming.nightIsOver(now: at(18.5), wake: nil, asleepHours: nil, tracksSleep: true,
                                           usualWakeMinutes: 16 * 60, calendar: calendar))
        // Waking is still what ends the night.
        #expect(RecoveryTiming.nightIsOver(now: at(16.2), wake: at(16), asleepHours: 7, tracksSleep: true,
                                           usualWakeMinutes: 16 * 60, calendar: calendar))
    }

    @Test func fallbackHourStaysNoonForMorningWakers() {
        #expect(RecoveryTiming.fallbackHour(usualWakeMinutes: 7 * 60) == 12)
        #expect(RecoveryTiming.fallbackHour(usualWakeMinutes: nil) == 12)
        #expect(RecoveryTiming.fallbackHour(usualWakeMinutes: 19 * 60) == 20)
    }
}

struct NewUserMuscularLoadTests {
    @Test func daysBeforeTheFirstLiftAreUnknownNotRest() {
        // 13 days of nothing, then two weeks of lifting: without knownDays this reads as a spike.
        let loads = Array(repeating: 0.0, count: 13) + Array(repeating: 60.0, count: 14)
        let calculator = TrainingLoadCalculator()
        #expect(calculator.evaluate(dailyLoads: loads).status == .spike)
        let known = calculator.evaluate(dailyLoads: loads, knownDays: 14)
        #expect(known.status == .steady)
        // Under 14 known days it is still calibrating.
        #expect(calculator.evaluate(dailyLoads: loads, knownDays: 10).status == .calibrating)
    }
}

struct VO2PeerTextTests {
    @Test func agesOutsideTheTableSayWhichDecadeIsUsed() {
        #expect(VO2Norms.standing(vo2: 45, age: 34, sex: .male).percentileText.hasSuffix("your age"))
        #expect(VO2Norms.standing(vo2: 45, age: 17, sex: .male).percentileText.contains("in their 20s"))
        #expect(VO2Norms.standing(vo2: 25, age: 84, sex: .female).percentileText.contains("in their 70s"))
    }
}

struct OverdueReminderTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
    var today: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

    @Test func remindsOnTheDueDayFirst() {
        #expect(OverdueReminder.nextDay(due: day(5), lastNag: nil, intervalDays: 30, now: today, calendar: calendar) == day(5))
        // Already overdue and never reminded: today.
        #expect(OverdueReminder.nextDay(due: day(-10), lastNag: nil, intervalDays: 30, now: today, calendar: calendar) == today)
    }

    @Test func overdueRepeatsOnlyAfterAFullInterval() {
        let firedYesterday = day(-1).addingTimeInterval(9 * 3600)
        #expect(OverdueReminder.nextDay(due: day(-10), lastNag: firedYesterday, intervalDays: 30, now: today, calendar: calendar) == day(29))
        // A reminder still waiting to fire stays put.
        let pending = day(1).addingTimeInterval(9 * 3600)
        #expect(OverdueReminder.nextDay(due: day(-10), lastNag: pending, intervalDays: 30, now: today, calendar: calendar) == day(1))
    }

    @Test func measuringStartsAFreshCycle() {
        // The last reminder was for the old due date; the new one is later.
        let oldNag = day(-40)
        #expect(OverdueReminder.nextDay(due: day(20), lastNag: oldNag, intervalDays: 30, now: today, calendar: calendar) == day(20))
    }
}
