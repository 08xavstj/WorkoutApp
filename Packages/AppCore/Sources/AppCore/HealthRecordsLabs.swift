import Foundation

/// Lab results from Apple Health Records: FHIR `Observation` resources (the
/// JSON in `HKClinicalRecord.fhirResource.data`) turned into results for the
/// `LabMarkers` catalog (docs/research/next-features-2026-11.md, I1).
///
/// Why: the blood-test schedule rests on strong guidance (Lp(a) once in
/// adults, Kronenberg 2022; lipids every 4-6 years from 20, ACC/AHA 2019;
/// HbA1c from 35, ADA 2026 and USPSTF 2021; see `BloodTestSchedule`), and
/// typing results in is a top reason people stop using health apps (Krebs &
/// Duncan 2015, carried in the research file). The import itself is plumbing:
/// no study tests it.
///
/// What it does:
/// - Reads FHIR R4 (and DSTU2, which has the same fields used here)
///   `Observation`s with a `valueQuantity`, or a `valueString` that holds a
///   number (eGFR ">60", Lp(a) "<10"; the marker's first unit when it names
///   none), dated by `effectiveDateTime`, then `effectivePeriod.start`, then
///   `issued`.
/// - A result reported only as a bound ("<10", ">60") is kept at the bound,
///   with a note. One whose bound lies past the range on its open side (a
///   "<x" above the high limit, a ">x" below the low limit) could be either
///   side of that limit, so it is left out (`Skip.boundOutsideRange`); Labs
///   has no field for bounds.
/// - Recognises the test by its LOINC code (`loincToMarker`). A result with
///   LOINC codes none of which are known is left out (it's a different test:
///   urine glucose, non-HDL, a ratio...). Only a result with no LOINC code at
///   all falls back to its printed name (`LabMarkers.match`).
/// - Keeps the lab's unit when the marker lists it, else converts to one the
///   marker uses (`convert`). Lp(a) mg/dL ↔ nmol/L is never converted: the
///   factor depends on the particle size (Kronenberg 2022, EAS consensus), so
///   such a result is left out rather than guessed.
/// - Uses the lab's reference range when the record has one, else the
///   catalog's typical range.
/// - Skips anything already in Labs: the same record, or the same marker on
///   the same day (or a day apart with a value within 5%), whoever typed it.
///
/// LOINC codes are from the LOINC table as remembered (not re-read this
/// round); the common panel codes are listed and anything else falls through
/// to "not recognised", which is the safe side.
public enum HealthRecordsLabs {
    /// One clinical record as HealthKit hands it over.
    public struct Record: Sendable, Equatable {
        /// `HKFHIRResource.identifier`, stable across reads. Unique only
        /// within its source: two clinics can both have an "obs-1".
        public var identifier: String
        /// `HKFHIRResource.sourceURL`: the FHIR server it came from.
        public var sourceURL: String?
        /// `HKFHIRResource.data`: the FHIR JSON.
        public var data: Data

        public init(identifier: String, sourceURL: String? = nil, data: Data) {
            self.identifier = identifier
            self.sourceURL = sourceURL
            self.data = data
        }

        /// The key a result is remembered by (`Imported.recordID`): source
        /// and identifier together; the identifier alone without a source.
        public var key: String {
            guard let sourceURL, !sourceURL.isEmpty else { return identifier }
            return sourceURL + "|" + identifier
        }
    }

    /// A result ready for Labs, in one of the marker's units.
    public struct Imported: Sendable, Equatable {
        public var recordID: String
        public var markerID: String
        public var name: String
        public var panel: String
        public var value: Double
        public var unit: String
        public var referenceLow: Double?
        public var referenceHigh: Double?
        public var date: Date
        /// A caveat to keep with the result ("Reported as < 10", "Not marked as fasting").
        public var note: String?
    }

    /// Why a record wasn't brought in.
    public enum Skip: String, Sendable, Equatable {
        case notObservation, notResulted, noValue, noDate, unknownTest, unconvertibleUnit, unreadable
        /// Reported only as "<x" with x above the high limit, or ">x" with x
        /// below the low limit: it could be either side of that limit.
        case boundOutsideRange
    }

    public enum Outcome: Sendable, Equatable {
        case result(Imported)
        case skipped(Skip)
    }

    /// A result already in Labs, typed or imported earlier.
    public struct Existing: Sendable, Equatable {
        public var markerID: String?
        public var value: Double
        public var unit: String
        public var date: Date
        public var recordID: String?

