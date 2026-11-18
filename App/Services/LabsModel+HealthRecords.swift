import Foundation
import AppCore

/// Lab results from Apple Health Records (docs/research/next-features-2026-11.md,
/// I1). The clinical permission sheet is asked for only from Labs' "Import
/// from Health Records" button; until the person's clinic or lab is connected
/// in the Health app, the import finds nothing and says so. Imported results
/// are ordinary Labs results marked `.healthRecords`, so they feed the trends
/// and `BloodTestSchedule` like typed ones. Parsing, the LOINC map, units and
/// duplicate checks are in AppCore (`HealthRecordsLabs`).
extension LabsModel {
    /// What one import found, for the Labs card.
    struct HealthRecordsImport: Equatable {
        var added: Int
        var duplicates: Int
        var notTracked: Int
        var recordsRead: Int

        /// The card's line after an import.
        var text: String {
            if recordsRead == 0 { return Self.emptyText }
            var parts: [String] = []
            parts.append(added == 0 ? "No new results." : "Added \(added) result\(added == 1 ? "" : "s") from Health Records.")
            if duplicates > 0 { parts.append("\(duplicates) \(duplicates == 1 ? "was" : "were") already in Labs.") }
            if notTracked > 0 { parts.append("\(notTracked) other test\(notTracked == 1 ? "" : "s") that Labs doesn't track \(notTracked == 1 ? "was" : "were") left out.") }
            return parts.joined(separator: " ")
        }

        static let emptyText = "No lab results in Health Records yet. They appear here once your clinic or lab is connected in the Health app (Health › Health Records)."
    }

    /// Adds the new results among `records` and reports what it found.
    func importHealthRecords(_ records: [HealthRecordsLabs.Record], sex: BiologicalSex) -> HealthRecordsImport {
        reloadIfUnavailable()
        let existing = results.map {
            HealthRecordsLabs.Existing(markerID: $0.markerID, value: $0.value, unit: $0.unit, date: $0.date, recordID: $0.recordID)
        }
        let summary = HealthRecordsLabs.importable(records, existing: existing, sex: sex)
        let new = summary.results.map { lab in
            LabResult(name: lab.name, markerID: lab.markerID, value: lab.value, unit: lab.unit,
                      referenceLow: lab.referenceLow, referenceHigh: lab.referenceHigh, date: lab.date, panel: lab.panel,
                      notes: lab.note ?? "", source: .healthRecords, recordID: lab.recordID)
        }
        if !new.isEmpty { add(new) }
        return HealthRecordsImport(added: new.count, duplicates: summary.duplicates, notTracked: summary.notTracked,
                                   recordsRead: summary.recordsRead)
    }

    var importedCount: Int { results.filter(\.isFromHealthRecords).count }
}
