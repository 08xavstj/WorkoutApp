import Foundation

/// The low-mood rule for the morning message
/// (docs/research/healthy-living-2026-11.md, section 3 item 10).
///
/// What it does: after three low mornings in a week, a morning message that
/// would have suggested rest offers a 20-minute walk or an easy session
/// instead and says why. After two weeks of mostly low mornings it adds one
/// sentence that this is worth raising with someone. There is no score, and
/// nothing is shown until the rule applies.
///
/// Evidence and its limits:
/// - Exercise reduces depressive symptoms: walking or jogging g = −0.62,
///   strength training −0.49, low certainty (Noetel et al., BMJ 2024;384:e075847,
///   network meta-analysis); about −0.43 across 97 reviews (Singh et al., Br J
///   Sports Med 2023;57:1203). Those trials were in people with depression or
///   raised symptoms. Applying the finding to a healthy person's bad week is an
///   extrapolation, so the message says moving "often" helps and only offers.
/// - A single 1-5 mood answer has no validated cut-off. Every threshold here
///   is the app's choice. The two-week, more-than-half-the-days window mirrors
///   the time frame the PHQ questions use (Kroenke, Spitzer & Williams, Med
///   Care 2003;41:1284), but this is not a PHQ and not a screen.
/// - Exercise as treatment is the trials' finding; whether one 20-minute walk
///   lifts one low morning is not what they tested. Single bouts of moderate
///   exercise do improve mood for a while afterwards in many studies, but
///   that literature is mixed in quality, so the message says "often helps"
///   and never promises.
/// - The offer never replaces rest that has a physical reason: low recovery,
///   HRV below normal, a rest day that follows an unplanned hard day, reported
///   illness or rest mode all leave the message as it was.
public enum LowMoodRule {
    /// A morning check-in mood of 1 ("Low") or 2 ("Meh") on the 1-5 scale
    /// counts as a low morning (app's choice; no validated cut-off).
    public static let lowMoodAtOrBelow = 2
    /// The same line for Apple Health's State of Mind valence (−1...1): below
    /// −0.2 reads "Meh" or "Low" in `MoodScale.word` (app's choice).
    public static let lowValenceBelow = -0.2
    /// Low mornings in the last `weekDays` days that start the offer (app's choice).
    public static let lowDaysInWeek = 3
    public static let weekDays = 7
    /// "Mostly low for two weeks": low on more than half of the last 14 days
    /// (app's choice; days with no answer count as not low, so it errs towards silence).
    public static let lowDaysInFortnight = 8
    public static let fortnightDays = 14
    /// The "worth raising with someone" sentence is said at most once in this
    /// many days (app's choice: said once, then left alone for a week).
    public static let raiseEveryDays = 7
    /// The walk the message offers, minutes (app's choice within the trials'
    /// range; Noetel 2024 found benefit across doses, more at higher intensity).
    public static let walkMinutes = 20

    /// One day's answer.
    public struct Day: Sendable, Equatable {
        /// Start of the day.
        public var day: Date
        public var isLow: Bool

        public init(day: Date, isLow: Bool) {
            self.day = day
            self.isLow = isLow
        }
    }

    /// What the rule found for one morning.
    public struct Finding: Sendable, Equatable {
        /// Low days among the last 7 (the message's day included).
        public var lowInWeek: Int
        /// Low days among the last 14.
        public var lowInFortnight: Int
        /// Days with any mood answer among the last 14.
        public var answeredInFortnight: Int

        public init(lowInWeek: Int, lowInFortnight: Int, answeredInFortnight: Int) {
            self.lowInWeek = lowInWeek
            self.lowInFortnight = lowInFortnight
            self.answeredInFortnight = answeredInFortnight
        }

        /// Three or more low mornings in the week: the offer may be made.
        public var weekApplies: Bool { lowInWeek >= LowMoodRule.lowDaysInWeek }
        /// Low on more than half of the last 14 days.
        public var fortnightApplies: Bool { lowInFortnight >= LowMoodRule.lowDaysInFortnight }
    }

