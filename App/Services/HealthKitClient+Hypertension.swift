import Foundation
import HealthKit
import AppCore

// MARK: - Hypertension notification (iOS/watchOS 26.2)
//
// `HKCategoryTypeIdentifier.hypertensionEvent` (iOS/watchOS 26.2), confirmed
// in the iOS 27.2 SDK's HealthKit headers (HKTypeIdentifiers.h: "HKCategory-
// TypeIdentifierHypertensionEvent API_AVAILABLE(ios(26.2) …)", printed by the
// SDK probe workflow, 19 Nov 2026). Its samples carry no value enum, so any
// sample is treated as one notification. Before iOS 26.2 nothing is read and
// `hypertensionEvents(since:)` returns [].
//
// What the watch does: Series 9+/Ultra 2+ review 30 days of optical data and
// notify on consistent signs of hypertension; validation against 30-day home
// blood pressure found sensitivity 41%, specificity 92% (refs B1-B3; the
// figures live in `HomeBloodPressure`).
nonisolated extension HealthKitClient {
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
}
