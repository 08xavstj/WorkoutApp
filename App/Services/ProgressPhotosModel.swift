import Foundation
import UIKit
import AppCore

/// Front and side progress photos, kept only inside the app: never in the
/// Photos library, left out of iCloud and computer backups, and never sent
/// anywhere.
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

    /// Earlier versions also stored weekly analyses here; those keys are
    /// ignored when the index is read and dropped on the next save.
    private struct Index: Codable {
        var entries: [Entry] = []
    }

    private(set) var entries: [Entry] = []

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var thumbnails: [String: UIImage] = [:]
    /// The index (`SafeJSONFile`). Until it has been read, nothing is saved
    /// over it: a launch in the background while the phone was locked used to
    /// read nothing, and the next save wiped the list of photos.
    @ObservationIgnored private let indexFile: SafeJSONFile
    @ObservationIgnored private var canSave = false

    init() {
        var folder = URL.applicationSupportDirectory.appending(path: "ProgressPhotos")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Keep body photos out of iCloud and computer backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        self.folder = folder
        indexFile = SafeJSONFile(url: folder.appending(path: "index.json"))
        reload()
    }

    /// Reads the index again if the last read failed (call when the phone unlocks).
    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        let loaded = indexFile.loadLogged(Index.self)
        canSave = loaded.state.canSave
        if canSave { entries = loaded.value?.entries ?? [] }
    }

    /// The index is protected until first unlock (readable in a background
    /// launch); the photos themselves stay unreadable while the phone is locked.
    private func saveIndex() {
        indexFile.saveLogged(Index(entries: entries), canSave: canSave)
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
        reloadIfUnavailable()
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
        reloadIfUnavailable()
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
}
