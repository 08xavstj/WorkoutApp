import AppCore
import Foundation

/// Finished weeks of cardio minutes (`WeeklyIntensity.Week`), kept as JSON in
/// Application Support so twelve weeks of heart rate aren't read from Apple
/// Health on every visit. Only weeks before the current one are kept; a week
/// is counted again when the zones or profile change (`signature`) or when
/// the number of lifting sessions logged in it changes (an edited log).
enum WeeklyIntensityCache {
    private static let file = SafeJSONFile.appSupport("weekly-intensity.json")

    nonisolated struct Entry: Codable, Sendable {
        var week: WeeklyIntensity.Week
        var liftingSessions: Int
    }

    nonisolated struct Stored: Codable, Sendable {
        var signature: String
        var entries: [Entry]
    }

    /// Cached weeks that still match, by week start.
    static func weeks(signature: String, liftingSessions: [Date: Int]) -> [Date: WeeklyIntensity.Week] {
        guard let stored = file.loadLogged(Stored.self).value, stored.signature == signature else { return [:] }
        var result: [Date: WeeklyIntensity.Week] = [:]
        for entry in stored.entries where entry.liftingSessions == liftingSessions[entry.week.start, default: 0] {
            result[entry.week.start] = entry.week
        }
        return result
    }

    /// Keeps finished weeks (the app's choice: the 12 shown plus a few).
    static func store(_ weeks: [WeeklyIntensity.Week], signature: String, liftingSessions: [Date: Int]) {
        let loaded = file.loadLogged(Stored.self)
        let entries = weeks.suffix(16).map { Entry(week: $0, liftingSessions: liftingSessions[$0.start, default: 0]) }
        file.saveLogged(Stored(signature: signature, entries: Array(entries)), canSave: loaded.state.canSave)
    }
}
