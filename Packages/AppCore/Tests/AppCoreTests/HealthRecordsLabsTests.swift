import Foundation
import Testing
@testable import AppCore

struct HealthRecordsLabsTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A FHIR R4 Observation as Health Records stores it.
    func observation(loinc: String?, display: String = "Test", value: Double, unit: String, ucum: String? = nil,
                     effective: String? = "2026-09-14T08:30:00-04:00", status: String = "final",
                     low: Double? = nil, high: Double? = nil, comparator: String? = nil, text: String? = nil) -> Data {
        var coding: [[String: Any]] = []
        if let loinc { coding.append(["system": "http://loinc.org", "code": loinc, "display": display]) }
        var quantity: [String: Any] = ["value": value, "unit": unit, "system": "http://unitsofmeasure.org", "code": ucum ?? unit]
        if let comparator { quantity["comparator"] = comparator }
        var json: [String: Any] = [
            "resourceType": "Observation",
            "id": UUID().uuidString,
            "status": status,
            "category": [["coding": [["system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory"]]]],
            "code": ["coding": coding, "text": text ?? display],
            "valueQuantity": quantity,
        ]
        if let effective { json["effectiveDateTime"] = effective }
        var range: [String: Any] = [:]
        if let low { range["low"] = ["value": low, "unit": unit] }
        if let high { range["high"] = ["value": high, "unit": unit] }
        if !range.isEmpty { json["referenceRange"] = [range] }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func parsed(_ data: Data, sex: BiologicalSex = .male) -> HealthRecordsLabs.Imported? {
        if case .result(let lab) = HealthRecordsLabs.parse(data, recordID: "r1", sex: sex, calendar: calendar) { return lab }
        return nil
    }

    func skip(_ data: Data) -> HealthRecordsLabs.Skip? {
        if case .skipped(let reason) = HealthRecordsLabs.parse(data, recordID: "r1", sex: .male, calendar: calendar) { return reason }
        return nil
    }

    // MARK: Parsing

    @Test func ldlWithLabRangeAndDateIsRead() throws {
        let lab = try #require(parsed(observation(loinc: "13457-7", display: "LDL Cholesterol Calc", value: 112, unit: "mg/dL", high: 99)))
        #expect(lab.markerID == "ldl")
        #expect(lab.name == "LDL cholesterol")
        #expect(lab.panel == "Lipids")
        #expect(lab.value == 112)
        #expect(lab.unit == "mg/dL")
        #expect(lab.referenceHigh == 99)
        #expect(lab.referenceLow == nil)
        // 08:30 at −04:00 is 12:30 UTC on the same day.
        #expect(lab.date == date(2026, 9, 14, hour: 12).addingTimeInterval(30 * 60))
    }

    @Test func catalogRangeFillsInWhenTheRecordHasNone() throws {
        let lab = try #require(parsed(observation(loinc: "2085-9", value: 48, unit: "mg/dL"), sex: .female))
        #expect(lab.markerID == "hdl")
        #expect(lab.referenceLow == 50)
    }

    @Test func everyListedMarkerHasALoincCode() {
        let mapped = Set(HealthRecordsLabs.loincToMarker.values.map(\.markerID))
        for marker in LabMarkers.all {
            #expect(mapped.contains(marker.id), "no LOINC code for \(marker.id)")
        }
        // And every code points at a real marker.
        for (code, target) in HealthRecordsLabs.loincToMarker {
            #expect(LabMarkers.marker(id: target.markerID) != nil, "\(code) → \(target.markerID)")
        }
    }

    @Test(arguments: [
        ("2093-3", "totalCholesterol"), ("2571-8", "triglycerides"), ("1884-6", "apoB"), ("10835-7", "lpa"),
        ("4548-4", "hba1c"), ("1558-6", "glucose"), ("2276-4", "ferritin"), ("98979-8", "egfr"),
        ("2160-0", "creatinine"), ("1742-6", "alt"), ("3016-3", "tsh"), ("1989-3", "vitaminD"),
        ("2132-9", "b12"), ("718-7", "hemoglobin"),
    ])
    func loincCodesMapToMarkers(code: String, marker: String) {
        #expect(HealthRecordsLabs.loincToMarker[code]?.markerID == marker)
    }

    @Test func ucumCodeIsUsedWhenTheUnitTextIsMissing() throws {
        let lab = try #require(parsed(observation(loinc: "98979-8", value: 94, unit: "", ucum: "mL/min/{1.73_m2}")))
        #expect(lab.markerID == "egfr")
        #expect(lab.unit == "mL/min/1.73m²")
    }

    @Test func dateOnlyIsDatedAtNoonOnThatDay() throws {
        let lab = try #require(parsed(observation(loinc: "4548-4", value: 5.4, unit: "%", effective: "2026-03-02")))
        #expect(lab.date == date(2026, 3, 2))
    }

    @Test func fractionalSecondsAndZuluParse() throws {
        let lab = try #require(parsed(observation(loinc: "4548-4", value: 5.4, unit: "%", effective: "2026-03-02T07:15:00.000Z")))
        #expect(lab.date == date(2026, 3, 2, hour: 7).addingTimeInterval(15 * 60))
    }

    @Test func issuedIsTheLastDateFallback() throws {
        var json = try JSONSerialization.jsonObject(with: observation(loinc: "4548-4", value: 5.4, unit: "%", effective: nil)) as! [String: Any]
        json["issued"] = "2026-05-01T10:00:00Z"
        let lab = try #require(parsed(try JSONSerialization.data(withJSONObject: json)))
        #expect(lab.date == date(2026, 5, 1, hour: 10))
    }

    @Test func noDateNoValueOrCancelledAreSkipped() throws {
        #expect(skip(observation(loinc: "4548-4", value: 5.4, unit: "%", effective: nil)) == .noDate)
        #expect(skip(observation(loinc: "4548-4", value: 5.4, unit: "%", status: "entered-in-error")) == .notResulted)
        #expect(skip(observation(loinc: "4548-4", value: 5.4, unit: "%", status: "cancelled")) == .notResulted)
        var json = try JSONSerialization.jsonObject(with: observation(loinc: "4548-4", value: 5.4, unit: "%")) as! [String: Any]
        json["valueQuantity"] = nil
        json["valueString"] = "See note"
        #expect(skip(try JSONSerialization.data(withJSONObject: json)) == .noValue)
        #expect(skip(Data("not json".utf8)) == .unreadable)
        let condition = try JSONSerialization.data(withJSONObject: ["resourceType": "Condition", "id": "c1"])
        #expect(skip(condition) == .notObservation)
    }

    @Test func unknownLoincCodeIsNotGuessedFromItsName() {
        // Glucose in urine (5792-7) shares a word with the blood test but isn't it.
        #expect(skip(observation(loinc: "5792-7", display: "Glucose [Mass/volume] in Urine", value: 0, unit: "mg/dL")) == .unknownTest)
        // Non-HDL cholesterol (43396-1) isn't LDL or HDL.
        #expect(skip(observation(loinc: "43396-1", display: "Cholesterol non HDL", value: 140, unit: "mg/dL")) == .unknownTest)
    }

    @Test func noLoincFallsBackToTheName() throws {
        let lab = try #require(parsed(observation(loinc: nil, display: "Ferritin", value: 80, unit: "ng/mL")))
        #expect(lab.markerID == "ferritin")
        #expect(skip(observation(loinc: nil, display: "Glucose, urine", value: 0, unit: "mg/dL")) == .unknownTest)
    }

    @Test func nonFastingGlucoseCarriesANote() throws {
        let fasting = try #require(parsed(observation(loinc: "1558-6", value: 92, unit: "mg/dL")))
        #expect(fasting.note == nil)
        let random = try #require(parsed(observation(loinc: "2345-7", value: 92, unit: "mg/dL")))
        #expect(random.markerID == "glucose")
        #expect(random.note == "Not marked as fasting by the lab")
    }

    @Test func comparatorIsKeptAsANote() throws {
        let lab = try #require(parsed(observation(loinc: "10835-7", value: 10, unit: "mg/dL", comparator: "<")))
        #expect(lab.value == 10)
        #expect(lab.note == "Reported as < 10 mg/dL")
    }

    // MARK: Units

    @Test func markerUnitsAreKeptAsTheLabSentThem() throws {
        let ldl = try #require(parsed(observation(loinc: "13457-7", value: 2.9, unit: "mmol/L", high: 2.6)))
        #expect(ldl.unit == "mmol/L")
        #expect(ldl.value == 2.9)
        #expect(ldl.referenceHigh == 2.6)
        let ferritin = try #require(parsed(observation(loinc: "2276-4", value: 45, unit: "ug/L")))
        #expect(ferritin.unit == "µg/L")
        let tsh = try #require(parsed(observation(loinc: "3016-3", value: 1.9, unit: "uIU/mL")))
        #expect(tsh.unit == "mIU/L")
        #expect(tsh.value == 1.9)
    }

    @Test func otherUnitsAreConvertedWithTheirRange() throws {
        // ApoB in mg/L isn't a catalog unit: 950 mg/L = 95 mg/dL.
        let apoB = try #require(parsed(observation(loinc: "1884-6", value: 950, unit: "mg/L", high: 1000)))
        #expect(apoB.unit == "mg/dL")
        #expect(abs(apoB.value - 95) < 0.001)
        #expect(abs((apoB.referenceHigh ?? 0) - 100) < 0.001)
        // hs-CRP in mg/dL stays; in g/L converts to mg/L.
        let crp = try #require(parsed(observation(loinc: "30522-7", value: 0.0012, unit: "g/L")))
        #expect(crp.unit == "mg/L")
        #expect(abs(crp.value - 1.2) < 0.0001)
    }

    @Test func massAndMolarConversionsMatchTheClinicalFactors() throws {
        func convert(_ value: Double, _ from: String, _ to: String, _ marker: String) throws -> Double {
            try #require(HealthRecordsLabs.convert(value, from: from, to: to, markerID: marker))
        }
        #expect(abs(try convert(3.0, "mmol/L", "mg/dL", "ldl") - 116.0) < 0.1)
        #expect(abs(try convert(1.7, "mmol/L", "mg/dL", "triglycerides") - 150.6) < 0.2)
        #expect(abs(try convert(5.5, "mmol/L", "mg/dL", "glucose") - 99.1) < 0.2)
        #expect(abs(try convert(1.0, "mg/dL", "µmol/L", "creatinine") - 88.4) < 0.1)
        #expect(abs(try convert(20, "ng/mL", "nmol/L", "vitaminD") - 49.9) < 0.1)
        #expect(abs(try convert(400, "pg/mL", "pmol/L", "b12") - 295.1) < 0.5)
        #expect(abs(try convert(500, "ng/dL", "nmol/L", "testosterone") - 17.3) < 0.1)
        #expect(abs(try convert(9.0, "mmol/L", "g/dL", "hemoglobin") - 14.5) < 0.1)
        #expect(abs(try convert(0.45, "L/L", "%", "hematocrit") - 45) < 0.001)
    }

    @Test func hbA1cUsesTheMasterEquation() throws {
        let ifcc = try #require(HealthRecordsLabs.convert(5.7, from: "%", to: "mmol/mol", markerID: "hba1c"))
        #expect(abs(ifcc - 38.8) < 0.3)
        let ngsp = try #require(HealthRecordsLabs.convert(48, from: "mmol/mol", to: "%", markerID: "hba1c"))
        #expect(abs(ngsp - 6.5) < 0.05)
        // "%" is not a volume fraction for HbA1c.
        #expect(HealthRecordsLabs.convert(5.7, from: "%", to: "L/L", markerID: "hba1c") == nil)
    }

    @Test func lpaIsNeverConvertedBetweenMassAndMoles() {
        #expect(HealthRecordsLabs.convert(50, from: "mg/dL", to: "nmol/L", markerID: "lpa") == nil)
        // A catalog unit is kept, so both arrive as sent.
        #expect(parsed(observation(loinc: "43583-4", value: 140, unit: "nmol/L"))?.unit == "nmol/L")
        // Molar to molar is fine: 0.14 µmol/L is 140 nmol/L.
        let molar = parsed(observation(loinc: "43583-4", value: 0.14, unit: "umol/L"))
        #expect(molar?.unit == "nmol/L")
        #expect(abs((molar?.value ?? 0) - 140) < 0.001)
    }

    @Test func unknownUnitsAreSkipped() {
        #expect(skip(observation(loinc: "2276-4", value: 45, unit: "furlongs")) == .unconvertibleUnit)
    }

    // MARK: Duplicates

    @Test func sameRecordOrSameDayIsADuplicate() {
        let records = [
            HealthRecordsLabs.Record(identifier: "a", data: observation(loinc: "13457-7", value: 112, unit: "mg/dL")),
            HealthRecordsLabs.Record(identifier: "b", data: observation(loinc: "4548-4", value: 5.3, unit: "%")),
            HealthRecordsLabs.Record(identifier: "c", data: observation(loinc: "2276-4", value: 110, unit: "ng/mL")),
            HealthRecordsLabs.Record(identifier: "d", data: observation(loinc: "5792-7", value: 0, unit: "mg/dL")),
        ]
        let existing = [
            // Typed in by hand the same day, in the other unit.
            HealthRecordsLabs.Existing(markerID: "ldl", value: 2.9, unit: "mmol/L", date: date(2026, 9, 14, hour: 9)),
            // Imported before.
            HealthRecordsLabs.Existing(markerID: "hba1c", value: 5.3, unit: "%", date: date(2026, 9, 14), recordID: "b"),
        ]
        let summary = HealthRecordsLabs.importable(records, existing: existing, sex: .male, calendar: calendar)
        #expect(summary.results.map(\.markerID) == ["ferritin"])
        #expect(summary.duplicates == 2)
        #expect(summary.notTracked == 1)
        #expect(summary.recordsRead == 4)
    }

    @Test func aDayApartNeedsTheSameValue() {
        let records = [HealthRecordsLabs.Record(identifier: "a", data: observation(loinc: "13457-7", value: 112, unit: "mg/dL"))]
        // Typed as the report day, the next morning, in mmol/L (2.9 ≈ 112 mg/dL).
        let same = [HealthRecordsLabs.Existing(markerID: "ldl", value: 2.9, unit: "mmol/L", date: date(2026, 9, 15))]
        #expect(HealthRecordsLabs.importable(records, existing: same, sex: .male, calendar: calendar).results.isEmpty)
        let different = [HealthRecordsLabs.Existing(markerID: "ldl", value: 140, unit: "mg/dL", date: date(2026, 9, 15))]
        #expect(HealthRecordsLabs.importable(records, existing: different, sex: .male, calendar: calendar).results.count == 1)
        let weekLater = [HealthRecordsLabs.Existing(markerID: "ldl", value: 112, unit: "mg/dL", date: date(2026, 9, 21))]
        #expect(HealthRecordsLabs.importable(records, existing: weekLater, sex: .male, calendar: calendar).results.count == 1)
    }

    @Test func aRecordListedTwiceInOneReadIsAddedOnce() {
        let data = observation(loinc: "2276-4", value: 110, unit: "ng/mL")
        let records = [HealthRecordsLabs.Record(identifier: "a", data: data), HealthRecordsLabs.Record(identifier: "a", data: data)]
        let summary = HealthRecordsLabs.importable(records, existing: [], sex: .male, calendar: calendar)
        #expect(summary.results.count == 1)
        #expect(summary.duplicates == 1)
    }

    @Test func resultsComeOldestFirst() {
        let records = [
            HealthRecordsLabs.Record(identifier: "new", data: observation(loinc: "2276-4", value: 90, unit: "ng/mL", effective: "2026-10-01")),
            HealthRecordsLabs.Record(identifier: "old", data: observation(loinc: "2276-4", value: 60, unit: "ng/mL", effective: "2025-10-01")),
        ]
        let summary = HealthRecordsLabs.importable(records, existing: [], sex: .male, calendar: calendar)
        #expect(summary.results.map(\.recordID) == ["old", "new"])
    }

    @Test func importedResultsFeedTheBloodTestSchedule() throws {
        let records = [
            HealthRecordsLabs.Record(identifier: "a", data: observation(loinc: "13457-7", value: 95, unit: "mg/dL", effective: "2026-09-14", high: 99)),
            HealthRecordsLabs.Record(identifier: "b", data: observation(loinc: "10835-7", value: 20, unit: "mg/dL", effective: "2026-09-14")),
        ]
        let summary = HealthRecordsLabs.importable(records, existing: [], sex: .male, calendar: calendar)
        let results = summary.results.map {
            BloodTestSchedule.Result(markerID: $0.markerID, value: $0.value, unit: $0.unit, date: $0.date,
                                     status: LabMarkers.status(value: $0.value, low: $0.referenceLow, high: $0.referenceHigh))
        }
        let due = BloodTestSchedule.schedule(results: results, testedOn: [:], age: 34, now: date(2026, 11, 18), calendar: calendar)
        let lpa = try #require(due.first { $0.check == .lpa })
        #expect(lpa.isDue == false)
        let lipids = try #require(due.first { $0.check == .lipids })
        #expect(lipids.isDue == false)
    }
}
