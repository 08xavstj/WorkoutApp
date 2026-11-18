import Foundation
import AppCore

/// Demo-mode stand-ins for the Health Records lab import, Apple's heart
/// events, walking speed, mindful minutes and waist readings from other apps
/// (`HealthKitClient+HealthRecords`, `HealthKitClient+HeartEventsAndMobility`),
/// so those screens have content in the Simulator. Made up, deterministic.
nonisolated extension DemoHealth {
    /// The demo's lab report day (as `DemoData.seedLabs`).
    static let labReportDaysAgo = 45

    /// FHIR record ids `DemoData` seeds as already imported, so Labs shows
    /// "From Health Records" rows and a second import finds them as duplicates.
    static let importedRecordIDs = ["demo-obs-apob", "demo-obs-lpa"]

    /// Health Records' FHIR R4 Observations for the demo report: two already
    /// in Labs from Health Records, two typed in by hand (LDL, HbA1c: the
    /// import skips them), and three new (TSH, eGFR, creatinine), plus a
    /// urine test the catalog doesn't track.
    func labResultRecords() -> [HealthRecordsLabs.Record] {
        let formatter = ISO8601DateFormatter()
        let when = formatter.string(from: day(Self.labReportDaysAgo).addingTimeInterval(8 * 3600 + 20 * 60))
        func record(_ id: String, loinc: String, display: String, value: Double, unit: String, low: Double? = nil, high: Double? = nil) -> HealthRecordsLabs.Record {
            var range = ""
            var bounds: [String] = []
            if let low { bounds.append("\"low\": {\"value\": \(low), \"unit\": \"\(unit)\"}") }
            if let high { bounds.append("\"high\": {\"value\": \(high), \"unit\": \"\(unit)\"}") }
            if !bounds.isEmpty { range = ", \"referenceRange\": [{\(bounds.joined(separator: ", "))}]" }
            let json = """
            {"resourceType": "Observation", "id": "\(id)", "status": "final",
             "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory"}]}],
             "code": {"coding": [{"system": "http://loinc.org", "code": "\(loinc)", "display": "\(display)"}], "text": "\(display)"},
             "effectiveDateTime": "\(when)",
             "valueQuantity": {"value": \(value), "unit": "\(unit)", "system": "http://unitsofmeasure.org", "code": "\(unit)"}\(range)}
            """
            return HealthRecordsLabs.Record(identifier: id, data: Data(json.utf8))
        }
        return [
            record("demo-obs-apob", loinc: "1884-6", display: "Apolipoprotein B", value: 96, unit: "mg/dL", high: 100),
            record("demo-obs-lpa", loinc: "43583-4", display: "Lipoprotein (a)", value: 38, unit: "nmol/L", high: 75),
            record("demo-obs-ldl", loinc: "13457-7", display: "LDL Cholesterol Calc", value: 112, unit: "mg/dL", high: 99),
            record("demo-obs-a1c", loinc: "4548-4", display: "Hemoglobin A1c", value: 5.3, unit: "%", high: 5.6),
            record("demo-obs-tsh", loinc: "3016-3", display: "TSH", value: 1.8, unit: "uIU/mL", low: 0.45, high: 4.5),
            record("demo-obs-egfr", loinc: "98979-8", display: "eGFR CKD-EPI 2021", value: 104, unit: "mL/min/{1.73_m2}", low: 60),
            record("demo-obs-creat", loinc: "2160-0", display: "Creatinine", value: 1.02, unit: "mg/dL", low: 0.76, high: 1.27),
            record("demo-obs-ua-glucose", loinc: "5792-7", display: "Glucose [Mass/volume] in Urine", value: 0, unit: "mg/dL"),
        ]
    }

    /// One high heart rate notification this month (an intense session), so the heart line shows.
    var heartEventCounts: HeartEvents.Counts { HeartEvents.Counts(high: 1, low: 0, irregular: 0) }

    /// iPhone walking speed around 1.35 m/s (4.9 km/h), most days, edging up
    /// over the months; m/s, oldest first.
    func walkingSpeedSeries(days: Int) -> [DatedValue] {
        (0..<min(days, historyDays + 1)).reversed().compactMap { daysAgo -> DatedValue? in
            guard daysAgo % 9 != 4 else { return nil } // phone left at home
            let value = 1.36 + 0.03 * Self.noise(daysAgo, 71) - 0.0006 * Double(daysAgo)
            return DatedValue(date: day(daysAgo), value: value)
        }
    }

    /// A 10-minute session in Apple's Mindfulness app on about one evening in three.
    func mindfulMinutesByDay(days: Int) -> [Date: Double] {
        var result: [Date: Double] = [:]
        guard days >= 1 else { return result }
        for daysAgo in 1...min(days, historyDays) where daysAgo % 3 == 1 {
            result[day(daysAgo)] = 10
        }
        return result
    }

    /// One waist reading another app wrote to Health, before the demo's typed ones.
    var healthWaistReadings: [WaistReadings.Reading] {
        [WaistReadings.Reading(date: day(120).addingTimeInterval(8 * 3600), centimeters: 90, fromHealth: true)]
    }
}
