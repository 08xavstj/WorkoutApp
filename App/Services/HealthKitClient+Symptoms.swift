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
    static var checkInSymptomTypes: [HKCategoryType] {
        MorningCheckIn.Symptom.allCases.map(symptomType(for:))
    }

    /// The illness signs read back: the written four plus the other common
    /// signs of a respiratory infection from Apple's list. Lower back pain
    /// and the like are left out; they aren't illness.
    static var illnessReadTypes: [HKCategoryType] {
        checkInSymptomTypes + [HKCategoryType(.chills), HKCategoryType(.coughing), HKCategoryType(.runnyNose)]
    }

    /// Pain types that match a `PainArea`. Apple's symptom list
    /// (HKCategoryTypeIdentifier, "Symptom Type Identifiers", checked
    /// 6 Nov 2026) has `lowerBackPain` but nothing for the shoulder, elbow,
    /// wrist, hip, knee, ankle or neck, so only the lower back is shared.
    static var painTypes: [HKCategoryType] { [HKCategoryType(.lowerBackPain)] }

    /// Everything this file writes (asked for in `requestAuthorization`).
    static var symptomTypes: [HKCategoryType] { checkInSymptomTypes + painTypes }

    /// Everything this file reads (asked for in `requestAuthorization`).
    static var symptomReadTypes: [HKCategoryType] { illnessReadTypes + painTypes }

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
        for type in Self.checkInSymptomTypes {
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
            predicates: Self.illnessReadTypes.map { HKSamplePredicate<HKCategorySample>.categorySample(type: $0, predicate: predicate) },
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

    // MARK: Lower back pain (`PainGuard`)

    /// 0-10 → Apple's severity. App choice: 1-3 mild, 4-6 moderate, 7-10 severe.
    static func severity(forPain level: Int) -> HKCategoryValueSeverity {
        switch level {
        case ...3: .mild
        case 4...6: .moderate
        default: .severe
        }
    }

    /// Apple's severity → 0-10 for the trainer. App choice, the middle of
    /// each band above; "present, severity unknown" counts as 4 (a
    /// regression, not an avoid). Nil for "not present".
    static func painLevel(for severity: HKCategoryValueSeverity) -> Int? {
        switch severity {
        case .notPresent: nil
        case .mild: 2
        case .moderate: 5
        case .severe: 8
        case .unspecified: 4
        @unknown default: 4
        }
    }

    /// Writes today's lower back pain from the check-in or the trainer,
    /// replacing what this app wrote for that day. Nil or 0 clears it.
    @concurrent
    func saveLowerBackPain(level: Int?, date: Date) async throws {
        guard isAvailable else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return }
        let ownThatDay = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: day, end: next),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        let type = HKCategoryType(.lowerBackPain)
        _ = try? await store.deleteObjects(of: type, predicate: ownThatDay)
        guard let level, level > 0 else { return }
        let sample = HKCategorySample(type: type, value: Self.severity(forPain: level).rawValue, start: date, end: date)
        try await store.save(sample)
    }

    /// Lower back pain logged in Health by other apps (this app's own samples
    /// are left out: the check-in and trainer already have them), as reports
    /// for `PainGuard`. "Not present" samples clear the area.
    @concurrent
    func reportedPain(from start: Date, to end: Date) async throws -> [PainReport] {
        guard isAvailable else { return [] }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate<HKCategorySample>.categorySample(type: HKCategoryType(.lowerBackPain), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store).map { sample in
                let severity = HKCategoryValueSeverity(rawValue: sample.value) ?? .unspecified
                return PainReport(area: .lowerBack, level: Self.painLevel(for: severity) ?? 0, loggedAt: sample.startDate)
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }
}