        public init(markerID: String?, value: Double, unit: String, date: Date, recordID: String? = nil) {
            self.markerID = markerID
            self.value = value
            self.unit = unit
            self.date = date
            self.recordID = recordID
        }
    }

    /// What an import found.
    public struct Summary: Sendable, Equatable {
        /// New results, oldest first.
        public var results: [Imported] = []
        /// Records that matched a result already in Labs.
        public var duplicates = 0
        /// Lab observations for tests the catalog doesn't track (or units it can't convert).
        public var notTracked = 0
        /// Tracked tests whose result has no number (a `valueString` such as
        /// "Negative", a coded value, or none).
        public var withoutNumber = 0
        /// Tracked tests reported only as a bound that leaves the flag in
        /// doubt (`Skip.boundOutsideRange`).
        public var boundsOnly = 0
        /// Records that weren't usable results at all (no value, cancelled, not an observation).
        public var other = 0
        /// Every record read, whatever happened to it.
        public var recordsRead = 0
    }

    // MARK: Import

    /// Parses `records`, keeps the catalog markers and drops duplicates of
    /// `existing` and of each other.
    public static func importable(_ records: [Record], existing: [Existing], sex: BiologicalSex,
                                  calendar: Calendar = .current) -> Summary {
        var summary = Summary()
        summary.recordsRead = records.count
        var known = existing
        let parsed = records.map { parse($0.data, recordID: $0.key, sex: sex, calendar: calendar) }
        // Oldest first, so a batch reads in report order.
        let results = parsed.compactMap { outcome -> Imported? in
            if case .result(let lab) = outcome { return lab }
            return nil
        }
        .sorted { $0.date < $1.date }
        for outcome in parsed {
            if case .skipped(let reason) = outcome {
                switch reason {
                case .unknownTest, .unconvertibleUnit: summary.notTracked += 1
                case .noValue: summary.withoutNumber += 1
                case .boundOutsideRange: summary.boundsOnly += 1
                default: summary.other += 1
                }
            }
        }
        for lab in results {
            if isDuplicate(lab, of: known, calendar: calendar) {
                summary.duplicates += 1
                continue
            }
            summary.results.append(lab)
            known.append(Existing(markerID: lab.markerID, value: lab.value, unit: lab.unit, date: lab.date, recordID: lab.recordID))
        }
        return summary
    }

    /// A typed result within this fraction of the imported one, a day apart,
    /// is the same test with the date typed as the report day (app's choice).
    static let nearbyDayTolerance = 0.05

    /// The same record, or the same marker on the same calendar day, or a
    /// day apart with a value within `nearbyDayTolerance`. A lab doesn't run
    /// the same marker twice in a day for a routine panel, so a same-day
    /// match counts whatever its value: the result already in Labs stays.
    public static func isDuplicate(_ lab: Imported, of existing: [Existing], calendar: Calendar = .current) -> Bool {
        existing.contains { other in
            if let id = other.recordID, id == lab.recordID { return true }
            guard other.markerID == lab.markerID else { return false }
            let day = calendar.startOfDay(for: lab.date)
            let otherDay = calendar.startOfDay(for: other.date)
            if day == otherDay { return true }
            let apart = abs(calendar.dateComponents([.day], from: otherDay, to: day).day ?? 99)
            guard apart <= 1 else { return false }
            let otherUnit = canonicalUnit(other.unit) ?? other.unit
            guard let comparable = convert(other.value, from: otherUnit, to: lab.unit, markerID: lab.markerID),
                  lab.value != 0 else { return false }
            return abs(comparable - lab.value) / abs(lab.value) <= nearbyDayTolerance
        }
    }

    // MARK: Parsing

