import Foundation
import AppCore

/// The breathing-training log (`InspiratoryTraining`: 30 breaths a day
/// through a handheld resistance trainer), kept as JSON in Application
/// Support. Not written to Apple Health: HealthKit has no type for it.
/// Demo mode shows the last nine days, one missed, and saves nothing.
@Observable
final class InspiratoryTrainingStore {
    static let shared = InspiratoryTrainingStore()

    private(set) var sessions: [InspiratoryTraining.Session] = []
    @ObservationIgnored private var canSave = false
    @ObservationIgnored private let file = SafeJSONFile.appSupport("breathing-training.json")

    private init() {
        reload()
    }

    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    /// Newest first.
    var history: [InspiratoryTraining.Session] { sessions.sorted { $0.date > $1.date } }

    func add(breaths: Int, at date: Date = .now) {
        guard breaths > 0 else { return }
        reloadIfUnavailable()
        sessions.append(InspiratoryTraining.Session(date: date, breaths: min(breaths, InspiratoryTraining.breathsPerSession)))
        save()
    }

    func delete(_ session: InspiratoryTraining.Session) {
        reloadIfUnavailable()
        sessions.removeAll { $0.id == session.id }
        save()
    }

    private func reload() {
        if DemoMode.isOn {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            sessions = (1...9).compactMap { daysAgo -> InspiratoryTraining.Session? in
                guard daysAgo != 4, let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
                return InspiratoryTraining.Session(date: day.addingTimeInterval(7.5 * 3600), breaths: 30)
            }
            canSave = false
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = file.loadLogged([InspiratoryTraining.Session].self, decoder: decoder)
        canSave = loaded.state.canSave
        if canSave { sessions = loaded.value ?? [] }
    }

    private func save() {
        guard !DemoMode.isOn else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        file.saveLogged(sessions, canSave: canSave, encoder: encoder)
    }
}
