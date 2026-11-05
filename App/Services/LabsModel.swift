import Foundation
import AppCore

/// One blood-test result.
nonisolated struct LabResult: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id = UUID()
    /// Name as entered or printed on the report.
    var name: String
    /// Catalog marker (`LabMarkers`), when recognised; used to group results.
    var markerID: String?
    var value: Double
    var unit: String
    /// The lab's reference range (or the typical range, if none was given).
    var referenceLow: Double?
    var referenceHigh: Double?
    var date: Date
    var panel: String?
    var notes: String = ""

    var status: LabMarkers.Status? {
        LabMarkers.status(value: value, low: referenceLow, high: referenceHigh)
    }

    /// Results with the same key are the same test over time.
    var groupKey: String { markerID ?? name.lowercased() }

    var rangeText: String? {
        func f(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
        switch (referenceLow, referenceHigh) {
        case let (low?, high?): return "\(f(low))–\(f(high)) \(unit)"
        case let (nil, high?): return "under \(f(high)) \(unit)"
        case let (low?, nil): return "\(f(low)) \(unit) or more"
        default: return nil
        }
    }
}

/// Your lab results, typed in by hand and stored as a file inside the app
/// (not in iCloud Drive or Photos). Nothing is sent anywhere.
@Observable
final class LabsModel {
    private(set) var results: [LabResult] = []

    init() {
        results = Self.load()
    }

    /// Latest result for each test, most recent first.
    var latest: [LabResult] {
        var seen = Set<String>()
        return results.sorted { $0.date > $1.date }.filter { seen.insert($0.groupKey).inserted }
    }

    func history(for key: String) -> [LabResult] {
        results.filter { $0.groupKey == key }.sorted { $0.date < $1.date }
    }

    var outOfRange: [LabResult] { latest.filter { $0.status == .low || $0.status == .high } }

    func add(_ new: [LabResult]) {
        results.append(contentsOf: new)
        save()
    }

    func delete(_ result: LabResult) {
        results.removeAll { $0.id == result.id }
        save()
    }

    /// Lines for the coach: the latest of each test, flagged when out of range.
    var coachSummary: [String]? {
        guard !results.isEmpty else { return nil }
        return latest.prefix(25).map { result in
            var line = "\(result.name) \(result.value.formatted(.number.precision(.fractionLength(0...2)))) \(result.unit) on \(result.date.formatted(date: .abbreviated, time: .omitted))"
            if let range = result.rangeText { line += " (range \(range))" }
            if let status = result.status, status != .inRange { line += " — \(status.rawValue.lowercased())" }
            return line
        }
    }

    // MARK: Storage

    nonisolated private static var fileURL: URL {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "lab-results.json")
    }

    nonisolated private static func load() -> [LabResult] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LabResult].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(results) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }
}
