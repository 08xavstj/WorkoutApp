import Foundation
import Testing
@testable import AppCore

/// Apple's numbers by day (`AppleScoreLog`) and Apple's published bands.
@Suite struct AppleScoresTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_794_900_000) // 17 Nov 2026

    // MARK: Ranges and bands

    @Test func ranges() {
        #expect(AppleScoreKind.readiness.accepts(0))
        #expect(AppleScoreKind.readiness.accepts(10))
        #expect(!AppleScoreKind.readiness.accepts(11))
        #expect(!AppleScoreKind.readiness.accepts(-1))
        #expect(AppleScoreKind.sleepScore.accepts(100))
        #expect(!AppleScoreKind.sleepScore.accepts(101))
        #expect(AppleScoreKind.healthAge.accepts(10))
        #expect(AppleScoreKind.healthAge.accepts(120))
        #expect(!AppleScoreKind.healthAge.accepts(9))
    }

    @Test func readinessBandsCoverEveryScoreOnce() {
        for score in 0...10 {
            #expect(AppleReadinessLevel.allCases.filter { $0.range.contains(score) }.count == 1)
        }
        #expect(AppleReadinessLevel(score: 0) == .recover)
        #expect(AppleReadinessLevel(score: 1) == .recover)
        #expect(AppleReadinessLevel(score: 2) == .paceYourself)
        #expect(AppleReadinessLevel(score: 4) == .paceYourself)
        #expect(AppleReadinessLevel(score: 5) == .ready)
        #expect(AppleReadinessLevel(score: 7) == .ready)
        #expect(AppleReadinessLevel(score: 8) == .goForIt)
        #expect(AppleReadinessLevel(score: 10) == .goForIt)
        #expect(AppleReadinessLevel(score: 11) == nil)
    }

    @Test func sleepBandsCoverEveryScoreOnce() {
        for score in 0...100 {
            #expect(AppleSleepScoreLevel.allCases.filter { $0.range.contains(score) }.count == 1)
        }
        #expect(AppleSleepScoreLevel(score: 40) == .veryLow)
        #expect(AppleSleepScoreLevel(score: 41) == .low)
        #expect(AppleSleepScoreLevel(score: 61) == .ok)
        #expect(AppleSleepScoreLevel(score: 81) == .high)
        #expect(AppleSleepScoreLevel(score: 96) == .veryHigh)
        #expect(AppleScoreKind.sleepScore.levelLabel(for: 82) == "High")
        #expect(AppleScoreKind.readiness.levelLabel(for: 3) == "Pace Yourself")
        #expect(AppleScoreKind.healthAge.levelLabel(for: 34) == nil)
    }

    // MARK: Day keys

    /// A Readiness logged for yesterday (a "Yesterday" screenshot) gets the
    /// app's recovery from that day, which was noted before Apple's number came in.
    @Test func aReadinessLoggedLaterIsStillPaired() {
        var log = AppleScoreLog()
        let noted = log.noteAppRecovery(62, day: "2026-11-16")
        #expect(noted)
        #expect(log.days.isEmpty)
        log.record(.readiness, value: 7, day: "2026-11-16", at: now, source: .screenshot)
        #expect(log.days["2026-11-16"]?.appRecovery == 62)
        // Noting it again for a day that now has Apple's number updates the pair.
        let updated = log.noteAppRecovery(64, day: "2026-11-16")
        #expect(updated)
        #expect(log.days["2026-11-16"]?.appRecovery == 64)
        let again = log.noteAppRecovery(64, day: "2026-11-16")
        #expect(!again)
    }

    @Test func onlyTwoWeeksOfRecoveryAreKept() {
        var log = AppleScoreLog()
        log.noteAppRecovery(50, day: "2026-11-01")
        log.noteAppRecovery(55, day: "2026-11-14")
        #expect(log.recentRecovery?["2026-11-01"] == 50)
        log.noteAppRecovery(60, day: "2026-11-15")
        #expect(log.recentRecovery?["2026-11-01"] == nil)
        #expect(log.recentRecovery?["2026-11-14"] == 55)
        // Too old to have been kept: no pair.
        log.record(.readiness, value: 6, day: "2026-11-01", at: now, source: .typed)
        #expect(log.days["2026-11-01"]?.appRecovery == nil)
        let bad = log.noteAppRecovery(60, day: "not a day")
        #expect(!bad)
    }

    @Test func aLogSavedBeforeRecoveryWasKeptStillDecodes() throws {
        let old = #"{"days":{"2026-11-16":{"readiness":{"value":7,"recordedAt":0,"source":"typed"}}}}"#
        let log = try JSONDecoder().decode(AppleScoreLog.self, from: Data(old.utf8))
        #expect(log.days["2026-11-16"]?.readiness?.value == 7)
        #expect(log.recentRecovery == nil)
    }

    @Test func dayKeys() {
        let key = AppleScoreLog.key(for: now, calendar: calendar)
        #expect(key == "2026-11-17")
        #expect(AppleScoreLog.key(year: 2026, month: 3, day: 5) == "2026-03-05")
        let back = AppleScoreLog.date(forKey: key, calendar: calendar)
        #expect(back.map { AppleScoreLog.key(for: $0, calendar: calendar) } == key)
        #expect(AppleScoreLog.date(forKey: "nonsense", calendar: calendar) == nil)
        #expect(AppleScoreLog.date(forKey: "2026-13-01", calendar: calendar) == nil)
    }

    @Test func ordinalsCountDays() {
        #expect(AppleScoreLog.ordinal(forKey: "1970-01-01") == 0)
        #expect(AppleScoreLog.ordinal(forKey: "1970-01-02") == 1)
        #expect(AppleScoreLog.ordinal(forKey: "2000-03-01") == 11_017)
        // Across a leap day and a year end.
        let leap = (AppleScoreLog.ordinal(forKey: "2028-03-01") ?? 0) - (AppleScoreLog.ordinal(forKey: "2028-02-28") ?? 0)
        #expect(leap == 2)
        let yearEnd = (AppleScoreLog.ordinal(forKey: "2027-01-01") ?? 0) - (AppleScoreLog.ordinal(forKey: "2026-12-31") ?? 0)
        #expect(yearEnd == 1)
        // Agrees with the calendar for today.
        let days = Int(calendar.startOfDay(for: now).timeIntervalSince1970 / 86_400)
        #expect(AppleScoreLog.ordinal(forKey: "2026-11-17") == days)
    }

    // MARK: Recording

    @Test func recordsAndReplacesOneReadingPerDay() {
        var log = AppleScoreLog()
        let first = log.record(.readiness, value: 6, day: "2026-11-17", at: now, source: .typed)
        #expect(first)
        let second = log.record(.readiness, value: 8, day: "2026-11-17", at: now.addingTimeInterval(3600), source: .screenshot)
        #expect(second)
        #expect(log.entries(.readiness).count == 1)
        #expect(log.reading(.readiness, day: "2026-11-17")?.value == 8)
        #expect(log.reading(.readiness, day: "2026-11-17")?.source == .screenshot)
        #expect(log.reading(.sleepScore, day: "2026-11-17") == nil)
    }

    @Test func rejectsValuesOutsideTheRange() {
        var log = AppleScoreLog()
        let tooHigh = log.record(.readiness, value: 11, day: "2026-11-17", at: now, source: .shortcut)
        #expect(!tooHigh)
        let negative = log.record(.sleepScore, value: -1, day: "2026-11-17", at: now, source: .shortcut)
        #expect(!negative)
        let tooYoung = log.record(.healthAge, value: 5, day: "2026-11-17", at: now, source: .shortcut)
        #expect(!tooYoung)
        let badDay = log.record(.readiness, value: 5, day: "17 Nov", at: now, source: .typed)
        #expect(!badDay)
        #expect(log.isEmpty)
    }

    @Test func removingTheLastReadingRemovesTheDay() {
        var log = AppleScoreLog()
        log.record(.readiness, value: 6, day: "2026-11-17", at: now, source: .typed)
        log.record(.sleepScore, value: 80, day: "2026-11-17", at: now, source: .typed)
        log.setAppValue(.readiness, 62, day: "2026-11-17")
        log.remove(.readiness, day: "2026-11-17")
        #expect(log.reading(.readiness, day: "2026-11-17") == nil)
        #expect(log.days["2026-11-17"]?.appRecovery == nil)
        #expect(!log.isEmpty)
        log.remove(.sleepScore, day: "2026-11-17")
        #expect(log.isEmpty)
    }

    @Test func latestIsByDayNotByWhenItWasTyped() {
        var log = AppleScoreLog()
        log.record(.healthAge, value: 35, day: "2026-11-10", at: now, source: .typed)
        log.record(.healthAge, value: 36, day: "2026-10-01", at: now.addingTimeInterval(60), source: .typed)
        #expect(log.latest(.healthAge)?.reading.value == 35)
        #expect(log.latest(.healthAge)?.day == "2026-11-10")
        #expect(log.latest(.readiness) == nil)
    }

    @Test func keepsTheNewestDays() {
        var log = AppleScoreLog()
        for offset in 0..<(AppleScoreLog.keptDays + 10) {
            let day = now.addingTimeInterval(-Double(offset) * 86_400)
            log.record(.sleepScore, value: 70, day: AppleScoreLog.key(for: day, calendar: calendar), at: day, source: .typed)
        }
        #expect(log.days.count == AppleScoreLog.keptDays)
        #expect(log.reading(.sleepScore, day: "2026-11-17") != nil)
    }

    // MARK: The app's own numbers

    @Test func appValuesOnlySitBesideAnAppleReading() {
        var log = AppleScoreLog()
        let withoutReading = log.setAppValue(.readiness, 62, day: "2026-11-17")
        #expect(!withoutReading)
        log.record(.readiness, value: 6, day: "2026-11-17", at: now, source: .typed)
        let otherKind = log.setAppValue(.sleepScore, 80, day: "2026-11-17")
        #expect(!otherKind)
        let changed = log.setAppValue(.readiness, 62, day: "2026-11-17")
        #expect(changed)
        let unchanged = log.setAppValue(.readiness, 62, day: "2026-11-17")
        #expect(!unchanged) // unchanged
        #expect(log.entries(.readiness).first?.appValue == 62)
    }

    @Test func pairsNeedBothNumbers() {
        var log = AppleScoreLog()
        log.record(.sleepScore, value: 82, day: "2026-11-15", at: now, source: .typed)
        log.record(.sleepScore, value: 74, day: "2026-11-16", at: now, source: .typed)
        log.record(.sleepScore, value: 90, day: "2026-11-17", at: now, source: .typed)
        log.setAppValue(.sleepScore, 78, day: "2026-11-15")
        log.setAppValue(.sleepScore, 85, day: "2026-11-17")
        let pairs = log.pairs(.sleepScore)
        #expect(pairs.count == 2)
        #expect(pairs.map(\.apple) == [82, 90])
        #expect(pairs.map(\.app) == [78, 85])
        #expect(pairs[1].day - pairs[0].day == 2)
    }

    @Test func surviveARoundTripThroughJSON() throws {
        var log = AppleScoreLog()
        log.record(.readiness, value: 7, day: "2026-11-17", at: now, source: .shortcut)
        log.record(.healthAge, value: 34, day: "2026-11-03", at: now, source: .migrated)
        log.setAppValue(.readiness, 66, day: "2026-11-17")
        let decoded = try JSONDecoder().decode(AppleScoreLog.self, from: JSONEncoder().encode(log))
        #expect(decoded == log)
    }

    // MARK: Coach

    @Test func coachLineNamesEachNumberItsScaleAndItsDay() {
        var log = AppleScoreLog()
        #expect(log.coachLine(today: "2026-11-17") == nil)
        log.record(.readiness, value: 7, day: "2026-11-17", at: now, source: .typed)
        log.record(.sleepScore, value: 82, day: "2026-11-16", at: now, source: .typed)
        log.record(.healthAge, value: 34, day: "2026-10-01", at: now, source: .typed)
        let line = log.coachLine(today: "2026-11-17") ?? ""
        #expect(line.contains("Apple's Readiness 7 out of 10 (\"Ready\"), today"))
        #expect(line.contains("Apple's Sleep score 82 out of 100, yesterday"))
        #expect(line.contains("Apple's Health Age 34 years, on 2026-10-01"))
        #expect(line.contains("differently"))
    }

    @Test func coachLineSurvivesThePromptVocabulary() {
        var log = AppleScoreLog()
        log.record(.readiness, value: 3, day: "2026-11-14", at: now, source: .typed)
        log.record(.sleepScore, value: 55, day: "2026-11-17", at: now, source: .typed)
        log.record(.healthAge, value: 41, day: "2026-11-17", at: now, source: .typed)
        let line = log.coachLine(today: "2026-11-17") ?? ""
        // Not dropped as a line about a condition, and no banned word left in it.
        let neutral = CoachPromptVocabulary.neutral(line)
        #expect(neutral != nil)
        #expect(!CoachPromptVocabulary.containsBannedWord(neutral ?? ""))
        // Apple's 0–10 number stays distinct from the app's own score, which
        // the prompt calls "Readiness score".
        #expect(neutral?.contains("Apple's Readiness 3 out of 10") == true)
        #expect(neutral?.contains("3 days ago") == true)
    }
}
