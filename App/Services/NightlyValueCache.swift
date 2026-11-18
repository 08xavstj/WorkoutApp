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
        /// One value per source (`sourceValues(for:)`), for values that must
        /// come from one device across nights; nil in single-value caches.
        var bySource: [String: Double]? = nil
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

    /// Known nights only, with each source's value (empty = read before, nothing there).
    func sourceValues(for nights: [SleepNight]) -> [Date: [String: Double]] {
        lock.lock(); defer { lock.unlock() }
        let entries = loaded()
        var result: [Date: [String: Double]] = [:]
        for night in nights {
            guard let entry = entries[Self.key(night.date)], let bySource = entry.bySource,
                  abs(entry.bedtime - night.bedtime.timeIntervalSince1970) < 60,
                  abs(entry.wake - night.wake.timeIntervalSince1970) < 60 else { continue }
            result[night.date] = bySource
        }
        return result
    }

    /// Stores several nights and writes the file once. Keeps about 100 nights.
    func store(_ values: [(night: SleepNight, value: Double?)]) {
        write(values.map { item -> NightValues in NightValues(night: item.night, value: item.value, bySource: nil) })
    }

    /// Stores several nights' values by source (`sourceValues(for:)`).
    func storeSourceValues(_ values: [(night: SleepNight, bySource: [String: Double])]) {
        write(values.map { item -> NightValues in NightValues(night: item.night, value: nil, bySource: item.bySource) })
    }

    nonisolated private struct NightValues {
        var night: SleepNight
        var value: Double?
        var bySource: [String: Double]?
    }

    private func write(_ values: [NightValues]) {
        guard !values.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var entries = loaded()
        for item in values {
            entries[Self.key(item.night.date)] = Entry(value: item.value, bedtime: item.night.bedtime.timeIntervalSince1970,
                                                       wake: item.night.wake.timeIntervalSince1970, bySource: item.bySource)
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
