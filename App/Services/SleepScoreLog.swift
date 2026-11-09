import Foundation
import AppCore

/// Sleep scores by morning, saved as JSON in Application Support, so recovery
/// can compare last night with your own last 30 nights instead of a
/// population anchor (see `RecoveryCalculator.sleepBaseline`).
enum SleepScoreLog {
    private static let file = SafeJSONFile.appSupport("sleep-scores.json")
    /// Mornings kept (about three months).
    static let keptMornings = 100
    /// Recent mornings scored after the fact when the app wasn't opened that
    /// day, and checked against Health for deleted sleep (`DailyMetricsModel`).
    static let backfillDays = 7

    private static func key(_ morning: Date) -> String {
        Calendar.current.startOfDay(for: morning).formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    /// The saved scores, and whether the file may be written (it may not
    /// after a read that failed, e.g. in a background launch while locked).
    private static func load() -> (scores: [String: Int], canSave: Bool) {
        let loaded = file.loadLogged([String: Int].self)
        return (loaded.value ?? [:], loaded.state.canSave)
    }

    private static func save(_ scores: [String: Int]) {
        var scores = scores
        if scores.count > keptMornings {
            for old in scores.keys.sorted().prefix(scores.count - keptMornings) { scores[old] = nil }
        }
        file.saveLogged(scores, canSave: true)
    }

    /// Saves a morning's sleep score (nil leaves the log alone).
    static func record(_ score: Int?, on morning: Date) {
        guard let score else { return }
        update(adding: [morning: score], removing: [])
    }

    /// Adds scores and removes mornings in one write.
    static func update(adding: [Date: Int], removing: [Date]) {
        let loaded = load()
        guard loaded.canSave else { return }
        var scores = loaded.scores
        var changed = false
        for (morning, score) in adding where scores[key(morning)] != score {
            scores[key(morning)] = score
            changed = true
        }
        for morning in removing where scores[key(morning)] != nil {
            scores[key(morning)] = nil
            changed = true
        }
        if changed { save(scores) }
    }

    /// Mornings from `start` up to (not including) `end` that have a score.
    static func scoredMornings(from start: Date, before end: Date) -> Set<Date> {
        let scores = load().scores
        let calendar = Calendar.current
        var result = Set<Date>()
        var day = calendar.startOfDay(for: start)
        while day < end {
            if scores[key(day)] != nil { result.insert(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Scores from the `days` mornings before `morning` (not including it), oldest first.
    static func recentScores(before morning: Date, days: Int = 30) -> [Int] {
        let scores = load().scores
        let calendar = Calendar.current
        return (1...max(1, days)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: morning).flatMap { scores[key($0)] }
        }
    }
}
