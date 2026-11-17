import Foundation
import AppCore

/// Finished days of daytime vitals, already reduced to hourly buckets
/// (`DaytimeVitals.Day`), so each day's readings are read from Apple Health
/// once: an Apple Watch Series 12 writes about 17,000 heart-rate and 288 HRV
/// readings a day, and the usual range looks back four weeks. A JSON file in
/// Application Support, like `NightlyValueCache`; about 10 KB a day.
nonisolated final class DaytimeDayCache: @unchecked Sendable {
    /// Raise when the rules in `DaytimeVitals.day` change: stored days were
    /// reduced with the old ones and are read again.
    static let version = 1
    /// Days kept: the 28-day usual range, yesterday's own 28, and some slack.
    static let capacity = 45

    nonisolated private struct Stored: Codable, Sendable {
        var version: Int
        var days: [String: DaytimeVitals.Day]
    }

    private let lock = NSLock()
    private let fileURL: URL
    private var storage: [String: DaytimeVitals.Day]?

    init(fileName: String) {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: fileName)
    }

    private static func key(_ day: Date) -> String {
        Calendar.current.startOfDay(for: day).formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    /// Call with the lock held.
    private func loaded() -> [String: DaytimeVitals.Day] {
        if let storage { return storage }
        var decoded: [String: DaytimeVitals.Day] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Stored.self, from: data),
           stored.version == Self.version {
            decoded = stored.days
        }
        storage = decoded
        return decoded
    }

    /// The stored days among `days` (each the start of a day), keyed by that
    /// start. A day stored in another time zone starts at a different instant
    /// and is left out, so it is read again.
    func days(_ days: [Date]) -> [Date: DaytimeVitals.Day] {
        lock.lock(); defer { lock.unlock() }
        let entries = loaded()
        var result: [Date: DaytimeVitals.Day] = [:]
        for day in days {
            guard let entry = entries[Self.key(day)], entry.date == day, entry.hours.count == 24 else { continue }
            result[day] = entry
        }
        return result
    }

    /// Stores several days and writes the file once.
    func store(_ days: [DaytimeVitals.Day]) {
        guard !days.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var entries = loaded()
        for day in days {
            entries[Self.key(day.date)] = day
        }
        if entries.count > Self.capacity {
            for old in entries.keys.sorted().prefix(entries.count - Self.capacity) { entries[old] = nil }
        }
        storage = entries
        if let data = try? JSONEncoder().encode(Stored(version: Self.version, days: entries)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
