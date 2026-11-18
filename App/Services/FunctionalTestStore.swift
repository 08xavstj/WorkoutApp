import Foundation
import AppCore

/// The yearly functional tests (`FunctionalTest`: push-ups, sitting-rising,
/// one-leg stand), kept in a small JSON file in Application Support next to
/// the walking tests (`FitnessCheckStore`). Not written to Apple Health:
/// HealthKit has no type for them. Demo mode shows two push-up tests a year
/// apart and saves nothing.
@Observable
final class FunctionalTestStore {
    static let shared = FunctionalTestStore()

    private(set) var results: [FunctionalTest.Result] = []
    @ObservationIgnored private var canSave = false
    @ObservationIgnored private let file = SafeJSONFile.appSupport("functional-tests.json")

    private init() {
        reload()
    }

    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    /// This test's results, newest first.
    func history(_ test: FunctionalTest) -> [FunctionalTest.Result] {
        results.filter { $0.test == test }.sorted { $0.date > $1.date }
    }

    func add(_ result: FunctionalTest.Result) {
        reloadIfUnavailable()
        results.append(result)
        save()
    }

    func delete(_ result: FunctionalTest.Result) {
        reloadIfUnavailable()
        results.removeAll { $0.id == result.id }
        save()
    }

    private func reload() {
        if DemoMode.isOn {
            let calendar = Calendar.current
            let lastYear = calendar.date(byAdding: .day, value: -380, to: .now) ?? .now
            let recent = calendar.date(byAdding: .day, value: -15, to: .now) ?? .now
            results = [FunctionalTest.Result(test: .pushUps, date: lastYear, value: 27),
                       FunctionalTest.Result(test: .pushUps, date: recent, value: 31)]
            canSave = false
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = file.loadLogged([FunctionalTest.Result].self, decoder: decoder)
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
