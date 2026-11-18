import Foundation

/// The functional test pack in the yearly fitness check
/// (docs/research/next-features-2026-11.md, I4 and §4c): push-ups to
/// failure, the sitting-rising test from 45 and the 10-second one-leg stand
/// from 50. Abstracts re-read at PubMed on 18 Nov 2026 (PMIDs below).
///
/// Every figure here comes from one cohort, so each line says "linked with,
/// in one cohort": a test doesn't change health by itself, and none of these
/// studies shows that improving the score lowers risk. Their use is a yearly
/// trend that can catch a decline early. Only the cut-offs the papers report
/// are used; where a paper reports none for someone (push-ups for women), the
/// app shows the count and its trend and says why there is no comparison.
public enum FunctionalTest: String, Codable, Sendable, CaseIterable, Identifiable {
    case pushUps, sittingRising, oneLegStand
    public var id: String { rawValue }

    // MARK: Evidence

    /// Yang et al., JAMA Netw Open 2019;2:e188341 (PMID 30768197): 1,104
    /// male firefighters aged 18+, mean age 39.6, followed 10 years; 37 CVD
    /// events in all. More than 40 push-ups vs fewer than 10: IRR 0.04 (95% CI
    /// 0.01-0.36), adjusted for age and BMI. Five count groups; only the two
    /// ends are given in the abstract, so only those two are used.
    public static let pushUpTopGroupAbove = 40
    public static let pushUpLowestGroupBelow = 10
    public static let pushUpIRR = 0.04

    /// Araújo et al., Eur J Prev Cardiol 2026;33:2170-8 (PMID 40569873):
    /// 4,282 adults aged 46-75 (68% men), median follow-up 12.3 years. Groups
    /// 0-4, 4.5-7.5, 8, 8.5-9.5 and 10; death rates 42.1%, 20.4%, 11.1%, 7.0%
    /// and 3.7%. Lowest vs highest group: HR 3.84 for natural death and 6.05
    /// for cardiovascular death, adjusted for age, sex, BMI and clinical
    /// variables. Brito et al. 2014 (record only) first tied it to all-cause
    /// mortality.
    public static let sittingRisingGroups: [ClosedRange<Double>] = [0...4, 4.5...7.5, 8...8, 8.5...9.5, 10...10]
    /// Death rates by group, lowest group first (Araújo 2026).
    public static let sittingRisingDeathRates = [42.1, 20.4, 11.1, 7.0, 3.7]
    public static let sittingRisingNaturalDeathHR = 3.84
    public static let sittingRisingCVDeathHR = 6.05

    /// Araujo et al., Br J Sports Med 2022;56:975-80 (PMID 35728834): 1,702
    /// adults aged 51-75 (68% men), median follow-up 7 years. 20.4% couldn't
    /// stand 10 s on one leg; 17.5% of them died vs 4.6% of those who could.
    /// Adjusted HR 1.84 (95% CI 1.23-2.78) for all-cause mortality.
    public static let oneLegStandUnableHR = 1.84
    public static let oneLegStandSeconds = 10

    /// The ages each cohort covered. Nil for push-ups: the abstract gives
    /// "18 years or older", mean 39.6, without an upper limit.
    public var cohortAges: ClosedRange<Int>? {
        switch self {
        case .pushUps: nil
        case .sittingRising: 46...75
        case .oneLegStand: 51...75
        }
    }

    /// The youngest age the app shows a test at. The research doc's choice:
    /// the sitting-rising test from 45 and the one-leg stand from 50, a year
    /// below each cohort's youngest member; push-ups for every adult.
    public var minimumAge: Int {
        switch self {
        case .pushUps: 18
        case .sittingRising: 45
        case .oneLegStand: 50
        }
    }

    /// Repeat yearly: the research doc's "Yearly, manual" (§4c). App's choice;
    /// none of the cohorts tested a cadence.
    public static let intervalDays = 365

    /// The tests to show at this age.
    public static func available(age: Int) -> [FunctionalTest] {
        allCases.filter { age >= $0.minimumAge }
    }

