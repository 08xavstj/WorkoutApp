import Foundation
import HealthKit
import AppCore

// MARK: - Lab results from Apple Health Records (I1)
//
// Clinical records are read-only and need the Clinical Health Records
// capability (`com.apple.developer.healthkit.access: [health-records]`), an
// `NSHealthClinicalHealthRecordsShareUsageDescription` and a privacy policy
// (developer.apple.com, "Accessing health records";
// docs/research/next-features-2026-11.md, I1, A9). They are NOT in the
// main `readTypes`: the clinical sheet is asked for only when the person taps
// "Import from Health Records" in Labs, so nobody sees it before their
// clinic or lab is connected. Parsing and the LOINC map are in AppCore
// (`HealthRecordsLabs`). Nothing leaves the iPhone.
nonisolated extension HealthKitClient {
    /// The lab-result record type (iOS 12+).
    static var labResultType: HKClinicalType? {
        HKObjectType.clinicalType(forIdentifier: .labResultRecord)
    }

    /// Whether this iPhone can hold Health Records at all (iOS 12+; false
    /// where Apple doesn't offer them). Demo mode says yes, so the button shows.
    var supportsHealthRecords: Bool {
        if DemoHealth.active != nil { return true }
        return isAvailable && store.supportsHealthRecords()
    }

    /// Shows the clinical-records permission sheet (lab results only). It
    /// is a separate sheet from the main one, asked for from Labs only.
    @concurrent
    func requestHealthRecordsAccess() async throws {
        if DemoHealth.active != nil { return }
        guard supportsHealthRecords, let type = Self.labResultType else { return }
        try await store.requestAuthorization(toShare: Set<HKSampleType>(), read: [type])
    }

    /// Every lab-result record's FHIR JSON, as AppCore values. Empty with no
    /// records, no permission (HealthKit doesn't say which) or no support.
    @concurrent
    func labResultRecords() async throws -> [HealthRecordsLabs.Record] {
        if let demo = DemoHealth.active { return demo.labResultRecords() }
        guard supportsHealthRecords, let type = Self.labResultType else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error {
                    if let healthError = error as? HKError, healthError.code == .errorNoData {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let records = (samples ?? []).compactMap { sample -> HealthRecordsLabs.Record? in
                    guard let record = sample as? HKClinicalRecord, let resource = record.fhirResource,
                          resource.resourceType == .observation else { return nil }
                    return HealthRecordsLabs.Record(identifier: resource.identifier, data: resource.data)
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }
}
