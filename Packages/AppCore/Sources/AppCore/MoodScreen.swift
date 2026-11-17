import Foundation

/// The monthly two-question depression screen (PHQ-2) and two-question
/// anxiety screen (GAD-2), together the PHQ-4 (write-up in
/// docs/research/mind-and-prevention-2026-11.md).
///
/// **Wording and scoring**, checked against the developers' instruction
/// manual and the GAD-7 form on phqscreeners.com on 17 Nov 2026:
/// - Stem: "Over the last 2 weeks, how often have you been bothered by the
///   following problems?" (the GAD-7 form's stem; the PHQ-9's reads "…by any
///   of the following problems").
/// - PHQ-2 = PHQ-9 items 1 and 2; GAD-2 = GAD-7 items 1 and 2.
/// - Answers score 0 "Not at all", 1 "Several days", 2 "More than half the
///   days", 3 "Nearly every day"; each pair totals 0-6.
/// - "The recommended cutpoints for each when used as screeners is a score of
///   3 or greater", which "should prompt administration of the full PHQ-9
///   and/or GAD-7, as well as a clinical interview" (instruction manual).
///
/// **Licence.** The manual says: "All of the measures included in Table 1 are
/// in the public domain. No permission is required to reproduce, translate,
/// display or distribute." The GAD-7 form's footer: "Developed by Drs. Robert
/// L. Spitzer, Janet B.W. Williams, Kurt Kroenke and colleagues, with an
/// educational grant from Pfizer Inc. No permission required to reproduce,
/// translate, display or distribute." The item wording below is unchanged.
///
/// **How good a screen it is.**
/// - PHQ-2 at 3 or more: sensitivity 83%, specificity 92% for major
///   depression in the first study (Kroenke, Spitzer & Williams, Med Care
///   2003;41:1284, 580 interviewed). Pooled over 44 studies with
///   semi-structured interviews it is lower: sensitivity 0.72, specificity
///   0.85 (Levis et al., JAMA 2020;323:2290). At the 10% prevalence of those
///   studies, about one positive screen in three is major depression.
/// - GAD-2 at 3 or more: sensitivity 0.76, specificity 0.81 for generalised
///   anxiety disorder (Plummer et al., Gen Hosp Psychiatry 2016;39:24, 6
///   samples); first validated in 965 primary-care patients (Kroenke et al.,
///   Ann Intern Med 2007;146:317).
/// - So a positive screen is a reason to be asked more, not a diagnosis, and
///   a negative one does not rule anything out. Both studies were in clinic
///   patients; accuracy in a healthy person repeating it monthly is unknown.
/// - Screening helps when it leads to care: the US Preventive Services Task
///   Force recommends screening adults for depression and, up to 64, anxiety
///   (both grade B, June 2023), with "adequate systems" for follow-up, and
///   says there is little evidence on how often. Monthly is the owner's
///   choice, not a tested interval; the questions cover two weeks, so
///   monthly answers don't overlap.
/// - Neither pair asks about self-harm. The crisis line is shown with every
///   positive screen regardless.
public enum MoodScreen {
    /// The form's stem, unchanged.
    public static let stem = "Over the last 2 weeks, how often have you been bothered by the following problems?"
    /// A pair's total at or above this is a positive screen (instruction manual; Kroenke 2003, 2007).
    public static let cutoff = 3
    public static let maximumScore = 6
    /// Full-form lines for questionnaires read from Apple Health: 10 or more
    /// on the PHQ-9 or GAD-7 is the manual's point for further evaluation.
    public static let fullFormCutoff = 10
    /// Days between offers (the owner's choice of "monthly"; not from a study).
    public static let intervalDays = 30
    /// "Not this month" puts the offer off this long (app's choice: a week,
    /// then it sits quietly in the check-in again).
    public static let notNowDays = 7
    /// A questionnaire filled in Apple Health this recently counts as this month's.
    public static let healthCountsForDays = 30

    public enum Scale: String, Codable, Sendable, CaseIterable {
        case phq2, gad2

        /// The plain name on the result ("Low mood", "Worry"); the instrument's name is in `instrument`.
        public var title: String {
            switch self {
            case .phq2: "Low mood"
            case .gad2: "Anxiety"
            }
        }

        public var instrument: String {
            switch self {
            case .phq2: "PHQ-2"
            case .gad2: "GAD-2"
            }
        }

