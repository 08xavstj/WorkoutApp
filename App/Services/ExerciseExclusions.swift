import Foundation
import AppCore

/// One exercise the user never wants planned again (Fitbod-style "never again").
nonisolated struct ExcludedExercise: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var addedAt: Date
}

/// The "never again" list, as JSON in UserDefaults. The trainer never plans
/// these and never offers them as a swap (`ExerciseFilter.neverAgain`).
@Observable
final class ExerciseExclusions {
    static let shared = ExerciseExclusions()

    private static let key = "neverAgainExercises"

    private(set) var items: [ExcludedExercise]

    init() {
        items = Self.load()
    }

    var ids: Set<String> { Set(items.map(\.id)) }

    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

    func add(id: String, name: String) {
        guard !contains(id) else { return }
        items.append(ExcludedExercise(id: id, name: name, addedAt: .now))
        write()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        write()
    }

    private func write() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func load() -> [ExcludedExercise] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([ExcludedExercise].self, from: data) else { return [] }
        return items
    }
}

/// Pain logged from the trainer ("Something hurts?" above the plan), as JSON
/// in UserDefaults. The morning check-in keeps its own answers in
/// `MorningCheckIn.pains`; `allReports` merges both with what Apple Health
/// has, and `PainGuard.active` keeps the newest per area for 7 days.
@Observable
final class PainLogStore {
    static let shared = PainLogStore()

    private static let key = "painLog"
    /// Kept long enough to tell when pain has lasted 2+ weeks (`PainGuard.clinicianDays`).
    static let keepDays = 30

    private(set) var reports: [PainReport]

    init() {
        reports = Self.load()
    }

    func log(_ new: [PainReport]) {
        guard !new.isEmpty else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        reports = (reports + new).filter { $0.loggedAt >= cutoff }
        if let data = try? JSONEncoder().encode(reports) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Everything logged in the last `keepDays`: the trainer's log, the
    /// morning check-ins' pain answers and Apple Health's (`health`).
    func allReports(checkIns: CheckInStore, health: [PainReport], now: Date = .now) -> [PainReport] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var all = reports + health
        for offset in 0..<Self.keepDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let pains = checkIns.morning(on: day)?.pains else { continue }
            all.append(contentsOf: pains)
        }
        return all
    }

    private static func load() -> [PainReport] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let reports = try? JSONDecoder().decode([PainReport].self, from: data) else { return [] }
        return reports
    }
}
