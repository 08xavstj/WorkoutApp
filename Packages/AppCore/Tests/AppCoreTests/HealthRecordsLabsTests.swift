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
        ("2160-0", "creatinine"), ("1742-6", "alt"), ("3016-3", "tsh"), ("62292-8", "vitaminD"),
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

    @Test func lipoproteinNamesAreNotTotalCholesterol() {
        // "cholesterol" is the longest alias in "Cholesterol, HDL", but it's HDL.
        #expect(LabMarkers.match("Cholesterol, HDL")?.id == "hdl")
        #expect(LabMarkers.match("Cholesterol in LDL")?.id == "ldl")
        #expect(LabMarkers.match("Cholesterol in VLDL") == nil)
        #expect(LabMarkers.match("Cholesterol, Total")?.id == "totalCholesterol")
        #expect(LabMarkers.match("Cholesterol")?.id == "totalCholesterol")
        #expect(parsed(observation(loinc: nil, display: "Cholesterol, HDL", value: 52, unit: "mg/dL"))?.markerID == "hdl")
    }

    @Test func onlyFastingGlucoseCodesAreRead() throws {
        let fasting = try #require(parsed(observation(loinc: "1558-6", value: 92, unit: "mg/dL")))
        #expect(fasting.markerID == "glucose")
        #expect(fasting.note == nil)
        #expect(parsed(observation(loinc: "14771-0", value: 5.1, unit: "mmol/L"))?.markerID == "glucose")
        // General glucose codes don't say fasting: a random 140 mg/dL must not
        // read as prediabetic fasting glucose or count as the screening test.
        for code in ["2345-7", "14749-6", "2339-0", "15074-8"] {
            #expect(skip(observation(loinc: code, value: 140, unit: "mg/dL")) == .unknownTest, "\(code)")
        }
    }

    @Test func standardCRPAndVitaminD3AloneAreNotRead() throws {
        #expect(parsed(observation(loinc: "30522-7", value: 1.2, unit: "mg/L"))?.markerID == "crp")
        #expect(skip(observation(loinc: "1988-5", value: 4, unit: "mg/L")) == .unknownTest)
        #expect(parsed(observation(loinc: "62292-8", value: 30, unit: "ng/mL"))?.markerID == "vitaminD")
        #expect(parsed(observation(loinc: "35365-6", value: 30, unit: "ng/mL"))?.markerID == "vitaminD")
        #expect(skip(observation(loinc: "1989-3", value: 30, unit: "ng/mL")) == .unknownTest)
    }

    @Test func comparatorIsKeptAsANote() throws {
        let lab = try #require(parsed(observation(loinc: "10835-7", value: 10, unit: "mg/dL", comparator: "<")))
        #expect(lab.value == 10)
        #expect(lab.note == "Reported as < 10 mg/dL")
    }

    @Test func boundsPastTheRangeAreSkipped() throws {
        // hs-CRP "< 5" against a high limit of 3 could be 1 or 4.
        #expect(skip(observation(loinc: "30522-7", value: 5, unit: "mg/L", comparator: "<")) == .boundOutsideRange)
        // eGFR "> 30" against a low limit of 60 could be 40 or 90.
        #expect(skip(observation(loinc: "98979-8", value: 30, unit: "mL/min/1.73m2", comparator: ">")) == .boundOutsideRange)
        // The lab's own range counts: "<= 8" with a high of 10 is in range.
        #expect(parsed(observation(loinc: "30522-7", value: 8, unit: "mg/L", high: 10, comparator: "<="))?.value == 8)
        // A bound on the far side of a limit leaves no doubt: TSH "< 0.01" is low.
        let tsh = try #require(parsed(observation(loinc: "3016-3", value: 0.01, unit: "mIU/L", comparator: "<")))
        #expect(LabMarkers.status(value: tsh.value, low: tsh.referenceLow, high: tsh.referenceHigh) == .low)
        // Without a comparator nothing changes.
        #expect(parsed(observation(loinc: "30522-7", value: 5, unit: "mg/L"))?.value == 5)
    }

    // MARK: valueString

    func stringObservation(loinc: String, _ text: String) throws -> Data {
        var json = try JSONSerialization.jsonObject(with: observation(loinc: loinc, value: 0, unit: "")) as! [String: Any]
        json["valueQuantity"] = nil
        json["valueString"] = text
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func valueStringNumbersAreRead() throws {
        // eGFR ">60" with no unit: the marker's first unit, at the bound, with notes.
        let egfr = try #require(parsed(try stringObservation(loinc: "98979-8", ">60")))
        #expect(egfr.value == 60)
        #expect(egfr.unit == "mL/min/1.73m²")
        #expect(egfr.note == "Reported as > 60 mL/min/1.73m². No unit given; read as mL/min/1.73m²")
        #expect(LabMarkers.status(value: egfr.value, low: egfr.referenceLow, high: egfr.referenceHigh) == .inRange)
        let lpa = try #require(parsed(try stringObservation(loinc: "10835-7", "<10")))
        #expect(lpa.value == 10)
        #expect(lpa.unit == "mg/dL")
        // With a unit, a space, and the "≤" sign.
        let crp = try #require(parsed(try stringObservation(loinc: "30522-7", "≤ 0.3 mg/L")))
        #expect(crp.value == 0.3)
        #expect(crp.unit == "mg/L")
        #expect(crp.note == "Reported as <= 0.3 mg/L")
        // A plain number with a comma decimal.
        let a1c = try #require(parsed(try stringObservation(loinc: "4548-4", "5,4 %")))
        #expect(a1c.value == 5.4)
        #expect(a1c.note == nil)
        // A unit Labs can't read is still left out, and a bound past the range too.
        #expect(skip(try stringObservation(loinc: "2276-4", "45 furlongs")) == .unconvertibleUnit)
        #expect(skip(try stringObservation(loinc: "98979-8", ">30")) == .boundOutsideRange)
        #expect(skip(try stringObservation(loinc: "4548-4", "Negative")) == .noValue)
    }

    @Test func resultsWithoutANumberAreCounted() throws {
        let records = [
            HealthRecordsLabs.Record(identifier: "a", data: try stringObservation(loinc: "4548-4", "See note")),
            HealthRecordsLabs.Record(identifier: "b", data: try stringObservation(loinc: "98979-8", ">60")),
            HealthRecordsLabs.Record(identifier: "c", data: try stringObservation(loinc: "30522-7", "<5")),
            // An untracked test without a number is "not tracked", not "without a number".
            HealthRecordsLabs.Record(identifier: "d", data: try stringObservation(loinc: "5792-7", "Negative")),
        ]
        let summary = HealthRecordsLabs.importable(records, existing: [], sex: .male, calendar: calendar)
        #expect(summary.results.map(\.markerID) == ["egfr"])
        #expect(summary.withoutNumber == 1)
        #expect(summary.boundsOnly == 1)
        #expect(summary.notTracked == 1)
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

    @Test func recordsAreKeyedBySourceAndIdentifier() {
        let data = observation(loinc: "2276-4", value: 110, unit: "ng/mL")
        let other = observation(loinc: "2276-4", value: 60, unit: "ng/mL", effective: "2025-03-01")
        // Two clinics, the same FHIR id: two results.
        let records = [
            HealthRecordsLabs.Record(identifier: "obs-1", sourceURL: "https://a.example/fhir", data: data),
            HealthRecordsLabs.Record(identifier: "obs-1", sourceURL: "https://b.example/fhir", data: other),
        ]
        let summary = HealthRecordsLabs.importable(records, existing: [], sex: .male, calendar: calendar)
        #expect(summary.results.count == 2)
        #expect(Set(summary.results.map(\.recordID)) == ["https://a.example/fhir|obs-1", "https://b.example/fhir|obs-1"])
        // An earlier import from the same source is still found by its key.
        let existing = [HealthRecordsLabs.Existing(markerID: "ferritin", value: 1, unit: "ng/mL", date: date(2020, 1, 1),
                                                   recordID: "https://a.example/fhir|obs-1")]
        let again = HealthRecordsLabs.importable(records, existing: existing, sex: .male, calendar: calendar)
        #expect(again.results.map(\.recordID) == ["https://b.example/fhir|obs-1"])
        #expect(again.duplicates == 1)
        // No source: the identifier alone.
        #expect(HealthRecordsLabs.Record(identifier: "x", data: data).key == "x")
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
