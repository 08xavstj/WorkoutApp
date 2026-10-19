import Foundation
import UIKit

/// Front and side progress photos, kept only inside the app: never in the
/// Photos library, and left out of iCloud and computer backups. Plus the
/// optional weekly Claude analysis of them.
@Observable
final class ProgressPhotosModel {
    enum Pose: String, Codable, CaseIterable, Identifiable {
        case front, side
        var id: String { rawValue }
        var title: String { self == .front ? "Front" : "Side" }
    }

    struct Entry: Codable, Identifiable, Hashable {
        var id: String { "\(day)-\(pose.rawValue)" }
        /// "2026-10-18"
        var day: String
        var date: Date
        var pose: Pose
        var fileName: String
    }

    struct Analysis: Codable, Identifiable, Hashable {
        var id: Date { date }
        var date: Date
        var text: String
        var comparedDays: [String]
    }

    private struct Index: Codable {
        var entries: [Entry] = []
        var analyses: [Analysis] = []
        /// When the last analysis failed, so it isn't retried (and photos
        /// re-sent) on every refresh.
        var lastFailure: Date?
    }

    private(set) var entries: [Entry] = []
    private(set) var analyses: [Analysis] = []
    private(set) var isAnalyzing = false
    private(set) var analysisError: String?
    private var lastFailure: Date?

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let cloud: CloudCoach
    @ObservationIgnored private var thumbnails: [String: UIImage] = [:]

    /// Wait this long after a failed analysis before trying again on its own.
    static let retryDelay: TimeInterval = 24 * 3600

    init(cloud: CloudCoach) {
        self.cloud = cloud
        var folder = URL.applicationSupportDirectory.appending(path: "ProgressPhotos")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Keep body photos out of iCloud and computer backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        self.folder = folder
        if let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data) {
            entries = index.entries
            analyses = index.analyses
            lastFailure = index.lastFailure
        }
    }

    private var indexURL: URL { folder.appending(path: "index.json") }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(Index(entries: entries, analyses: analyses, lastFailure: lastFailure)) {
            // Encrypted at rest; unreadable while the phone is locked.
            try? data.write(to: indexURL, options: [.atomic, .completeFileProtection])
        }
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Photos

    /// Days with at least one photo, newest first.
    var days: [String] {
        Array(Set(entries.map(\.day))).sorted(by: >)
    }

    func entry(day: String, pose: Pose) -> Entry? {
        entries.first { $0.day == day && $0.pose == pose }
    }

    func todayEntry(_ pose: Pose) -> Entry? {
        entry(day: Self.dayKey(.now), pose: pose)
    }

    /// The most recent photo of a pose (for the camera's outline guide).
    func latest(_ pose: Pose) -> Entry? {
        entries.filter { $0.pose == pose }.max { $0.date < $1.date }
    }

    func save(_ image: UIImage, pose: Pose) {
        let day = Self.dayKey(.now)
        let fileName = "\(day)-\(pose.rawValue).jpg"
        guard let data = Self.resized(image, maxSide: 1600).jpegData(compressionQuality: 0.82) else { return }
        do {
            try data.write(to: folder.appending(path: fileName), options: [.atomic, .completeFileProtection])
        } catch {
            return
        }
        entries.removeAll { $0.day == day && $0.pose == pose }
        entries.append(Entry(day: day, date: .now, pose: pose, fileName: fileName))
        thumbnails[fileName] = nil
        saveIndex()
    }

    func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: folder.appending(path: entry.fileName))
        entries.removeAll { $0.id == entry.id }
        thumbnails[entry.fileName] = nil
        saveIndex()
    }

    func image(_ entry: Entry) -> UIImage? {
        UIImage(contentsOfFile: folder.appending(path: entry.fileName).path(percentEncoded: false))
    }

    func thumbnail(_ entry: Entry) -> UIImage? {
        if let cached = thumbnails[entry.fileName] { return cached }
        guard let full = image(entry) else { return nil }
        let small = Self.resized(full, maxSide: 360)
        thumbnails[entry.fileName] = small
        return small
    }

    nonisolated static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: Weekly analysis

    var latestAnalysis: Analysis? { analyses.max { $0.date < $1.date } }

    /// Due when it's been a week since the last one, there are photos from at
    /// least 5 days apart, and one of them is from the last 3 days.
    /// Not retried automatically for a day after a failure.
    var isAnalysisDue: Bool {
        if let last = latestAnalysis, Date.now.timeIntervalSince(last.date) < 7 * 86_400 { return false }
        if let lastFailure, Date.now.timeIntervalSince(lastFailure) < Self.retryDelay { return false }
        return comparisonDays() != nil
    }

    /// Baseline, about a week ago, and latest (days with a front or side photo).
    func comparisonDays() -> [String]? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let newest = sorted.last, let oldest = sorted.first,
              Date.now.timeIntervalSince(newest.date) < 3 * 86_400,
              newest.date.timeIntervalSince(oldest.date) >= 5 * 86_400 else { return nil }
        let weekAgo = newest.date.addingTimeInterval(-7 * 86_400)
        let middle = sorted.min { abs($0.date.timeIntervalSince(weekAgo)) < abs($1.date.timeIntervalSince(weekAgo)) }
        return Array(Set([oldest.day, middle?.day, newest.day].compactMap { $0 })).sorted()
    }

    /// Sends up to 6 photos (front and side for each compared day) plus a text
    /// summary of goals and data to Claude, and stores the reply.
    func analyze(context: String, settings: UserSettings) async {
        guard !isAnalyzing, let days = comparisonDays() else {
            analysisError = "Take photos on at least two days, 5+ days apart, to compare."
            return
        }
        isAnalyzing = true
        analysisError = nil
        defer { isAnalyzing = false }
        let labels = Self.dayLabels(days)
        var files: [(label: String, path: String)] = []
        for day in days {
            for pose in Pose.allCases {
                guard let entry = entry(day: day, pose: pose) else { continue }
                files.append(("\(labels[day] ?? day) (\(day)), \(pose.title.lowercased())",
                              folder.appending(path: entry.fileName).path(percentEncoded: false)))
            }
        }
        // Decoding and re-encoding photos is slow; keep it off the main thread.
        let photos = await Self.encodePhotos(files)
        guard photos.count >= 2 else {
            analysisError = "Not enough photos to compare yet."
            return
        }
        do {
            let text = try await cloud.analyzeProgress(photos: photos, context: context, settings: settings)
            analyses.append(Analysis(date: .now, text: text, comparedDays: days))
            lastFailure = nil
            saveIndex()
        } catch {
            analysisError = error.localizedDescription
            lastFailure = .now
            saveIndex()
        }
    }

    @concurrent
    nonisolated private static func encodePhotos(_ files: [(label: String, path: String)]) async -> [CloudCoach.Photo] {
        files.compactMap { file in
            guard let full = UIImage(contentsOfFile: file.path),
                  let data = resized(full, maxSide: 1024).jpegData(compressionQuality: 0.7) else { return nil }
            return CloudCoach.Photo(label: file.label, data: data.base64EncodedString())
        }
    }

    private static func dayLabels(_ days: [String]) -> [String: String] {
        var labels: [String: String] = [:]
        for (index, day) in days.enumerated() {
            labels[day] = index == 0 ? "Earliest" : (index == days.count - 1 ? "Latest" : "About a week ago")
        }
        return labels
    }
}