    /// One FHIR resource, as a Labs result or the reason it isn't one.
    public static func parse(_ data: Data, recordID: String, sex: BiologicalSex, calendar: Calendar = .current) -> Outcome {
        guard let observation = try? JSONDecoder().decode(Observation.self, from: data) else { return .skipped(.unreadable) }
        guard observation.resourceType == nil || observation.resourceType == "Observation" else { return .skipped(.notObservation) }
        if let status = observation.status?.lowercased(), ignoredStatuses.contains(status) { return .skipped(.notResulted) }
        guard let date = [observation.effectiveDateTime, observation.effectivePeriod?.start, observation.effectiveInstant, observation.issued]
            .lazy.compactMap({ $0 }).compactMap({ parseDate($0, calendar: calendar) }).first else { return .skipped(.noDate) }
        // The test before the value, so "without a number" counts only tests Labs tracks.
        guard let match = markerMatch(observation.code) else { return .skipped(.unknownTest) }
        guard let marker = LabMarkers.marker(id: match.markerID) else { return .skipped(.unknownTest) }
        var unitNote: String?
        let quantity: Quantity
        if let valueQuantity = observation.valueQuantity, valueQuantity.value != nil {
            quantity = valueQuantity
        } else if let text = observation.valueString, var fromText = Self.quantity(fromString: text) {
            if fromText.unit == nil, let unit = marker.units.first?.unit {
                fromText.unit = unit
                unitNote = "No unit given; read as \(unit)"
            }
            quantity = fromText
        } else {
            return .skipped(.noValue)
        }
        guard let rawValue = quantity.value else { return .skipped(.noValue) }
        guard let unit = canonicalUnit(quantity.unit) ?? canonicalUnit(quantity.code) else { return .skipped(.unconvertibleUnit) }
        let markerUnits = marker.units.map(\.unit)
        let target = markerUnits.first { $0 == unit }
            ?? markerUnits.first { convert(rawValue, from: unit, to: $0, markerID: marker.id) != nil }
        guard let target, let value = convert(rawValue, from: unit, to: target, markerID: marker.id) else {
            return .skipped(.unconvertibleUnit)
        }

        // The lab's range, in the same unit as the value, else the catalog's.
        var low: Double?
        var high: Double?
        if let range = observation.referenceRange?.first {
            func converted(_ bound: Quantity?) -> Double? {
                guard let number = bound?.value else { return nil }
                let boundUnit = canonicalUnit(bound?.unit) ?? canonicalUnit(bound?.code) ?? unit
                return convert(number, from: boundUnit, to: target, markerID: marker.id)
            }
            low = converted(range.low)
            high = converted(range.high)
        }
        if low == nil && high == nil, let option = marker.units.first(where: { $0.unit == target }) {
            let typical = option.range(for: sex)
            low = typical.low
            high = typical.high
        }

        var notes: [String] = []
        if let comparator = quantity.comparator, !comparator.isEmpty {
            // "<x" above the high limit or ">x" below the low limit could be either
            // side of that limit, so it isn't stored as if it were x.
            switch comparator {
            case "<", "<=": if let high, value > high { return .skipped(.boundOutsideRange) }
            case ">", ">=": if let low, value < low { return .skipped(.boundOutsideRange) }
            default: break
            }
            notes.append("Reported as \(comparator) \(format(rawValue)) \(unit)")
        }
        if let unitNote { notes.append(unitNote) }
        if let note = match.note { notes.append(note) }
        return .result(Imported(
            recordID: recordID, markerID: marker.id, name: marker.name, panel: marker.panel,
            value: value, unit: target, referenceLow: low, referenceHigh: high, date: date,
            note: notes.isEmpty ? nil : notes.joined(separator: ". ")
        ))
    }

    /// FHIR statuses that carry no result (R4 ObservationStatus).
    static let ignoredStatuses: Set<String> = ["entered-in-error", "cancelled", "registered"]

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// A number in a `valueString`, with its comparator and unit if any:
    /// ">60", "<10", "< 0.3 mg/L", ">=90 mL/min/1.73m2", "5,4 %". Nil for
    /// text without a leading number ("Negative", "See note"). The unit is
    /// nil when the text names none.
    static func quantity(fromString text: String) -> Quantity? {
        let pattern = #"^\s*(<=|>=|≤|≥|<|>)?\s*([0-9]+(?:[.,][0-9]+)?)\s*(.*?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ index: Int) -> String? {
            guard let range = Range(found.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        guard let number = group(2).flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) else { return nil }
        var comparator = group(1)
        if comparator == "≤" { comparator = "<=" }
        if comparator == "≥" { comparator = ">=" }
        let unit = group(3).flatMap { $0.isEmpty ? nil : $0 }
        return Quantity(value: number, comparator: comparator, unit: unit, system: nil, code: nil)
    }

    // MARK: LOINC

    static let loincSystem = "http://loinc.org"

