import AppCore
import Foundation

/// Finished weeks of cardio minutes (`WeeklyIntensity.Week`), kept as JSON in
/// Application Support so twelve weeks of heart rate aren't read from Apple
/// Health on every visit. Only weeks before the current one are kept; a week
/// is counted again when the zones, profile or counting change (`signature`)
/// or when the lifting left out of it changes (`WeeklyIntensity.liftingFingerprints`:
/// an edited, added or deleted session).
enum WeeklyIntensityCache {
    static let fileName = "weekly-intensity.json"
    private static let file = SafeJSONFile.appSupport(fileName)

    nonisolated struct Entry: Codable, Sendable {
        var week: WeeklyIntensity.Week
        /// The week's lifting fingerprint; nil in files from before it existed.
        var lifting: String?
    }

    nonisolated struct Stored: Codable, Sendable {
        var signature: String
        var entries: [Entry]
    }

    /// Cached weeks that still match, by week start.
    static func weeks(signature: String, lifting: [Date: String]) -> [Date: WeeklyIntensity.Week] {
        guard let stored = file.loadLogged(Stored.self).value, stored.signature == signature else { return [:] }
        var result: [Date: WeeklyIntensity.Week] = [:]
        for entry in stored.entries where entry.lifting != nil && entry.lifting == lifting[entry.week.start, default: ""] {
            result[entry.week.start] = entry.week
        }
        return result
    }

    /// Keeps finished weeks (the app's choice: the 12 shown plus a few).
    static func store(_ weeks: [WeeklyIntensity.Week], signature: String, lifting: [Date: String]) {
        let loaded = file.loadLogged(Stored.self)
        let entries = weeks.suffix(16).map { Entry(week: $0, lifting: lifting[$0.start, default: ""]) }
        file.saveLogged(Stored(signature: signature, entries: Array(entries)), canSave: loaded.state.canSave)
    }
}