    // MARK: Words

    public var title: String {
        switch self {
        case .pushUps: "Push-ups to failure"
        case .sittingRising: "Sitting-rising test"
        case .oneLegStand: "10-second one-leg stand"
        }
    }

    public var citation: String {
        switch self {
        case .pushUps: "Yang et al., JAMA Netw Open 2019 (one cohort of 1,104 men)"
        case .sittingRising: "Araújo et al., Eur J Prev Cardiol 2026; Brito et al., 2014 (one cohort, ages 46-75)"
        case .oneLegStand: "Araujo et al., Br J Sports Med 2022 (one cohort, ages 51-75)"
        }
    }

    /// The protocol in plain words. Push-ups: the paper's metronome pace (80
    /// beats a minute) is from secondary descriptions and wasn't re-verified,
    /// so the app says "a steady pace". Sitting-rising: the scoring is the
    /// abstract's (one point off 5 for each hand or knee support, half a point
    /// for an unsteady movement, sitting plus rising). One-leg stand: 10
    /// seconds without support, as the abstract; the foot position and three
    /// attempts are from the published protocol's descriptions, not re-verified.
    public var steps: [String] {
        switch self {
        case .pushUps: [
            "Warm up for a few minutes first. Hands just wider than your shoulders, body straight from head to heels.",
            "Lower until your chest is about a fist above the floor, then push back to straight arms. That's one.",
            "Keep a steady pace, about one every two seconds, and count every full repetition.",
            "Stop when you can't do another with good form, or when your hips sag or you pause to rest. That count is your result.",
            "Do it the same way each year: rested, not after a hard upper-body day.",
        ]
        case .sittingRising: [
            "Clear a space on a non-slip floor. Wear comfortable clothes, no shoes and socks off.",
            "From standing, cross your legs and lower yourself to sit on the floor, using as little support as you can.",
            "Then stand back up the same way, again using as little support as you can.",
            "Each part starts at 5 points. Take 1 point off for each hand, forearm, knee or side of a leg you put down (or a hand on your knee), and half a point if you wobble or lose your balance.",
            "Add the two parts for a score out of 10. Having someone watch, or filming it, makes the count easier.",
        ]
        case .oneLegStand: [
            "Stand next to a wall or the back of a chair, in case you need to catch yourself.",
            "Lift one foot and rest its front against the back of the other lower leg. Arms by your sides, eyes straight ahead.",
            "Hold for 10 seconds without touching anything. You have up to three tries, on either leg.",
            "Your result is whether you held it for the full 10 seconds.",
        ]
        }
    }

    /// When not to do the test, and when to stop (the app's precautions; the
    /// cohorts excluded people with relevant limitations, Araújo 2026).
    public var safety: String {
        switch self {
        case .pushUps:
            "Skip it with a shoulder, elbow or wrist injury, or if your doctor has told you to avoid hard straining. Stop at once with chest pain, dizziness or unusual breathlessness."
        case .sittingRising:
            "Skip it with a hip or knee replacement, recent hip, knee or back injury, or if you can't get up from the floor safely. Have someone nearby if you're unsure of your balance. Stop if anything hurts."
        case .oneLegStand:
            "Do it beside a wall or sturdy chair and skip it if you've fallen recently or feel dizzy. Put your foot down whenever you need to."
        }
    }

    /// What the result is called and its unit, for entry and the log.
    public var resultLabel: String {
        switch self {
        case .pushUps: "Push-ups"
        case .sittingRising: "Score (0-10)"
        case .oneLegStand: "Held 10 seconds"
        }
    }