    /// LOINC code → catalog marker, with room for a caveat where a code is
    /// broader than the marker (none at present: broader codes are left out).
    public static let loincToMarker: [String: (markerID: String, note: String?)] = {
        var map: [String: (markerID: String, note: String?)] = [:]
        func add(_ id: String, _ codes: [String], note: String? = nil) {
            for code in codes { map[code] = (id, note) }
        }
        // Lipids: calculated, direct and molar LDL; HDL; total; triglycerides.
        add("ldl", ["13457-7", "18262-6", "2089-1", "22748-8", "39469-2"])
        add("hdl", ["2085-9", "14646-4"])
        add("totalCholesterol", ["2093-3", "14647-2"])
        add("triglycerides", ["2571-8", "14927-8"])
        add("apoB", ["1884-6"])
        add("lpa", ["10835-7", "43583-4"])
        // Blood sugar: HbA1c as % (NGSP) or mmol/mol (IFCC).
        add("hba1c", ["4548-4", "17856-6", "4549-2", "59261-8"])
        // Fasting glucose only. The general glucose codes (2345-7, 14749-6, 2339-0,
        // 15074-8) don't say the sample was fasting; mapped here, a random value
        // would set off the prediabetes rule and count as the screening test
        // (`BloodTestSchedule`), so they fall through as not recognised.
        add("glucose", ["1558-6", "14771-0"])
        add("ferritin", ["2276-4"])
        add("hemoglobin", ["718-7", "20509-6", "59260-0"])
        add("hematocrit", ["4544-3", "20570-8"])
        // Total 25(OH)D only: 1989-3 is 25(OH)D3 alone, which misses D2.
        add("vitaminD", ["62292-8", "35365-6"])
        add("b12", ["2132-9", "14685-2"])
        add("folate", ["2284-8", "14732-2"])
        add("tsh", ["3016-3", "11580-8", "11579-0"])
        add("testosterone", ["2986-8", "14913-8"])
        // hs-CRP only: 1988-5 is standard CRP, not sensitive enough below 3 mg/L
        // for the heart-risk bands the marker uses.
        add("crp", ["30522-7"])
        add("creatinine", ["2160-0", "14682-9", "38483-4"])
        // eGFR: MDRD, CKD-EPI and the 2021 race-free CKD-EPI equation.
        add("egfr", ["33914-3", "48642-3", "48643-1", "62238-1", "88293-6", "88294-4", "98979-8"])
        add("uricAcid", ["3084-1", "14933-6"])
        add("magnesium", ["19123-9", "2601-3"])
        add("alt", ["1742-6", "1743-4"])
        add("ast", ["1920-8", "30239-8"])
        return map
    }()

    /// The marker a FHIR `code` names: by LOINC when it has LOINC codes, by
    /// its printed name only when it has none.
    static func markerMatch(_ code: CodeableConcept?) -> (markerID: String, note: String?)? {
        let codings = code?.coding ?? []
        let loinc = codings.filter { ($0.system ?? "").lowercased().contains("loinc") }.compactMap(\.code)
        if !loinc.isEmpty {
            return loinc.lazy.compactMap { loincToMarker[$0] }.first
        }
        let names = [code?.text] + codings.map(\.display)
        for name in names.compactMap({ $0 }) where !name.lowercased().contains("urine") {
            if let marker = LabMarkers.match(name) { return (marker.id, nil) }
        }
        return nil
    }

    // MARK: Units

    /// Lab and UCUM spellings → the catalog's spelling. Nil for a unit the
    /// catalog doesn't use.
    public static func canonicalUnit(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var key = raw.lowercased()
        for (from, to) in [("μ", "u"), ("µ", "u"), ("mcg", "ug"), (" ", ""), ("{", ""), ("}", ""), ("[", ""), ("]", ""), ("_", ""), ("²", "2")] {
            key = key.replacingOccurrences(of: from, with: to)
        }
        return unitSpellings[key]
    }

    static let unitSpellings: [String: String] = [
        "mg/dl": "mg/dL", "mmol/l": "mmol/L", "g/dl": "g/dL", "g/l": "g/L", "mg/l": "mg/L",
        "ng/ml": "ng/mL", "ug/l": "µg/L", "ng/dl": "ng/dL", "pg/ml": "pg/mL",
        "nmol/l": "nmol/L", "pmol/l": "pmol/L", "umol/l": "µmol/L",
        "%": "%", "mmol/mol": "mmol/mol", "l/l": "L/L",
        "u/l": "U/L", "iu/l": "U/L",
        // TSH: µIU/mL is the same number as mIU/L.
        "miu/l": "mIU/L", "uiu/ml": "mIU/L", "mu/l": "mU/L",
        "ml/min/1.73m2": "mL/min/1.73m²", "ml/min/1.73": "mL/min/1.73m²", "ml/min": "mL/min",
    ]

    /// Mass concentration in g/L per unit.
    static let massPerLitre: [String: Double] = [
        "g/L": 1, "g/dL": 10, "mg/dL": 0.01, "mg/L": 0.001, "µg/L": 1e-6, "ng/mL": 1e-6, "ng/dL": 1e-8, "pg/mL": 1e-9,
    ]
    /// Molar concentration in mol/L per unit.
    static let molesPerLitre: [String: Double] = [
        "mmol/L": 1e-3, "µmol/L": 1e-6, "nmol/L": 1e-9, "pmol/L": 1e-12,
    ]

