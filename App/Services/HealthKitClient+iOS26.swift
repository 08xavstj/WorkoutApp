import Foundation
import HealthKit
import AppCore

/// Reads of the newer HealthKit types from docs/research/competitors.md §1g:
/// time in daylight (iOS 17), sleep-apnoea events (iOS 18) and the iOS 26
/// Medications API. The deployment target is iOS 26, so the iOS 17/18 types
/// are always present; the Medications API is behind a build flag until its
/// names have been checked against the SDK in Xcode (see below).
nonisolated extension HealthKitClient {
    /// Minutes outdoors in daylight per day (Apple Watch only; Garmin doesn't
    /// write it). Empty without a watch.
    @concurrent
    func timeInDaylight(days: Int) async throws -> [DatedValue] {
        try await dailySeries(.timeInDaylight, unit: .minute(), days: days, cumulative: true)
    }

    /// Nights (dated by the morning) on which the watch flagged possible sleep
    /// apnoea, in the last `days` days. Apple's notification runs on Series
    /// 9+/Ultra 2 and catches about two thirds of cases, so none flagged
    /// doesn't mean none (StopBangView says the same).
    @concurrent
    func sleepApneaNights(days: Int) async throws -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepApneaEvent), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            // An event in the evening belongs to the night ending the next morning (as sleep does).
            let nights = try await descriptor.result(for: store).map { calendar.startOfDay(for: $0.startDate.addingTimeInterval(6 * 3600)) }
            return Array(Set(nights)).sorted()
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }
}

/// A medication from the Health app's Medications list (iOS 26 Medications API).
nonisolated struct HealthMedication: Sendable, Equatable, Identifiable {
    /// Apple's stable concept identifier, used to avoid importing twice.
    var id: String
    var name: String
    var nickname: String?
    var isArchived: Bool
}

// MARK: - Medications API (iOS 26)
//
// The HKUserAnnotatedMedication / HKMedicationConcept / HKMedicationDoseEvent
// names below follow WWDC25 session 321 ("Meet the HealthKit Medications
// API") but could not be checked against the SDK here (no Xcode in this
// sandbox). They compile only with the TENSILE_HEALTHKIT_MEDICATIONS flag
// (add `-DTENSILE_HEALTHKIT_MEDICATIONS` to OTHER_SWIFT_FLAGS after confirming
// the names in Xcode). Without the flag, `importedMedications()` returns []
// and the rest of the app behaves as before. TODO(lead): verify and enable.
nonisolated extension HealthKitClient {
    #if TENSILE_HEALTHKIT_MEDICATIONS
    /// Asks for per-object read access to the Medications list (the API uses
    /// object-level authorization, not the usual type-level sheet).
    @concurrent
    func requestMedicationsAccess() async throws {
        guard isAvailable else { return }
        try await store.requestPerObjectReadAuthorization(for: HKObjectType.userAnnotatedMedicationType(), predicate: nil)
    }

    /// The user's medications from the Health app, read-only.
    @concurrent
    func importedMedications() async throws -> [HealthMedication] {
        guard isAvailable else { return [] }
        let descriptor = HKUserAnnotatedMedicationQueryDescriptor()
        return try await descriptor.result(for: store).map { entry in
            HealthMedication(
                id: entry.medication.identifier.identifier,
                name: entry.medication.displayText,
                nickname: entry.nickname,
                isArchived: entry.isArchived
            )
        }
    }
    #else
    /// Medications API not enabled in this build (see the note above).
    @concurrent
    func requestMedicationsAccess() async throws {}

    /// Medications API not enabled in this build: nothing to import.
    @concurrent
    func importedMedications() async throws -> [HealthMedication] { [] }
    #endif
}
