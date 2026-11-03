import Foundation

/// Sleep scores by morning, saved as JSON in Application Support, so recovery
/// can compare last night with your own last 30 nights instead of a
/// population anchor (see `RecoveryCalculator.sleepBaseline`).
enum SleepScoreLog {
    private static let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "sleep-scores.json")
    }()

    private static func key(_ morning: Date) -> String {
        Calendar.current.startOfDay(for: morning).formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    private static func load() -> [String: Int] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return decoded
    }

    /// Saves a morning's sleep score (nil leaves the log alone).
    static func record(_ score: Int?, on morning: Date) {
        guard let score else { return }
        var scores = load()
        guard scores[key(morning)] != score else { return }
        scores[key(morning)] = score
        // Keep about three months.
        if scores.count > 100 {
            for old in scores.keys.sorted().prefix(scores.count - 100) { scores[old] = nil }
        }
        if let data = try? JSONEncoder().encode(scores) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Scores from the `days` mornings before `morning` (not including it), oldest first.
    static func recentScores(before morning: Date, days: Int = 30) -> [Int] {
        let scores = load()
        let calendar = Calendar.current
        return (1...max(1, days)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: morning).flatMap { scores[key($0)] }
        }
    }
}
