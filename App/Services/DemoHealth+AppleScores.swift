import Foundation
import AppCore

/// Demo mode's Apple scores (`AppleScoresStore`): four weeks of made-up
/// Readiness and Sleep scores with Tensile's own numbers beside them, and one
/// Health Age, so the Apple's scores screen and the comparison lines have
/// content in the screenshot tour. Deterministic, like the rest of `DemoHealth`.
nonisolated extension DemoHealth {
    func appleScores() -> AppleScoreLog {
        var log = AppleScoreLog()
        for daysAgo in (0...27).reversed() {
            let morning = day(daysAgo)
            let key = AppleScoreLog.key(for: morning)
            let typedAt = morning.addingTimeInterval(8 * 3600)
            // Readiness follows the night's HRV loosely; Tensile's recovery follows it more closely.
            let swing = (hrv(daysAgo) - 47) / 5.5
            let readiness = Int((5.6 + 1.9 * swing + 1.1 * Self.noise(daysAgo, 71)).rounded())
            let recovery = Int((61 + 15 * swing + 5 * Self.noise(daysAgo, 72)).rounded())
            // A few mornings were skipped, as they would be in real use.
            if daysAgo % 9 != 4 {
                log.record(.readiness, value: min(10, max(0, readiness)), day: key, at: typedAt, source: .screenshot)
                log.setAppValue(.readiness, min(99, max(1, recovery)), day: key)
            }
            let appSleep = Int((78 + 9 * Self.noise(daysAgo, 73)).rounded())
            let appleSleep = appSleep + 4 + Int((5 * Self.noise(daysAgo, 74)).rounded())
            if daysAgo % 11 != 7 {
                log.record(.sleepScore, value: min(100, max(0, appleSleep)), day: key, at: typedAt, source: .screenshot)
                log.setAppValue(.sleepScore, min(100, max(0, appSleep)), day: key)
            }
        }
        let healthAgeDay = day(6)
        let healthAgeKey = AppleScoreLog.key(for: healthAgeDay)
        log.record(.healthAge, value: age - 2, day: healthAgeKey, at: healthAgeDay.addingTimeInterval(9 * 3600), source: .typed)
        log.setAppValue(.healthAge, age - 1, day: healthAgeKey)
        return log
    }
}
