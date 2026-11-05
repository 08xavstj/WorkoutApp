import Foundation
import HealthKit
import AppCore

/// Symptoms shared with Apple Health (docs/research/watch-features.md 4.5,
/// ref A17 "Symptom Type Identifiers"): the morning check-in's symptoms are
/// written as symptom category samples so Health and other apps see them, and
/// symptoms logged in Health by other apps are read back so the illness
/// watch's "you feel unwell" signal is true even when the user logged them
/// elsewhere. Plumbing, no evidence claim of its own.
nonisolated extension HealthKitClient {
    /// The symptom types the check-in writes (one per `MorningCheckIn.Symptom`).
    static var symptomTypes: [HKCategoryType] {
        MorningCheckIn.Symptom.allCases.map(symptomType(for:))
    }

    /// The types read back: the written four plus the other common signs of a
    /// respiratory infection from Apple's list. Lower back pain and the like
    /// are left out; they aren't illness.
    static var symptomReadTypes: [HKCategoryType] {
        symptomTypes + [HKCategoryType(.chills), HKCategoryType(.coughing), HKCategoryType(.runnyNose)]
    }

    /// Apple's type for each check-in symptom. "Fever or chills" is written as
    /// fever; both are read back.
    static func symptomType(for symptom: MorningCheckIn.Symptom) -> HKCategoryType {
        switch symptom {
        case .soreThroat: HKCategoryType(.soreThroat)
        case .congestion: HKCategoryType(.sinusCongestion)
        case .fever: HKCategoryType(.fever)
        case .bodyAches: HKCategoryType(.generalizedBodyAche)
        }
    }

    /// Writes the check-in's symptoms for `date`'s day, replacing what this app
    /// wrote for that day before (so clearing symptoms in the check-in clears
    /// Health too). The check-in doesn't ask how bad, so the severity is
    /// `unspecified` (present, severity unknown).
    @concurrent
    func saveSymptoms(_ symptoms: [MorningCheckIn.Symptom], date: Date) async throws {
        guard isAvailable else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return }
        let ownThatDay = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: day, end: next),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        for type in Self.symptomTypes {
            _ = try? await store.deleteObjects(of: type, predicate: ownThatDay)
        }
        let samples = Set(symptoms).map { symptom in
            HKCategorySample(
                type: Self.symptomType(for: symptom),
                value: HKCategoryValueSeverity.unspecified.rawValue,
                start: date, end: date
            )
        }
        guard !samples.isEmpty else { return }
        try await store.save(samples)
    }

    /// Days (start of day) between `start` and `end` on which a symptom was
    /// logged in Health by the Health app or another app. This app's own
    /// check-in samples are left out, since the check-in already counts and
    /// clearing it must clear the signal. Samples marked "not present" are
    /// skipped.
    @concurrent
    func reportedSymptoms(from start: Date, to end: Date) async throws -> [Date] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: Self.symptomReadTypes.map { HKSamplePredicate<HKCategorySample>.categorySample(type: $0, predicate: predicate) },
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            let days = try await descriptor.result(for: store)
                .filter { $0.value != HKCategoryValueSeverity.notPresent.rawValue }
                .map { calendar.startOfDay(for: $0.startDate) }
            return Array(Set(days)).sorted()
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }
}
