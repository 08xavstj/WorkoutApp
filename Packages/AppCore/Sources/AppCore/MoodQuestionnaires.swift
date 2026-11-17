import Foundation

/// The PHQ-9 (depression) and GAD-7 (anxiety) questionnaires, offered inside
/// the app only after two weeks of mostly low mornings
/// (docs/research/evidence-audit-2026-11.md, Gaps, item 4; the low-mood rule
/// is `LowMoodRule`).
///
/// Sources, read at the source in November 2026:
/// - Item wording, answers, scoring and bands: the PHQ Screeners instruction
///   manual (phqscreeners.com, "instructions.pdf"): each item scored 0-3 for
///   "not at all", "several days", "more than half the days", "nearly every
///   day"; PHQ-9 0-27 with cut points 5, 10, 15 and 20 for mild, moderate,
///   moderately severe and severe; GAD-7 0-21 with 5, 10 and 15 for mild,
///   moderate and severe; 10 or more is the usual point for further
///   evaluation. The GAD-7 item wording is from the University of
///   Washington's copy of the form (hiv.uw.edu), which matches the manual's.
/// - Validation: PHQ-9 ≥ 10 had 88% sensitivity and 88% specificity for
///   major depression (Kroenke, Spitzer & Williams, J Gen Intern Med
///   2001;16:606, PMID 11556941). GAD-7: sensitivity 89%, specificity 82% at
///   its cut point (Spitzer et al., Arch Intern Med 2006;166:1092, PMID 16717171).
/// - Licence: "no permission is required to reproduce, translate, display or
///   distribute them" (phqscreeners.com).
/// - Why offer it: USPSTF 2023 recommends screening adults for depression
///   (B; JAMA 2023;329:2057, PMID 37338872) and for anxiety disorders (B)
///   with insufficient evidence from 65 (I; JAMA 2023;329:2163, PMID
///   37338866). Both found the evidence insufficient on screening for
///   suicide risk, so the app doesn't score item 9 as a risk tool; any answer
///   above zero shows crisis contacts at once, which is the PHQ manual's own
///   practice (item 9 "is counted whenever it is present") and costs nothing.
/// - The timing (after the low-mood rule's two weeks, at most every 4
///   weeks) is the app's choice: the questions cover the last 2 weeks, so
///   asking more often than that overlaps.
///
/// It is a screen, not a diagnosis.
public enum MoodQuestionnaires {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case phq9, gad7
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .phq9: "PHQ-9"
            case .gad7: "GAD-7"
            }
        }

        /// What it screens for, in plain words.
        public var about: String {
            switch self {
            case .phq9: "Low mood and depression"
            case .gad7: "Worry and anxiety"
            }
        }

        public var stem: String {
            switch self {
            case .phq9: "Over the last 2 weeks, how often have you been bothered by any of the following problems?"
            case .gad7: "Over the last 2 weeks, how often have you been bothered by the following problems?"
            }
        }

        /// The items, verbatim from the published forms.
        public var items: [String] {
            switch self {
            case .phq9: [
                "Little interest or pleasure in doing things",
                "Feeling down, depressed, or hopeless",
                "Trouble falling or staying asleep, or sleeping too much",
                "Feeling tired or having little energy",
                "Poor appetite or overeating",
                "Feeling bad about yourself — or that you are a failure or have let yourself or your family down",
                "Trouble concentrating on things, such as reading the newspaper or watching television",
                "Moving or speaking so slowly that other people could have noticed? Or the opposite — being so fidgety or restless that you have been moving around a lot more than usual",
                "Thoughts that you would be better off dead or of hurting yourself in some way",
            ]
            case .gad7: [
                "Feeling nervous, anxious or on edge",
                "Not being able to stop or control worrying",
                "Worrying too much about different things",
                "Trouble relaxing",
                "Being so restless that it is hard to sit still",
                "Becoming easily annoyed or irritable",
                "Feeling afraid as if something awful might happen",
            ]
            }
        }

        /// The highest possible score.
        public var maxScore: Int { items.count * 3 }
    }

    /// The four answers, scored 0-3.
    public static let answers = ["Not at all", "Several days", "More than half the days", "Nearly every day"]

    /// PHQ-9 item 9 (thoughts of being better off dead or of self-harm), zero-based.
    public static let selfHarmItem = 8

    /// Moderate or higher: 10 on either (the manual's point for further
    /// evaluation; Kroenke 2001 for the PHQ-9's 88%/88%).
    public static let talkToDoctorScore = 10

    /// At most once in this many days (app's choice: the questions cover 2
    /// weeks, so 4 weeks keeps two answers from overlapping).
    public static let offerEveryDays = 28

    /// The GAD-7 is offered under this age (USPSTF 2023: anxiety screening B
    /// under 65, I statement from 65).
    public static let anxietyScreenBelowAge = 65

    /// A positive screen keeps the workout reminders plain this long (app's
    /// choice: until the next offer could come round).
    public static let keepPlainDays = 28

    public enum Severity: String, Codable, Sendable, CaseIterable {
        case minimal, mild, moderate, moderatelySevere, severe

        public var label: String {
            switch self {
            case .minimal: "Minimal"
            case .mild: "Mild"
            case .moderate: "Moderate"
            case .moderatelySevere: "Moderately severe"
            case .severe: "Severe"
            }
        }
    }

    /// The published bands: PHQ-9 5/10/15/20, GAD-7 5/10/15.
    public static func severity(_ kind: Kind, score: Int) -> Severity {
        switch kind {
        case .phq9:
            switch score {
            case ..<5: .minimal
            case ..<10: .mild
            case ..<15: .moderate
            case ..<20: .moderatelySevere
            default: .severe
            }
        case .gad7:
            switch score {
            case ..<5: .minimal
            case ..<10: .mild
            case ..<15: .moderate
            default: .severe
            }
        }
    }

    /// One completed questionnaire.
    public struct Result: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var kind: Kind
        public var date: Date
        /// One answer per item, 0-3.
        public var answers: [Int]

        public init(id: UUID = UUID(), kind: Kind, date: Date, answers: [Int]) {
            self.id = id
            self.kind = kind
            self.date = date
            self.answers = answers
        }

        public var isComplete: Bool {
            answers.count == kind.items.count && answers.allSatisfy { (0...3).contains($0) }
        }

        public var score: Int { answers.map { min(3, max(0, $0)) }.reduce(0, +) }
        public var severity: Severity { MoodQuestionnaires.severity(kind, score: score) }

        /// Moderate or higher: one calm suggestion to talk to a doctor.
        public var suggestsDoctor: Bool { score >= MoodQuestionnaires.talkToDoctorScore }

        /// PHQ-9 item 9 above zero: crisis contacts straight away.
        public var selfHarmAnswered: Bool {
            kind == .phq9 && answers.count > MoodQuestionnaires.selfHarmItem && answers[MoodQuestionnaires.selfHarmItem] > 0
        }

        /// What switches the workout reminders to plain wording.
        public var isPositive: Bool { suggestsDoctor || selfHarmAnswered }

        /// "PHQ-9: 7 of 27, mild"
        public var summary: String {
            "\(kind.title): \(score) of \(kind.maxScore), \(severity.label.lowercased())"
        }

        /// The plain line under the score. Says it is a screen, not a diagnosis.
        public var meaning: String {
            let topic = kind == .phq9 ? "low mood" : "anxiety"
            switch severity {
            case .minimal:
                return "Few signs of \(topic) in the last two weeks. This is a screen, not a diagnosis."
            case .mild:
                return "Some signs of \(topic). Mild scores often settle; sleep, activity and people help. This is a screen, not a diagnosis."
            case .moderate, .moderatelySevere, .severe:
                return "A \(severity.label.lowercased()) score for \(topic). This is a screen, not a diagnosis, and it's worth talking it through with a doctor. They can help, and it's common."
            }
        }
    }

    /// Shown at once when PHQ-9 item 9 is above zero (and on the screen's own
    /// page). Plain, no judgement, what to do now.
    public static let crisisText = "If you're having thoughts of hurting yourself, please reach out now. Contact your local emergency services or a crisis line. In the US, call or text 988 (Suicide & Crisis Lifeline)."

    /// Whether to offer the questionnaires today: the low-mood rule's two
    /// weeks apply (`LowMoodRule.Finding.fortnightApplies`), the person hasn't
    /// switched them off, and none was offered or taken in the last
    /// `offerEveryDays` days.
    public static func offerDue(lowMood: LowMoodRule.Finding?, lastOffered: Date?, lastTaken: Date?, turnedOff: Bool,
                                now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !turnedOff, lowMood?.fortnightApplies == true else { return false }
        let today = calendar.startOfDay(for: now)
        // The offer stays up for the rest of the day it was first shown.
        if let lastOffered, calendar.startOfDay(for: lastOffered) == today, lastTaken.map({ calendar.startOfDay(for: $0) != today }) ?? true {
            return true
        }
        guard let last = [lastOffered, lastTaken].compactMap({ $0 }).max() else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day ?? 0
        return days >= offerEveryDays
    }

    /// Which questionnaires to offer at this age.
    public static func kinds(age: Int) -> [Kind] {
        age < anxietyScreenBelowAge ? [.phq9, .gad7] : [.phq9]
    }

    /// True while a positive result from the last `keepPlainDays` days should
    /// keep reminders plain.
    public static func recentPositive(_ results: [Result], now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let cutoff = calendar.date(byAdding: .day, value: -keepPlainDays, to: now) else { return false }
        return results.contains { $0.isPositive && $0.date >= cutoff && $0.date <= now }
    }
}

extension MoodCare {
    /// Plain workout reminders while the low-mood rule is in play, and for
    /// `MoodQuestionnaires.keepPlainDays` after a positive PHQ-9 or GAD-7.
    public static func keepPlain(lowMood: LowMoodRule.Finding?, screens: [MoodQuestionnaires.Result],
                                 now: Date = .now, calendar: Calendar = .current) -> Bool {
        keepPlain(lowMood: lowMood) || MoodQuestionnaires.recentPositive(screens, now: now, calendar: calendar)
    }
}