    /// One entry per day with a mood answer. The morning check-in's mood (1-5)
    /// comes first. A day without one falls back to Apple Health's State of
    /// Mind entries from other apps for that day: the daily mood when there is
    /// one, else the average of the entries logged before noon.
    /// - Parameter mornings: start of day → the check-in's mood (1-5).
    public static func days(mornings: [Date: Int], health: [MoodSample], calendar: Calendar = .current) -> [Day] {
        var result: [Date: Bool] = [:]
        for (day, mood) in mornings {
            result[calendar.startOfDay(for: day)] = mood <= lowMoodAtOrBelow
        }
        let others = health.filter { !$0.fromThisApp }
        let grouped = Dictionary(grouping: others) { calendar.startOfDay(for: $0.date) }
        for (day, samples) in grouped where result[day] == nil {
            let daily = samples.filter { $0.kind == .daily }
            let beforeNoon = samples.filter { calendar.component(.hour, from: $0.date) < 12 }
            let used = daily.isEmpty ? beforeNoon : daily
            guard !used.isEmpty else { continue }
            let valence = used.map(\.valence).reduce(0, +) / Double(used.count)
            result[day] = valence < lowValenceBelow
        }
        return result.map { Day(day: $0.key, isLow: $0.value) }.sorted { $0.day < $1.day }
    }

    /// The counts for the morning of `today`, or nil when fewer than
    /// `lowDaysInWeek` of the last 7 days were low (the rule is not in play).
    public static func finding(days: [Day], on today: Date, calendar: Calendar = .current) -> Finding? {
        let end = calendar.startOfDay(for: today)
        guard let weekStart = calendar.date(byAdding: .day, value: -(weekDays - 1), to: end),
              let fortnightStart = calendar.date(byAdding: .day, value: -(fortnightDays - 1), to: end) else { return nil }
        // One answer per day, whatever the caller passed.
        var byDay: [Date: Bool] = [:]
        for day in days {
            let key = calendar.startOfDay(for: day.day)
            guard key >= fortnightStart, key <= end else { continue }
            byDay[key] = (byDay[key] ?? false) || day.isLow
        }
        let lowInWeek = byDay.filter { $0.key >= weekStart && $0.value }.count
        guard lowInWeek >= lowDaysInWeek else { return nil }
        return Finding(lowInWeek: lowInWeek, lowInFortnight: byDay.filter(\.value).count, answeredInFortnight: byDay.count)
    }

    /// Whether the "worth raising with someone" sentence may be said on `day`.
    /// It stays on the message it was first put on (so rebuilding that day's
    /// message doesn't drop it), then waits `raiseEveryDays` days.
    public static func raiseDue(lastRaised: Date?, on day: Date, calendar: Calendar = .current) -> Bool {
        guard let lastRaised else { return true }
        let last = calendar.startOfDay(for: lastRaised)
        let today = calendar.startOfDay(for: day)
        if last == today { return true }
        let days = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        // A date in the future (a message written ahead, then the clock changed): treat as said.
        return days >= raiseEveryDays
    }
}

// MARK: - The morning message

extension CoachCheckIns {
    /// Every low-mood sentence below starts with this, so the app can spot them.
    static let lowMoodOpening = "Mood has been low on "

    /// False for a message that carries a low-mood sentence: the on-device
    /// model may not reword it (`CoachNudges.deliver` asks first), so the
    /// careful wording here is what arrives.
    public static func mayReword(_ message: Message) -> Bool {
        !message.body.contains(lowMoodOpening)
    }

    /// Both "worth raising" sentences below end with this.
    static let lowMoodRaisePhrase = "worth raising with someone you trust or your doctor"

