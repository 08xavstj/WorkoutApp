import AppCore
import Foundation

/// Whether to download and show "Oura's own numbers" (`OuraOwnNumbersCard`),
/// readable anywhere. On by default: the owner asked for the panel (18 Nov 2026).
nonisolated enum OuraOwnNumbersSetting {
    static let key = "ouraOwnNumbers"
    /// Set when Oura refused the `heart_health` permission at sign-in, so the
    /// next sign-in asks without it (cardiovascular age and VO₂ max then stay empty).
    static let heartHealthRefusedKey = "ouraHeartHealthRefused"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static var heartHealthRefused: Bool {
        UserDefaults.standard.bool(forKey: heartHealthRefusedKey)
    }

    /// The permissions sign-in asks for now.
    static var requestedScopes: String {
        Oura.requestedScopes(ownNumbers: isOn, heartHealth: !heartHealthRefused)
    }
}

/// Oura's own scores and estimates as last downloaded (`oura-own.json` in
/// Application Support). Display-only: nothing in Tensile's scores reads this.
nonisolated final class OuraOwnNumbersStore: @unchecked Sendable {
    static let shared = OuraOwnNumbersStore()

    /// Days kept: enough for the panel's week-long trend.
    static let keptDays = 60

    private let lock = NSLock()
    private let fileURL: URL
    private var storage: OuraOwnNumbers?

    init(fileName: String = "oura-own.json") {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: fileName)
    }

    var numbers: OuraOwnNumbers {
        lock.lock(); defer { lock.unlock() }
        return loaded()
    }

    func merge(_ fresh: OuraOwnNumbers) {
        lock.lock(); defer { lock.unlock() }
        var numbers = loaded()
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keptDays, to: .now) ?? .now
        let style = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        numbers.merge(fresh, cutoffDay: cutoff.formatted(style))
        save(numbers)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        storage = OuraOwnNumbers()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Call with the lock held.
    private func loaded() -> OuraOwnNumbers {
        if let storage { return storage }
        let decoded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(OuraOwnNumbers.self, from: $0) } ?? OuraOwnNumbers()
        storage = decoded
        return decoded
    }

    /// Call with the lock held.
    private func save(_ numbers: OuraOwnNumbers) {
        storage = numbers
        if let data = try? JSONEncoder().encode(numbers) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
