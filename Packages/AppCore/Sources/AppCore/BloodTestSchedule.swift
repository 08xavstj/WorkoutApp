import Foundation

/// "Know your numbers": when the blood tests that matter most for heart and
/// metabolic risk are next due, from the results typed into Labs
/// (docs/research/evidence-audit-2026-11.md, Gaps, item 2).
///
/// Three checks, each with its own rule. Blood pressure has its own 7-day
/// home check (`HomeBloodPressure`) and is not repeated here.
///
/// - **Lipid panel, with ApoB.** Adults 20-39: "it is reasonable to assess
///   traditional ASCVD risk factors at least every 4 to 6 years" (2019
///   ACC/AHA primary prevention guideline, Arnett et al., Circulation
///   2019;140:e596, Section 2.2, COR IIa; full text read at PMC7734661). The
///   2026 ACC/AHA dyslipidemia guideline (Blumenthal et al., J Am Coll Cardiol
///   2026;87:2624, PMID 41824590; the record was checked, the wording comes
///   from a lab's summary, not re-verified) keeps "approximately every 5
///   years" for younger adults "with more frequent testing in higher-risk
///   individuals". The app uses 5 years, the middle of 4-6, from age 20, and
///   1 year when the last panel was flagged (a lipid above its range, or HDL
///   below): the 1 year is the app's choice; the guideline says only "more
///   frequent". ApoB is asked for with the panel: the 2026 guideline uses it
///   for residual risk (high triglycerides, diabetes), and it counts the
///   particles LDL-C estimates (Johannesen et al., JACC 2021, in `LabMarkers`).
/// - **Lp(a), once in life.** "Testing Lp(a) concentration at least once in
///   adults" (Kronenberg et al., EAS consensus, Eur Heart J 2022;43:3925,
///   PMID 36036785); "Lp(a) should be measured at least once in adulthood ...
///   repeat testing is generally not needed" (ACC press release for the 2026
///   guideline, read at acc.org). Once any result or test date is on file, it
///   is never due again.
/// - **HbA1c or fasting glucose.** ADA Standards of Care 2026 (Diabetes Care
///   2026;49 Suppl 1:S27, PMID 41358893, read at PMC12690183): Rec 2.12b
///   "for all other people, screening should begin at age 35 years"; 2.12c
///   repeat "at a minimum of 3-year intervals is reasonable"; people with
///   prediabetes (A1C ≥ 5.7% / 39 mmol/mol, fasting glucose 100-125 mg/dL /
///   5.6-6.9 mmol/L) "should be tested yearly". Rec 2.12a also tests adults of
///   any age with overweight and one or more risk factors; the app can't know
///   the risk factors, so before 35 it schedules nothing unless a result was
///   in the prediabetes range, and the text says a doctor may test earlier.
///   USPSTF 2021 (JAMA 2021;326:736, PMID 34427594) screens 35-70 with
///   overweight or obesity: the same starting age.
///
/// None of this is a diagnosis, and a doctor's plan always wins.
public enum BloodTestSchedule {
    public enum Check: String, CaseIterable, Codable, Sendable, Identifiable {
        case lipids, lpa, glucose

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .lipids: "Cholesterol panel with ApoB"
            case .lpa: "Lp(a)"
            case .glucose: "HbA1c or fasting glucose"
            }
        }

        /// `LabMarkers` ids whose results count as this check.
        public var markerIDs: Set<String> {
            switch self {
            case .lipids: ["ldl", "hdl", "totalCholesterol", "triglycerides", "apoB"]
            case .lpa: ["lpa"]
            case .glucose: ["hba1c", "glucose"]
            }
        }
    }

    /// Lipids every 5 years when normal (ACC/AHA 2019: at least every 4-6 years).
    public static let lipidYears = 5
    /// Lipids after a flagged panel: yearly (app's choice; 2026: "more frequent").
    public static let lipidRaisedYears = 1
    /// Lipid checks start at 20 (ACC/AHA 2019: adults 20 and over).
    public static let lipidStartAge = 20
    /// Lp(a) once, as an adult (EAS 2022; ACC/AHA 2026).
    public static let lpaStartAge = 18
    /// HbA1c or fasting glucose from 35 for everyone (ADA 2026 Rec 2.12b).
    public static let glucoseStartAge = 35
    /// Every 3 years when normal (ADA 2026 Rec 2.12c).
    public static let glucoseYears = 3
    /// Yearly in the prediabetes range (ADA 2026, Table 2.5).
    public static let glucoseRaisedYears = 1

    /// The ADA's prediabetes lines (Standards of Care 2026, Table 2.2), by unit.
    public static func inPrediabetesRange(markerID: String, value: Double, unit: String) -> Bool {
        switch (markerID, unit.lowercased()) {
        case ("hba1c", "%"): value >= 5.7
        case ("hba1c", "mmol/mol"): value >= 39
        case ("glucose", "mg/dl"): value >= 100
        case ("glucose", "mmol/l"): value >= 5.6
        default: false
        }
    }

    /// One result, as Labs holds it.
    public struct Result: Sendable, Equatable {
        public var markerID: String
        public var value: Double
        public var unit: String
        public var date: Date
        /// The lab's flag against its range (`LabMarkers.status`).
        public var status: LabMarkers.Status?

        public init(markerID: String, value: Double, unit: String, date: Date, status: LabMarkers.Status?) {
            self.markerID = markerID
            self.value = value
            self.unit = unit
            self.date = date
            self.status = status
        }
    }

    /// When one check is next due.
    public struct Due: Sendable, Equatable, Identifiable {
        public var check: Check
        /// The last result or typed-in test date; nil if never.
        public var lastTested: Date?
        /// Start of the day it falls due; nil when it never will (Lp(a) done).
        public var dueDate: Date?
        /// The last result was flagged, so the interval is the short one.
        public var raised: Bool
        /// No ApoB on file yet (lipids only): ask for it with the panel.
        public var askForApoB: Bool
        /// Due on or before today.
        public var isDue: Bool
        public var id: Check { check }

        /// "Every 5 years", "Yearly while it reads high", "Once in life".
        public var intervalText: String {
            switch check {
            case .lipids:
                raised ? "Yearly while a result reads outside the range" : "Every \(BloodTestSchedule.lipidYears) years"
            case .lpa:
                "Once in life"
            case .glucose:
                raised ? "Yearly while it's in the prediabetes range" : "Every \(BloodTestSchedule.glucoseYears) years from \(BloodTestSchedule.glucoseStartAge)"
            }
        }

        /// The one line Labs shows under the check's name.
        public var line: String {
            switch check {
            case .lpa:
                if lastTested != nil { return "Done. It's set by your genes, so once is enough." }
                return "Not on file. Worth testing once: it's genetic, and diet and training barely move it."
            case .lipids:
                let apoB = askForApoB ? " Ask for ApoB with it." : ""
                if lastTested == nil { return "Not on file. Due now.\(apoB)" }
                if isDue { return (raised ? "Due: last panel had a result outside the range." : "Due: last panel was over \(BloodTestSchedule.lipidYears) years ago.") + apoB }
                return raised ? "Next one sooner, as a result was outside the range.\(apoB)" : "Up to date.\(apoB)"
            case .glucose:
                if lastTested == nil { return "Not on file. Due now: from \(BloodTestSchedule.glucoseStartAge) every adult is checked." }
                if isDue { return raised ? "Due: yearly while it's in the prediabetes range." : "Due: last test was over \(BloodTestSchedule.glucoseYears) years ago." }
                return raised ? "In the prediabetes range last time, so yearly." : "Up to date."
            }
        }
    }

    /// The checks that apply at this age, each with its due date. A check
    /// that doesn't apply yet (glucose before 35 with nothing raised) is left out.
    /// - Parameters:
    ///   - results: every Labs result with a catalog marker.
    ///   - testedOn: test dates typed in without values ("I had it done in
    ///     March"), per check; used when newer than any result.
    public static func schedule(results: [Result], testedOn: [Check: Date] = [:], age: Int, now: Date = .now,
                                calendar: Calendar = .current) -> [Due] {
        let today = calendar.startOfDay(for: now)
        return Check.allCases.compactMap { check in
            let mine = results.filter { check.markerIDs.contains($0.markerID) }
            let lastResult = mine.map(\.date).max()
            let typed = testedOn[check]
            let last = [lastResult, typed].compactMap { $0 }.max()
            switch check {
            case .lpa:
                guard age >= lpaStartAge || last != nil else { return nil }
                return Due(check: check, lastTested: last, dueDate: last == nil ? today : nil, raised: false,
                           askForApoB: false, isDue: last == nil)
            case .lipids:
                guard age >= lipidStartAge || last != nil else { return nil }
                // The newest panel: results from the latest result day.
                let raised = latestDay(mine, calendar: calendar).contains { result in
                    result.markerID == "hdl" ? result.status == .low : result.status == .high
                }
                // A typed date newer than the results means a newer panel whose values aren't here.
                let raisedNow = raised && !typedIsNewer(typed, than: lastResult, calendar: calendar)
                let askForApoB = !mine.contains { $0.markerID == "apoB" }
                let due = dueDate(last: last, years: raisedNow ? lipidRaisedYears : lipidYears, today: today, calendar: calendar)
                return Due(check: check, lastTested: last, dueDate: due, raised: raisedNow, askForApoB: askForApoB, isDue: due <= today)
            case .glucose:
                let raised = latestDay(mine, calendar: calendar).contains {
                    inPrediabetesRange(markerID: $0.markerID, value: $0.value, unit: $0.unit) || $0.status == .high
                }
                let raisedNow = raised && !typedIsNewer(typed, than: lastResult, calendar: calendar)
                guard age >= glucoseStartAge || raisedNow else { return nil }
                let due = dueDate(last: last, years: raisedNow ? glucoseRaisedYears : glucoseYears, today: today, calendar: calendar)
                return Due(check: check, lastTested: last, dueDate: due, raised: raisedNow, askForApoB: false, isDue: due <= today)
            }
        }
    }

    /// The checks due on or before today, most important first (page order).
    public static func dueNow(_ schedule: [Due]) -> [Due] { schedule.filter(\.isDue) }

    /// "Lp(a) and a cholesterol panel are due", for one row elsewhere; nil when nothing is due.
    public static func summary(_ schedule: [Due]) -> String? {
        let due = dueNow(schedule)
        guard !due.isEmpty else { return nil }
        let names = due.map { $0.check == .lpa ? "Lp(a)" : ($0.check == .lipids ? "cholesterol panel" : "HbA1c") }
        let list: String
        switch names.count {
        case 1: list = names[0]
        case 2: list = "\(names[0]) and \(names[1])"
        default: list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        let text = list.prefix(1).uppercased() + list.dropFirst()
        return "\(text) \(due.count == 1 ? "is" : "are") due"
    }

    /// The results of the newest day with any result.
    static func latestDay(_ results: [Result], calendar: Calendar) -> [Result] {
        guard let newest = results.map(\.date).max() else { return [] }
        let day = calendar.startOfDay(for: newest)
        return results.filter { calendar.startOfDay(for: $0.date) == day }
    }

    /// A typed-in test date on a later day than the newest result: a newer
    /// test whose values aren't in the app, so the old flag no longer applies.
    static func typedIsNewer(_ typed: Date?, than result: Date?, calendar: Calendar) -> Bool {
        guard let typed else { return false }
        guard let result else { return true }
        return calendar.startOfDay(for: typed) > calendar.startOfDay(for: result)
    }

    /// `years` after the last test (start of day), or today if never tested.
    static func dueDate(last: Date?, years: Int, today: Date, calendar: Calendar) -> Date {
        guard let last else { return today }
        let start = calendar.startOfDay(for: last)
        return calendar.date(byAdding: .year, value: years, to: start) ?? start.addingTimeInterval(Double(years) * 365.25 * 86_400)
    }

    /// An unanswered reminder comes back once after this many days (app's
    /// choice, the same "one, then a long wait" as `OverdueReminder`).
    public static let reminderRepeatDays = 182
}
