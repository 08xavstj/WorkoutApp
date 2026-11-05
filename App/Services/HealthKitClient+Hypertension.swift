import Foundation
import HealthKit
import AppCore

// MARK: - Hypertension notification (iOS/watchOS 26.2)
//
// `HKCategoryTypeIdentifier.hypertensionEvent` is listed on Apple's page with
// availability iOS/watchOS 26.2+ and no description or value enum yet
// (docs/research/watch-features.md 1.1, ref A3), so any sample is treated as
// one notification. The name could not be checked against an SDK here (no
// Xcode in this sandbox) and CI's Xcode may predate 26.2, so the code compiles
// only with the TENSILE_HYPERTENSION_EVENT flag (add
// `-DTENSILE_HYPERTENSION_EVENT` to OTHER_SWIFT_FLAGS after confirming the
// identifier exists in Xcode 26.2+). Without the flag nothing is read and
// `hypertensionEvents(since:)` returns []. TODO(lead): verify and enable.
//
// What the watch does: Series 9+/Ultra 2+ review 30 days of optical data and
// notify on consistent signs of hypertension; validation against 30-day home
// blood pressure found sensitivity 41%, specificity 92% (refs B1-B3; the
// figures live in `HomeBloodPressure`).
nonisolated extension HealthKitClient {
    #if TENSILE_HYPERTENSION_EVENT
    /// The notification's category type, for `readTypes` (empty before iOS 26.2).
    static var hypertensionReadTypes: [HKObjectType] {
        if #available(iOS 26.2, *) {
            return [HKCategoryType(.hypertensionEvent)]
        }
        return []
    }

    /// When the watch flagged possible hypertension, from `start` to now,
    /// oldest first. Empty before iOS 26.2, without a watch, or without
    /// permission.
    @concurrent
    func hypertensionEvents(since start: Date) async throws -> [Date] {
        guard isAvailable else { return [] }
        guard #available(iOS 26.2, *) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.hypertensionEvent), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store).map(\.startDate)
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }
    #else
    /// Hypertension notifications not enabled in this build (see the note above).
    static var hypertensionReadTypes: [HKObjectType] { [] }

    /// Hypertension notifications not enabled in this build: none to report.
    @concurrent
    func hypertensionEvents(since start: Date) async throws -> [Date] { [] }
    #endif
}
