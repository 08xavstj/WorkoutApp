import Foundation

/// A small on-disk cache of one value per finished night (RMSSD, sleeping
/// heart rate), so each night is read from Apple Health once instead of on
/// every refresh. A JSON file in Application Support, like `SleepScoreLog`.
/// An entry only counts while the night's bedtime and wake still match, so an
/// edited or late-synced sleep is read again.
nonisolated final class NightlyValueCache: @unchecked Sendable {
    nonisolated private struct Entry: Codable, Sendable {
        /// Nil means "read, nothing there".
        var value: Double?
        var bedtime: Double
        var wake: Double
    }

    private let lock = NSLock()
    private let fileURL: URL
    private var storage: [String: Entry]?

    init(fileName: String) {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: fileName)
    }

    private static func key(_ night: Date) -> String {
        Calendar.current.startOfDay(for: night).formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    /// Call with the lock held.
    private func loaded() -> [String: Entry] {
        if let storage { return storage }
        var decoded: [String: Entry] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let entries = try? JSONDecoder().decode([String: Entry].self, from: data) {
            decoded = entries
        }
        storage = decoded
        return decoded
    }

    /// Known nights only (`.some(nil)` = read before, nothing there).
    func values(for nights: [SleepNight]) -> [Date: Double?] {
        lock.lock(); defer { lock.unlock() }
        let entries = loaded()
        var result: [Date: Double?] = [:]
        for night in nights {
            guard let entry = entries[Self.key(night.date)],
                  abs(entry.bedtime - night.bedtime.timeIntervalSince1970) < 60,
                  abs(entry.wake - night.wake.timeIntervalSince1970) < 60 else { continue }
            result[night.date] = .some(entry.value)
        }
        return result
    }

    /// Stores several nights and writes the file once. Keeps about 100 nights.
    func store(_ values: [(night: SleepNight, value: Double?)]) {
        guard !values.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var entries = loaded()
        for (night, value) in values {
            entries[Self.key(night.date)] = Entry(value: value, bedtime: night.bedtime.timeIntervalSince1970,
                                                  wake: night.wake.timeIntervalSince1970)
        }
        if entries.count > 100 {
            for old in entries.keys.sorted().prefix(entries.count - 100) { entries[old] = nil }
        }
        storage = entries
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