    /// Molar masses (g/mol) behind the usual clinical factors: cholesterol
    /// 386.65 (mg/dL = mmol/L × 38.67), triglycerides 885.7 (× 88.57), glucose
    /// 180.16 (× 18.0), creatinine 113.12 (µmol/L = mg/dL × 88.4), urate
    /// 168.11 (× 59.5), magnesium 24.305, 25(OH)D 400.64 (nmol/L = ng/mL ×
    /// 2.496), cobalamin 1355.4 (pmol/L = pg/mL × 0.738), folate 441.4 (×
    /// 2.266), testosterone 288.42 (nmol/L = ng/dL × 0.0347) and haemoglobin
    /// per haem (16,114; g/dL = mmol/L × 1.611). Standard SI conversion
    /// factors (from memory, the same ones lab reports print). Lp(a), ApoB,
    /// ferritin and CRP have none here: Lp(a) can't be converted reliably
    /// (Kronenberg 2022), and the others are reported by mass.
    static let molarMass: [String: Double] = [
        "ldl": 386.65, "hdl": 386.65, "totalCholesterol": 386.65, "triglycerides": 885.7,
        "glucose": 180.16, "creatinine": 113.12, "uricAcid": 168.11, "magnesium": 24.305,
        "vitaminD": 400.64, "b12": 1355.37, "folate": 441.4, "testosterone": 288.42, "hemoglobin": 16_114,
    ]

    /// `value` in `from` expressed in `to` for this marker, or nil when the
    /// two can't be converted.
    public static func convert(_ value: Double, from: String, to: String, markerID: String) -> Double? {
        if from == to { return value }
        // HbA1c: the IFCC-NGSP master equation, NGSP % = 0.0915 × IFCC + 2.15
        // (Hoelzel et al., Clin Chem 2004; from memory).
        if markerID == "hba1c" {
            switch (from, to) {
            case ("%", "mmol/mol"): return (value - 2.15) / 0.0915
            case ("mmol/mol", "%"): return value * 0.0915 + 2.15
            default: return nil
            }
        }
        if let a = massPerLitre[from], let b = massPerLitre[to] { return value * a / b }
        if let a = molesPerLitre[from], let b = molesPerLitre[to] { return value * a / b }
        let fractions: [String: Double] = ["%": 0.01, "L/L": 1]
        if markerID == "hematocrit", let a = fractions[from], let b = fractions[to] { return value * a / b }
        let sameNumber: Set<String> = ["mIU/L", "mU/L"]
        if sameNumber.contains(from), sameNumber.contains(to) { return value }
        let enzymes: Set<String> = ["U/L"]
        if enzymes.contains(from), enzymes.contains(to) { return value }
        if let mass = molarMass[markerID] {
            if let a = massPerLitre[from], let b = molesPerLitre[to] { return value * a / mass / b }
            if let a = molesPerLitre[from], let b = massPerLitre[to] { return value * a * mass / b }
        }
        return nil
    }

    // MARK: Dates

    /// FHIR dateTime: "2026", "2026-09", "2026-09-14" (dated at noon local,
    /// so the day doesn't shift with the time zone) or a full time with an offset.
    static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: text) { return date }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first, (1900...2200).contains(year) else { return nil }
        var components = DateComponents(year: year, month: parts.count > 1 ? parts[1] : 1, day: parts.count > 2 ? parts[2] : 1)
        components.hour = 12
        return calendar.date(from: components)
    }

    // MARK: FHIR shapes (the fields used here)

    struct Observation: Decodable {
        var resourceType: String?
        var id: String?
        var status: String?
        var code: CodeableConcept?
        var effectiveDateTime: String?
        var effectivePeriod: Period?
        var effectiveInstant: String?
        var issued: String?
        var valueQuantity: Quantity?
        var valueString: String?
        var referenceRange: [ReferenceRange]?
    }

    struct CodeableConcept: Decodable {
        var coding: [Coding]?
        var text: String?
    }

    struct Coding: Decodable {
        var system: String?
        var code: String?
        var display: String?
    }

    struct Period: Decodable {
        var start: String?
        var end: String?
    }

    struct Quantity: Decodable {
        var value: Double?
        var comparator: String?
        var unit: String?
        var system: String?
        var code: String?
    }

    struct ReferenceRange: Decodable {
        var low: Quantity?
        var high: Quantity?
        var text: String?
    }
}