    /// True for a message that says the "worth raising with someone" sentence.
    /// The app saves the day only then (`LowMoodRule.raiseDue`), so a message
    /// that ends up without it doesn't use up the week.
    public static func raisesLowMood(_ message: Message?) -> Bool {
        message?.body.contains(lowMoodRaisePhrase) ?? false
    }

    /// The morning message under the low-mood rule, or nil when the rule
    /// changes nothing (the caller then builds the usual message).
    ///
    /// - The offer replaces a rest-day line only: not when recovery is low,
    ///   HRV is below normal, the rest day follows an unplanned hard day, or
    ///   illness is reported. Rest mode never reaches here (`morning` returns earlier).
    /// - No offer before this morning's recovery is in: without it neither a
    ///   low score nor a 7-day HRV below normal can be ruled out, and a
    ///   physical reason to rest always wins.
    /// - The offer is one sentence: what was seen, why moving, what is on
    ///   offer. It stops there (the research's risk: sounding glib). The app
    ///   does not let the on-device model reword these (`mayReword`).
    static func lowMoodMorning(_ f: MorningFacts, title: String, easy: Bool) -> Message? {
        guard let mood = f.lowMood, mood.weekApplies, !f.illnessFlagged else { return nil }
        let offers = f.restDay && f.recovery != nil && !f.restForRecovery && !easy
        let raises = mood.fortnightApplies && f.lowMoodRaiseDue
        guard offers || raises else { return nil }

        var sentences: [String] = []
        let walk = "a \(LowMoodRule.walkMinutes)-minute walk or an easy session"
        if offers, raises {
            sentences.append("Mood has been low on \(mood.lowInFortnight) of your last \(LowMoodRule.fortnightDays) days; moving often helps, so \(walk) is there today.")
            sentences.append("That long is worth raising with someone you trust or your doctor.")
        } else if offers {
            sentences.append("Mood has been low on \(mood.lowInWeek) of your last \(LowMoodRule.weekDays) days; moving often helps, so \(walk) is an option today instead of full rest.")
        } else {
            // Not a day the message would suggest rest: keep its first line, add the one sentence.
            let raise = "Mood has been low on \(mood.lowInFortnight) of your last \(LowMoodRule.fortnightDays) days, which is worth raising with someone you trust or your doctor."
            // The day's first line stays when both fit; the sentence itself is never cut short.
            if let state = morningState(f, easy: easy), state.count + 1 + raise.count <= maxBodyCharacters {
                sentences.append(state)
            }
            sentences.append(raise)
        }
        var text = body(sentences)
        if offers, !raises, !f.checkInDone, text.count + morningCheckInAsk.count < maxBodyCharacters {
            text += " " + morningCheckInAsk
        }
        let session = f.restDay ? nil : f.session
        // Quiet delivery for the offer; the usual priority otherwise.
        let priority: Priority = offers ? .low : (easy ? .high : (session != nil ? .normal : .low))
        return Message(kind: .morning, title: title, body: text, link: todayLink, question: morningQuestion, priority: priority)
    }
}

// MARK: - Plain wording elsewhere

/// When other features stop being playful because mornings have run low:
/// the workout reminders (`WorkoutBanter.Facts.keepPlain`, set in the app's
/// `WorkoutVoice`). Pure, so it can be tested.
///
/// The app's choice, not a finding: no study tests jokes in reminders on low
/// days, and humour's small persuasive effect (r = .13, mostly on attitudes:
/// Walter et al., Hum Commun Res 2018) is not worth a joke landing badly.
/// The reminder learns only "keep it plain", never why.
public enum MoodCare {
    /// True while the low-mood rule is in play: three or more low mornings in
    /// the last seven days (`LowMoodRule.Finding.weekApplies`). It lets go by
    /// itself as better mornings push the low ones out of the week.
    public static func keepPlain(lowMood: LowMoodRule.Finding?) -> Bool {
        lowMood?.weekApplies == true
    }
}