    /// "32 push-ups", "8.5 of 10", "Held 10 s".
    public func formatted(_ value: Double) -> String {
        switch self {
        case .pushUps:
            let count = Int(value.rounded())
            return "\(count) push-up\(count == 1 ? "" : "s")"
        case .sittingRising:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) of 10"
        case .oneLegStand:
            return value >= 1 ? "Held 10 s" : "Couldn't hold 10 s"
        }
    }

    // MARK: Results

    public struct Result: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var test: FunctionalTest
        public var date: Date
        /// Push-ups: the count. Sitting-rising: the score, 0-10 in halves.
        /// One-leg stand: 1 held for 10 s, 0 not.
        public var value: Double

        public init(id: UUID = UUID(), test: FunctionalTest, date: Date, value: Double) {
            self.id = id
            self.test = test
            self.date = date
            self.value = value
        }
    }

    /// A typed value made valid, or nil when it can't be one: push-ups a
    /// whole count 0-200; the sitting-rising score 0-10 to the nearest half;
    /// the one-leg stand 0 or 1.
    public func validated(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        switch self {
        case .pushUps:
            let count = value.rounded()
            return (0...200).contains(count) ? count : nil
        case .sittingRising:
            let halves = (value * 2).rounded() / 2
            return (0...10).contains(halves) ? halves : nil
        case .oneLegStand:
            return value == 0 || value == 1 ? value : nil
        }
    }

    /// The sitting-rising score (Araújo 2026's scoring): each part starts at
    /// 5, loses 1 for each support and 0.5 for an unsteady movement, and
    /// can't go below 0; the two parts are added. The abstract names hand and
    /// knee supports; the forearm, side of a leg and hand on the knee are from
    /// descriptions of the published protocol (Brito 2014, record only), not
    /// re-verified. Each unsteady moment costs half a point (app's reading of
    /// "0.5 for an unsteadiness execution").
    public static func sittingRisingScore(sitSupports: Int, sitUnsteady: Int, riseSupports: Int, riseUnsteady: Int) -> Double {
        func part(_ supports: Int, _ unsteady: Int) -> Double {
            max(0, 5 - Double(max(0, supports)) - 0.5 * Double(max(0, unsteady)))
        }
        return part(sitSupports, sitUnsteady) + part(riseSupports, riseUnsteady)
    }

    /// Due when there's no result for this test in the last `intervalDays`.
    public static func isDue(_ test: FunctionalTest, results: [Result], now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let next = nextDue(test, results: results, calendar: calendar) else { return true }
        return calendar.startOfDay(for: now) >= next
    }

    public static func nextDue(_ test: FunctionalTest, results: [Result], calendar: Calendar = .current) -> Date? {
        guard let last = results.filter({ $0.test == test }).map(\.date).max() else { return nil }
        return calendar.date(byAdding: .day, value: intervalDays, to: calendar.startOfDay(for: last))
    }

    /// The change between this test's last two results (newer minus older);
    /// nil without two.
    public static func change(_ test: FunctionalTest, results: [Result]) -> Double? {
        let sorted = results.filter { $0.test == test }.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return nil }
        return sorted[sorted.count - 1].value - sorted[sorted.count - 2].value
    }

    // MARK: Interpretation

    public struct Interpretation: Sendable, Equatable {
        public enum Standing: String, Sendable {
            /// In the cohort's best group.
            case top
            /// Between the groups the paper reports.
            case middle
            /// In the cohort's lowest group.
            case low
            /// No cohort figure applies (push-ups for women).
            case noComparison
        }

        public var standing: Standing
        /// One short line: "Over 40: the study's top group".
        public var headline: String
        /// What the cohort found, labelled as one cohort.
        public var detail: String
        /// Set when the age is outside the cohort's.
        public var ageNote: String?
    }

    /// What a result means against its cohort, without overclaiming.
    public static func interpret(_ test: FunctionalTest, value: Double, age: Int, sex: BiologicalSex) -> Interpretation {
        let ageNote = test.cohortAges.flatMap { ages -> String? in
            ages.contains(age) ? nil : "The study followed people aged \(ages.lowerBound)-\(ages.upperBound), so at \(age) the comparison is rougher; your own trend still counts."
        }
        switch test {
        case .pushUps:
            return pushUps(Int(value.rounded()), sex: sex)
        case .sittingRising:
            var result = sittingRising(value)
            result.ageNote = ageNote
            return result
        case .oneLegStand:
            var result = oneLegStand(held: value >= 1)
            result.ageNote = ageNote
            return result
        }
    }

    static let oneCohort = "Linked with, in one cohort: it doesn't show that training for the test lowers risk."

    static func pushUps(_ count: Int, sex: BiologicalSex) -> Interpretation {
        let study = "In one study of 1,104 active men (firefighters, average age 40) followed for 10 years, those who did more than 40 push-ups had 96% fewer heart and blood-vessel events than those who did fewer than 10 (IRR 0.04; only 37 events in all; Yang 2019)."
        guard sex == .male else {
            return Interpretation(standing: .noComparison, headline: "Your count, for your own trend",
                                  detail: "The only study behind this test followed men, so there's no figure to compare a woman's count with. A count that holds or rises year to year is still a useful sign of upper-body strength.",
                                  ageNote: nil)
        }
        if count > pushUpTopGroupAbove {
            return Interpretation(standing: .top, headline: "Over \(pushUpTopGroupAbove): the study's top group",
                                  detail: "\(study) \(oneCohort)", ageNote: nil)
        }
        if count < pushUpLowestGroupBelow {
            return Interpretation(standing: .low, headline: "Under \(pushUpLowestGroupBelow): the study's lowest group",
                                  detail: "\(study) \(oneCohort) A low count is a reason to build strength, not a diagnosis.", ageNote: nil)
        }
        return Interpretation(standing: .middle, headline: "Between the study's lowest (under \(pushUpLowestGroupBelow)) and top (over \(pushUpTopGroupAbove)) groups",
                              detail: "\(study) \(oneCohort)", ageNote: nil)
    }

    /// The index of the score's group in `sittingRisingGroups` (0 = lowest).
    /// Halves between the paper's groups can't occur (scores move in halves
    /// and the groups cover every half from 0 to 10).
    public static func sittingRisingGroup(_ score: Double) -> Int {
        sittingRisingGroups.lastIndex { score >= $0.lowerBound } ?? 0
    }

    static func sittingRising(_ score: Double) -> Interpretation {
        let group = sittingRisingGroup(score)
        let range = sittingRisingGroups[group]
        let rangeText = range.lowerBound == range.upperBound
            ? range.lowerBound.formatted(.number.precision(.fractionLength(0...1)))
            : "\(range.lowerBound.formatted(.number.precision(.fractionLength(0...1))))-\(range.upperBound.formatted(.number.precision(.fractionLength(0...1))))"
        let rate = sittingRisingDeathRates[group].formatted(.number.precision(.fractionLength(1)))
        let study = "In one study of 4,282 adults aged 46-75 followed for about 12 years, \(rate)% of those scoring \(rangeText) died, against 3.7% of those scoring 10. The lowest group (0-4) had 3.84 times the risk of natural death and 6.05 times the risk of heart-related death of the top group (Araújo 2026)."
        let standing: Interpretation.Standing = group == sittingRisingGroups.count - 1 ? .top : (group == 0 ? .low : .middle)
        let headline: String = switch standing {
        case .top: "10 of 10: the study's top group"
        case .low: "In the study's lowest group (0-4)"
        default: "In the study's \(rangeText) group"
        }
        let extra = standing == .top ? "" : " Each support you need costs a point; strength, flexibility and balance work all move it."
        return Interpretation(standing: standing, headline: headline, detail: "\(study) \(oneCohort)\(extra)", ageNote: nil)
    }

    static func oneLegStand(held: Bool) -> Interpretation {
        let study = "In one study of 1,702 adults aged 51-75 followed for about 7 years, 1 in 5 couldn't do it. Of them 17.5% died, against 4.6% of those who could: 1.84 times the risk after allowing for age, sex, weight and illnesses (Araujo 2022)."
        if held {
            return Interpretation(standing: .top, headline: "Held 10 seconds", detail: "\(study) \(oneCohort)", ageNote: nil)
        }
        return Interpretation(standing: .low, headline: "Couldn't hold 10 seconds",
                              detail: "\(study) \(oneCohort) Balance training helps, and it's worth mentioning to your doctor.",
                              ageNote: nil)
    }
}
