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

/// A result read from a PDF, waiting for the user to check it.
nonisolated struct LabDraft: Sendable, Identifiable, Equatable {
    var id = UUID()
    var result: LabResult
    var include = true
}

/// Your lab results, stored as a file inside the app (not in iCloud Drive or
/// Photos). PDFs are only sent to the server for reading and aren't stored there.
@Observable
final class LabsModel {
    private(set) var results: [LabResult] = []
    @ObservationIgnored private let cloud: CloudCoach

    init(cloud: CloudCoach) {
        self.cloud = cloud
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

    /// Lines for the AI coach: the latest of each test, flagged when out of range.
    var coachSummary: [String]? {
        guard !results.isEmpty else { return nil }
        return latest.prefix(25).map { result in
            var line = "\(result.name) \(result.value.formatted(.number.precision(.fractionLength(0...2)))) \(result.unit) on \(result.date.formatted(date: .abbreviated, time: .omitted))"
            if let range = result.rangeText { line += " (range \(range))" }
            if let status = result.status, status != .inRange { line += " — \(status.rawValue.lowercased())" }
            return line
        }
    }

    // MARK: Import

    nonisolated private struct ImportReply: Decodable {
        nonisolated struct Marker: Decodable {
            let name: String
            let value: Double
            let unit: String?
            let referenceLow: Double?
            let referenceHigh: Double?
            let date: String?
            let panel: String?
        }
        let markers: [Marker]
        let collectionDate: String?
    }

    enum ImportError: LocalizedError {
        case tooLarge, unreadable, nothingFound

        var errorDescription: String? {
            switch self {
            case .tooLarge: "That PDF is too large (over 8 MB). Try exporting just the results pages."
            case .unreadable: "Couldn't read results from that file."
            case .nothingFound: "No test results were found in that PDF."
            }
        }
    }

    /// Sends the PDF to the `labs` function, which reads the results with
    /// Claude. Nothing is saved until you review the drafts.
    func importPDF(_ data: Data, filename: String, sex: BiologicalSex, settings: UserSettings) async throws -> [LabDraft] {
        guard data.count <= 8_000_000 else { throw ImportError.tooLarge }
        let reply = try await cloud.extractLabs(pdfBase64: data.base64EncodedString(), filename: filename, settings: settings)
        guard let json = reply.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ImportReply.self, from: json) else { throw ImportError.unreadable }
        let fallbackDate = decoded.collectionDate.flatMap(Self.parseDate) ?? .now
        let drafts = decoded.markers.map { marker -> LabDraft in
            let catalog = LabMarkers.match(marker.name)
            let unit = marker.unit ?? catalog?.units.first?.unit ?? ""
            // Use the lab's range; fall back to the typical range for that unit.
            var low = marker.referenceLow
            var high = marker.referenceHigh
            if low == nil && high == nil, let option = catalog?.units.first(where: { $0.unit.lowercased() == unit.lowercased() }) {
                (low, high) = option.range(for: sex)
            }
            return LabDraft(result: LabResult(
                name: marker.name, markerID: catalog?.id, value: marker.value, unit: unit,
                referenceLow: low, referenceHigh: high,
                date: marker.date.flatMap(Self.parseDate) ?? fallbackDate,
                panel: marker.panel ?? catalog?.panel
            ))
        }
        guard !drafts.isEmpty else { throw ImportError.nothingFound }
        return drafts
    }

    nonisolated private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
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