        /// What a positive screen is a screen for.
        public var screensFor: String {
            switch self {
            case .phq2: "depression"
            case .gad2: "an anxiety disorder"
            }
        }
    }

    public enum Item: String, Codable, Sendable, CaseIterable, Identifiable {
        case littleInterest, feelingDown, nervous, worrying

        public var id: String { rawValue }

        /// The item text, unchanged from the PHQ-9 and GAD-7 forms.
        public var text: String {
            switch self {
            case .littleInterest: "Little interest or pleasure in doing things"
            case .feelingDown: "Feeling down, depressed, or hopeless"
            case .nervous: "Feeling nervous, anxious or on edge"
            case .worrying: "Not being able to stop or control worrying"
            }
        }

        public var scale: Scale {
            switch self {
            case .littleInterest, .feelingDown: .phq2
            case .nervous, .worrying: .gad2
            }
        }
    }

    public enum Answer: Int, Codable, Sendable, CaseIterable, Identifiable {
        case notAtAll = 0, severalDays, moreThanHalfTheDays, nearlyEveryDay

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .notAtAll: "Not at all"
            case .severalDays: "Several days"
            case .moreThanHalfTheDays: "More than half the days"
            case .nearlyEveryDay: "Nearly every day"
            }
        }
    }

    public enum Source: String, Codable, Sendable {
        /// The four questions answered in this app.
        case app
        /// A PHQ-9 or GAD-7 filled in Apple Health.
        case appleHealth
    }

    /// One completed screen. From the app both pairs are present; from Apple
    /// Health one form gives one pair and its full-form total.
    public struct Result: Codable, Sendable, Equatable, Identifiable {
        public var date: Date
        public var source: Source
        /// 0-6; nil when this entry has no depression answers.
        public var phq2: Int?
        /// 0-6; nil when this entry has no anxiety answers.
        public var gad2: Int?
        /// PHQ-9 total (0-27), only from Apple Health.
        public var phq9: Int?
        /// GAD-7 total (0-21), only from Apple Health.
        public var gad7: Int?

        public var id: String { "\(source.rawValue)|\(date.timeIntervalSinceReferenceDate)|\(phq2 ?? -1)|\(gad2 ?? -1)" }

        public init(date: Date, source: Source = .app, phq2: Int? = nil, gad2: Int? = nil, phq9: Int? = nil, gad7: Int? = nil) {
            self.date = date
            self.source = source
            self.phq2 = phq2
            self.gad2 = gad2
            self.phq9 = phq9
            self.gad7 = gad7
        }

        public var depressionPositive: Bool {
            (phq2 ?? 0) >= MoodScreen.cutoff || (phq9 ?? 0) >= MoodScreen.fullFormCutoff
        }

        public var anxietyPositive: Bool {
            (gad2 ?? 0) >= MoodScreen.cutoff || (gad7 ?? 0) >= MoodScreen.fullFormCutoff
        }

        public var isPositive: Bool { depressionPositive || anxietyPositive }

        public func score(_ scale: Scale) -> Int? {
            switch scale {
            case .phq2: phq2
            case .gad2: gad2
            }
        }

        public func isPositive(_ scale: Scale) -> Bool {
            switch scale {
            case .phq2: depressionPositive
            case .gad2: anxietyPositive
            }
        }
    }

    /// The result of four answers; nil until all four are given.
    public static func result(answers: [Item: Answer], date: Date) -> Result? {
        guard Item.allCases.allSatisfy({ answers[$0] != nil }) else { return nil }
        func total(_ scale: Scale) -> Int {
            Item.allCases.filter { $0.scale == scale }.reduce(0) { $0 + (answers[$1]?.rawValue ?? 0) }
        }
        return Result(date: date, source: .app, phq2: total(.phq2), gad2: total(.gad2))
    }

    // MARK: When to offer

    /// The newest result of any source.
    public static func latest(_ results: [Result]) -> Result? {
        results.max { $0.date < $1.date }
    }

    /// Whether the monthly offer shows: switched on, `intervalDays` since the
    /// last screen from any source (a questionnaire filled in Apple Health
    /// counts), and not put off with "Not this month".
    public static func isDue(enabled: Bool, results: [Result], notNowUntil: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        if let notNowUntil, notNowUntil > now { return false }
        guard let last = latest(results) else { return true }
        return now.timeIntervalSince(last.date) >= Double(intervalDays) * 86_400
    }

    // MARK: Words

    /// "2 of 6 · below the screening line"
    public static func line(_ scale: Scale, in result: Result) -> String? {
        guard let score = result.score(scale) else { return nil }
        let side = score >= cutoff ? "at or above the screening line (\(cutoff))" : "below the screening line (\(cutoff))"
        return "\(score) of \(maximumScore) · \(side)"
    }

    /// The plain statement under every result.
    public static let notADiagnosis = "This is a screen, not a diagnosis. It shows who should be asked more. It can't tell you what you have, and a low score doesn't rule anything out."

    /// One calm suggestion after a positive screen; nil after a negative one.
    public static func suggestion(for result: Result) -> String? {
        guard result.isPositive else { return nil }
        let what: String
        switch (result.depressionPositive, result.anxietyPositive) {
        case (true, true): what = "Both pairs are"
        case (true, false): what = "The low-mood pair is"
        default: what = "The anxiety pair is"
        }
        return "\(what) at the line where a doctor would ask more. It's worth talking to your doctor, or to someone you trust, about how the last two weeks have been."
    }

    /// Shown with every positive screen, whatever the answers.
    public static let crisisText = "If you have thoughts of harming yourself, contact your local emergency services or a crisis line now. In the US, call or text 988."

    /// How often the line is right, in plain numbers (Levis 2020; Plummer 2016).
    public static let accuracyNote = "At this line the low-mood pair finds about 7 in 10 people who have major depression and flags about 15 in 100 who don't (Levis 2020, 44 studies). The anxiety pair finds about 3 in 4 with generalised anxiety disorder and flags about 19 in 100 without (Plummer 2016). So most positive screens turn out not to be a disorder. The studies were in clinic patients, not in people repeating it monthly."

    /// Where the questions come from, for the page's footer.
    public static let sourceNote = "PHQ-2 and GAD-2, the first two questions of the PHQ-9 and GAD-7, developed by Drs. Robert L. Spitzer, Janet B.W. Williams, Kurt Kroenke and colleagues with an educational grant from Pfizer Inc. Public domain; wording unchanged."
}

