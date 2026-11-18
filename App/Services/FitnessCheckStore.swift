import Foundation
import AppCore

/// The quarterly fitness checks (`FitnessCheck`: a one-mile walk or a
/// treadmill walk test), kept in a small JSON file in Application Support.
/// Not written to Apple Health: a walking-test estimate isn't the watch's
/// reading, and mixing them would muddle its trend. Demo mode shows one
/// check from three months ago and saves nothing.
@Observable
final class FitnessCheckStore {
    static let shared = FitnessCheckStore()

    private(set) var results: [FitnessCheck.Result] = []
    @ObservationIgnored private var canSave = false
    @ObservationIgnored private let file = SafeJSONFile.appSupport("fitness-checks.json")

    private init() {
        reload()
    }

    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    /// Newest first.
    var history: [FitnessCheck.Result] { results.sorted { $0.date > $1.date } }

    func add(_ result: FitnessCheck.Result) {
        reloadIfUnavailable()
        results.append(result)
        save()
    }

    func delete(_ result: FitnessCheck.Result) {
        reloadIfUnavailable()
        results.removeAll { $0.id == result.id }
        save()
    }

    private func reload() {
        if DemoMode.isOn {
            let date = Calendar.current.date(byAdding: .day, value: -95, to: .now) ?? .now
            results = [FitnessCheck.Result(test: .mileWalk, date: date, vo2Max: 43.1)]
            canSave = false
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = file.loadLogged([FitnessCheck.Result].self, decoder: decoder)
        canSave = loaded.state.canSave
        if canSave { results = loaded.value ?? [] }
    }

    private func save() {
        guard !DemoMode.isOn else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        file.saveLogged(results, canSave: canSave, encoder: encoder)
    }
}
