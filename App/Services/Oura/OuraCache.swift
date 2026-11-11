import Foundation
import AppCore

/// What the direct Oura link last downloaded, kept on this phone
/// (`oura.json` in Application Support) so the sleep and HRV reads in
/// `HealthKitClient` can use it off the main actor and offline.
nonisolated final class OuraCache: @unchecked Sendable {
    static let shared = OuraCache()

    nonisolated struct Contents: Codable, Sendable, Equatable {
        var periods: [Oura.SleepPeriod] = []
        var readiness: [Oura.DailyReadiness] = []
        var dailySleep: [Oura.DailySleep] = []
        var syncedAt: Date?
    }

    /// Days of data kept (the HRV baseline and sleep history read up to 90).
    static let keptDays = 120

    private let lock = NSLock()
    private let fileURL: URL
    private var storage: Contents?

    init(fileName: String = "oura.json") {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: fileName)
    }

    /// Call with the lock held.
    private func loaded() -> Contents {
        if let storage { return storage }
        let decoded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Contents.self, from: $0) } ?? Contents()
        storage = decoded
        return decoded
    }

    var contents: Contents {
        lock.lock(); defer { lock.unlock() }
        return loaded()
    }

    var hasData: Bool { !contents.periods.isEmpty }

    /// Oura's sleep for the periods that start between `start` and `end`.
    func sleepSamples(from start: Date, to end: Date) -> [SleepSample] {
        Oura.samples(contents.periods, from: start, to: end)
    }

    /// Overnight RMSSD by morning, from Oura's main sleeps.
    func nightlyRMSSD() -> [Date: Double] {
        Oura.nightlyRMSSD(contents.periods)
    }

    /// Adds a sync's downloads (newer entries replace older ones with the
    /// same id or day) and drops anything older than `keptDays`.
    func merge(periods: [Oura.SleepPeriod], readiness: [Oura.DailyReadiness], dailySleep: [Oura.DailySleep], syncedAt: Date) {
        lock.lock(); defer { lock.unlock() }
        var contents = loaded()
        let cutoff = Date.now.addingTimeInterval(-Double(Self.keptDays) * 86_400)
        let cutoffDay = cutoff.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())

        var byID = Dictionary(contents.periods.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for period in periods { byID[period.id] = period }
        contents.periods = byID.values.filter { $0.bedtimeEnd >= cutoff && $0.type != "deleted" }.sorted { $0.bedtimeStart < $1.bedtimeStart }

        var readinessByDay = Dictionary(contents.readiness.map { ($0.day, $0) }, uniquingKeysWith: { _, new in new })
        for day in readiness { readinessByDay[day.day] = day }
        contents.readiness = readinessByDay.values.filter { $0.day >= cutoffDay }.sorted { $0.day < $1.day }

        var sleepByDay = Dictionary(contents.dailySleep.map { ($0.day, $0) }, uniquingKeysWith: { _, new in new })
        for day in dailySleep { sleepByDay[day.day] = day }
        contents.dailySleep = sleepByDay.values.filter { $0.day >= cutoffDay }.sorted { $0.day < $1.day }

        contents.syncedAt = syncedAt
        save(contents)
    }

    /// Forgets everything (on disconnect).
    func clear() {
        lock.lock(); defer { lock.unlock() }
        save(Contents())
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Call with the lock held.
    private func save(_ contents: Contents) {
        storage = contents
        if let data = try? JSONEncoder().encode(contents) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