// MARK: - Tone flag for jokes and the coach

/// One flag other features read before being playful: workout notifications
/// with jokes, a bantering coach line. It is false after a positive mood or
/// anxiety screen and while mood has been mostly low for two weeks.
///
/// Read it with `PlayfulTone.isAllowed()` from anywhere (it reads
/// `UserDefaults.standard`; no actor, no model). Only the mood features write
/// it. It carries no score and no reason, so a reader learns nothing clinical.
public enum PlayfulTone {
    /// UserDefaults keys, one per reason, each holding the date the pause ends.
    public static let screenKey = "playfulTonePausedUntil.screen"
    public static let lowMoodKey = "playfulTonePausedUntil.lowMood"
    /// A positive screen pauses playful wording this long, or until a later
    /// screen is negative (app's choice: the next monthly check plus a month's slack).
    public static let pauseDaysAfterPositiveScreen = 60
    /// Two weeks of mostly low mood pauses it this long past the last day the
    /// rule held (app's choice).
    public static let pauseDaysAfterLowMood = 7

    /// True when jokes and banter are fine. False: keep wording plain and kind.
    public static func isAllowed(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        for key in [screenKey, lowMoodKey] {
            if let until = defaults.object(forKey: key) as? Date, until > now { return false }
        }
        return true
    }

    /// Call after every completed screen (from the app or read from Health).
    public static func noteScreen(_ result: MoodScreen.Result, defaults: UserDefaults = .standard) {
        if result.isPositive {
            defaults.set(result.date.addingTimeInterval(Double(pauseDaysAfterPositiveScreen) * 86_400), forKey: screenKey)
        } else {
            defaults.removeObject(forKey: screenKey)
        }
    }

    /// Call with whether mood has been mostly low for two weeks (`LowMoodRule.Finding.fortnightApplies`).
    public static func noteLowMood(_ mostlyLowForTwoWeeks: Bool, now: Date = .now, defaults: UserDefaults = .standard) {
        // When the rule stops holding, the pause runs out by itself.
        guard mostlyLowForTwoWeeks else { return }
        defaults.set(now.addingTimeInterval(Double(pauseDaysAfterLowMood) * 86_400), forKey: lowMoodKey)
    }

    /// The one line the on-device coach gets while the flag is false: tone
    /// only, no result, so there is nothing for it to counsel on.
    public static let coachToneLine = "Tone for today: plain and kind. No jokes, no banter, no pep talk."
}
