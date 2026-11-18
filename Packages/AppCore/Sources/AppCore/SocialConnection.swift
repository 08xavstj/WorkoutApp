import Foundation

/// An optional social connection check every 3 months: the 3-item UCLA
/// Loneliness Scale (docs/research/next-features-2026-11.md, I6; §4e).
/// Off by default, switched on in Settings beside the mood questionnaires.
///
/// Sources and their limits:
/// - The scale: three questions answered "hardly ever" (1), "some of the
///   time" (2) or "often" (3), summed to 3-9 (Hughes, Waite, Hawkley &
///   Cacioppo, Res Aging 2004; record only, the abstract wasn't re-read this
///   round). Hughes validated the short form against the 20-item scale; the
///   6-or-more line that "suggests loneliness" is a convention of later
///   survey research, not a clinical cut-off, so the result is worded as
///   "you've felt lonely often lately", never as a diagnosis.
/// - Why it matters: loneliness went with HR 1.14 and social isolation with
///   HR 1.32 for death from any cause (90 cohorts, 2.2 million people; Wang
///   et al., Nat Hum Behav 2023), and stronger social relationships with 50%
///   higher odds of survival (Holt-Lunstad et al., PLoS Med 2010). Strong
///   association.
/// - What helps is much less certain: randomised trials of loneliness
///   interventions showed small effects, and the best addressed maladaptive
///   social thinking (Masi et al., Pers Soc Psychol Rev 2011), which an app
///   can't deliver. So the only follow-up is one gentle line about planning
///   time with someone, and where to find help.
/// - Every 3 months is the research file's cadence (app's choice: loneliness
///   changes slowly, and asking more often would nag).
public enum SocialConnectionCheck {
    /// The three items (Hughes 2004).
    public static let items = [
        "How often do you feel that you lack companionship?",
        "How often do you feel left out?",
        "How often do you feel isolated from others?",
    ]

    /// Answers scored 1, 2 and 3.
    public static let answers = ["Hardly ever", "Some of the time", "Often"]

    /// Total 6 or more: the usual line for "lonely" in survey research.
    public static let lonelyFrom = 6

    /// About every 3 months (91 days).
    public static let everyDays = 91

    public struct Result: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var date: Date
        /// One answer per item, 1-3.
        public var answers: [Int]

        public init(id: UUID = UUID(), date: Date, answers: [Int]) {
            self.id = id
            self.date = date
            self.answers = answers
        }

        public var isComplete: Bool {
            answers.count == SocialConnectionCheck.items.count && answers.allSatisfy { (1...3).contains($0) }
        }

        /// 3-9.
        public var score: Int { answers.map { min(3, max(1, $0)) }.reduce(0, +) }

        public var suggestsLoneliness: Bool { score >= SocialConnectionCheck.lonelyFrom }

        /// The gentle line under the score. Never a diagnosis.
        public var meaning: String {
            suggestsLoneliness
                ? "You've felt left out or short of company fairly often lately. That's common, and it tends to ease with small, regular contact."
                : "You've mostly felt connected lately."
        }
    }

    /// The one follow-up and where to find help, shown with every result.
    public static let resourceLine = "Planning time with someone this week, even a call or a walk, is a good place to start. If loneliness is weighing on you, a GP or a local helpline can help you find groups and support."

    /// How the questions were chosen, for the result screen.
    public static let sourceLine = "Three questions from the UCLA Loneliness Scale's short form (Hughes et al. 2004), scored 3-9; 6 or more is the line surveys use for loneliness. It isn't a diagnosis. Feeling lonely and being isolated both go with poorer long-term health (Wang et al. 2023), but how best to help is less clear (Masi et al. 2011)."

    /// Due when switched on and none was answered in the last `everyDays` days.
    public static func isDue(enabled: Bool, lastTaken: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        guard let lastTaken, let next = nextDue(lastTaken: lastTaken, calendar: calendar) else { return true }
        return calendar.startOfDay(for: now) >= next
    }

    public static func nextDue(lastTaken: Date?, calendar: Calendar = .current) -> Date? {
        guard let lastTaken else { return nil }
        return calendar.date(byAdding: .day, value: everyDays, to: calendar.startOfDay(for: lastTaken))
    }
}
