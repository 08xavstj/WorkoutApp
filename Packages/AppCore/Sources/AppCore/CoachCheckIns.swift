import Foundation

/// The messages the coach sends first: a morning briefing, a note after a
/// workout and an evening wind-down. Pure rules: they decide *what* to say
/// from facts the app already has, and *whether* to say anything at all.
/// The app (`CoachNudges`) decides when, schedules the notification and may
/// let the on-device model reword the body (`acceptRephrase` checks it).
///
/// Evidence and choices:
/// - **Few, well-timed, skippable.** Support works when it arrives at a moment
///   the person can act on it (just-in-time adaptive interventions:
///   Nahum-Shani et al., Ann Behav Med 2018), and the effect of repeated
///   prompts fades with habituation (Klasnja et al., Ann Behav Med 2019:
///   +107% at first, +14% on average). So at most one message of each kind a
///   day, none when there is nothing new, and fewer when they go unopened.
///   The caps (3 a day, back off after 3 unopened) are app choices; no trial
///   tested these exact numbers.
/// - **Autonomy-supportive wording.** Options and reasons, never "should",
///   "must" or "missed" (self-determination theory: Teixeira et al., Int J
///   Behav Nutr Phys Act 2012; Ntoumanis et al., Health Psychol Rev 2021).
///   A low score is an easy day, not a day off (HRV-guided training:
///   Javaloyes et al., IJSPP 2019), as in `CoachAnswers`.
/// - **Morning = a plan with a choice** (docs/research/behaviour-change.md
///   rec. 9): today's session from the adaptive week, with the short version
///   as an equal option.
public enum CoachCheckIns {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case morning, postWorkout, evening

        /// For Settings and the Coach tab.
        public var label: String {
            switch self {
            case .morning: "Morning"
            case .postWorkout: "After workouts"
            case .evening: "Evening"
            }
        }
    }

    /// How much a message matters today: a low recovery or a new best is
    /// worth the interruption more than a routine line.
    public enum Priority: Int, Codable, Sendable, Comparable {
        case low = 0, normal, high

        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Message: Codable, Sendable, Equatable {
        public var kind: Kind
        /// At most `maxTitleCharacters`.
        public var title: String
        /// One or two sentences, at most `maxBodyCharacters`.
        public var body: String
        /// Where a tap goes, e.g. "workoutapp://today".
        public var link: String
        /// A question the Coach tab can answer from data ("Ask the coach").
        public var question: String?
        public var priority: Priority

        public init(kind: Kind, title: String, body: String, link: String, question: String?, priority: Priority) {
            self.kind = kind
            self.title = title
            self.body = body
            self.link = link
            self.question = question
            self.priority = priority
        }

        /// Same key means nothing new to say.
        public var key: String { "\(kind.rawValue)|\(title)|\(body)" }
    }

    // MARK: Limits and timing (app choices unless cited)

    /// Lock-screen banners show a short title in full (app choice).
    public static let maxTitleCharacters = 40
    /// About four lines of a notification body before iOS truncates it (app choice).
    public static let maxBodyCharacters = 200
    /// Never more than this many coach messages a day (app choice; Klasnja 2019 on habituation).
    public static let maxPerDay = 3
    /// Unopened messages in a row before the evening message stops notifying (app choice).
    public static let backOffAfterUnopened = 3
    /// Unopened in a row before the morning message stops notifying too (app choice: twice the first step).
    public static let quietMorningAfterUnopened = 6
    /// A delivered message counts as ignored only after this long (app choice).
    public static let ignoredAfterHours = 3.0
    /// Morning briefing: this long after your usual wake time, once you're up (app choice).
    public static let morningMinutesAfterWake = 30
    /// Evening note: this long before the bed-by window starts, time to act on it (app choice).
    public static let eveningMinutesBeforeBed = 60
    /// Without sleep data (app choice).
    public static let fallbackMorningMinutes = 7 * 60 + 30
    public static let fallbackEveningMinutes = 21 * 60 + 30
    /// After a workout: once you've left the gym, still inside the couple of
    /// hours the protein advice is about (app choice; Kerksick et al., JISSN 2017).
    public static let postWorkoutDelayMinutes = 20
    /// Sleep debt worth a mention, hours (`SleepDebt` calls under 1 h "none").
    public static let notableSleepDebtHours = 1.0
    /// A night this much under your need counts as short (app choice).
    public static let shortNightHours = 1.0

    // MARK: Protein after training

    /// Protein in the meal after training: about 0.3 g/kg (the middle of the
    /// 0.25-0.4 g/kg per meal range) and 20-40 g in absolute terms (ISSN
    /// position stands: Jäger et al., JISSN 2017; Kerksick et al., JISSN 2017).
    /// The day's total matters more than the timing (Morton et al., Br J Sports
    /// Med 2018), so the wording says "helps", not "needs".
    public static let proteinPerKgPerMeal = 0.3
    public static let proteinMealRange = 20.0...40.0

    /// Grams for the meal after training, rounded to 5 g; 30 g without a weight.
    public static func postWorkoutProteinGrams(bodyMassKg: Double?) -> Int {
        guard let bodyMassKg, bodyMassKg > 0 else { return 30 }
        let grams = min(proteinMealRange.upperBound, max(proteinMealRange.lowerBound, bodyMassKg * proteinPerKgPerMeal))
        return Int((grams / 5).rounded()) * 5
    }

    // MARK: Questions and links

    /// The app's URL scheme (project.yml CFBundleURLSchemes).
    public static let scheme = "workoutapp"
    public static let todayLink = "\(scheme)://today"
    public static let eveningCheckInLink = "\(scheme)://checkin/evening"

    /// "workoutapp://coach?q=How%20should%20I%20train%20today%3F"
    public static func coachLink(question: String?) -> String {
        guard let question else { return "\(scheme)://coach" }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "coach"
        components.queryItems = [URLQueryItem(name: "q", value: question)]
        return components.string ?? "\(scheme)://coach"
    }

    /// The follow-up questions; each routes to a data answer (`CoachIntent.question`, tested).
    public static let morningQuestion = "How should I train today?"
    public static let postWorkoutQuestion = "What should I eat after?"
    public static let eveningQuestion = "Plan my next workout"

    // MARK: - Facts

    /// A session from the weekly plan, as the messages describe it.
    public struct Session: Sendable, Equatable {
        /// "Upper", "Full body".
        public var name: String
        public var minutes: Int
        /// The fallback length (`PlannedDay.shortVersionMinutes`).
        public var shortMinutes: Int?
        /// Not on its planned weekday.
        public var moved: Bool
        /// The short version was asked for today (short on time or tired).
        public var offerShort: Bool
        /// The muscles it loads are sore and the week has no room to wait.
        public var easy: Bool
        /// The adaptive week's own sentence, e.g. "Lower moved to Thu: legs still sore."
        public var note: String?

        public init(name: String, minutes: Int, shortMinutes: Int? = nil, moved: Bool = false, offerShort: Bool = false,
                    easy: Bool = false, note: String? = nil) {
            self.name = name
            self.minutes = minutes
            self.shortMinutes = shortMinutes
            self.moved = moved
            self.offerShort = offerShort
            self.easy = easy
            self.note = note
        }

        /// A day of the adaptive week (`AdaptiveWeek.Slot`).
        public init(slot: AdaptiveWeek.Slot) {
            self.init(name: slot.focus.shortTitle, minutes: slot.session.minutes,
                      shortMinutes: slot.session.shortVersionMinutes, moved: slot.isMoved,
                      offerShort: slot.short, easy: slot.easy, note: slot.note)
        }

        /// "Upper · 60 min"
        public var label: String { "\(name) · \(minutes) min" }

        /// The short version, when it is shorter than the session.
        var shortOption: Int? {
            guard let shortMinutes, shortMinutes > 0, shortMinutes < minutes else { return nil }
            return shortMinutes
        }
    }

    public struct MorningFacts: Sendable, Equatable {
        /// Today's recovery, 0-100; nil before last night's data is in.
        public var recovery: Int?
        public var recoveryCalibrated = true
        /// The 7-day HRV average is below your normal range.
        public var hrvBelowNormal = false
        /// The score input that moved it most, in words: "resting heart rate up 4 bpm".
        public var recoveryReason: String?
        public var restMode = false
        /// Today is a rest day in the plan (`TrainingDayPlanner.Guidance.isRestDay`).
        public var restDay = false
        public var session: Session?
        public var sleepHours: Double?
        public var sleepNeedHours: Double?
        public var sleepDebtHours: Double?
        /// Tonight's bed-by window, "22:00–22:30".
        public var bedByText: String?
        /// Latest coffee for your usual bedtime (`CaffeineTiming.cutoffMinutes`), "2:10 pm".
        public var caffeineCutoffText: String?

        public init() {}
    }

    public struct PostWorkoutFacts: Sendable, Equatable {
        public var name: String
        public var minutes: Int
        public var workingSets: Int
        /// Total volume in the user's unit, "8,450 kg".
        public var volumeText: String?
        /// Exercises with a new personal record (`SetFeedback.records`).
        public var recordExercises: [String] = []
        /// Lifts that earned a step up since last time, e.g. "Squat +2.5 kg" (`WorkoutSummary.Progression`).
        public var progressions: [String] = []
        public var nextSession: Session?
        /// "tomorrow", "on Thursday".
        public var nextDayText: String?
        public var bodyMassKg: Double?
        public var goals: Goals?
        public var proteinSoFarGrams: Double?
        public var proteinTargetGrams: Double?
        public var bedByText: String?

        public init(name: String, minutes: Int, workingSets: Int) {
            self.name = name
            self.minutes = minutes
            self.workingSets = workingSets
        }
    }

    public struct EveningFacts: Sendable, Equatable {
        public var restMode = false
        /// Tonight's bed-by window, "22:00–22:30".
        public var bedByText: String?
        /// Why that window (`BedtimeWindow.Result.reason`): "8 h need, up at 6:30".
        public var bedByReason: String?
        public var tomorrowSession: Session?
        /// Caffeine logged today past the cut-off for tonight (`CaffeineTiming.isTooLate`).
        public var lateCaffeine = false
        /// Standard drinks logged today.
        public var drinksToday: Int?
        public var checkInDone = false

        public init() {}
    }

    // MARK: - Morning

    /// The morning briefing, or nil when there is nothing useful to say
    /// (rest mode, or no recovery, session or sleep debt to speak of).
    public static func morning(_ f: MorningFacts) -> Message? {
        if f.restMode { return nil } // Rest mode pauses nudges (Settings › Rest mode).
        let debt = (f.sleepDebtHours ?? 0) >= notableSleepDebtHours ? f.sleepDebtHours : nil
        guard f.recovery != nil || f.session != nil || debt != nil else { return nil }

        let easy = isEasy(f)
        let session = f.restDay ? nil : f.session
        let title: String
        if let session {
            title = fit("Today: \(easy ? "easy " : "")\(session.label)", maxTitleCharacters)
        } else if f.restDay {
            title = "Rest day today"
        } else if let recovery = f.recovery {
            title = "Recovery \(recovery)% this morning"
        } else {
            title = "Good morning"
        }

        var sentences: [String] = []
        if let state = morningState(f, easy: easy) { sentences.append(state) }
        if let tip = morningTip(f, session: session, easy: easy, debt: debt) { sentences.append(tip) }
        guard !sentences.isEmpty else { return nil }

        let priority: Priority = easy ? .high : (session != nil ? .normal : .low)
        return Message(kind: .morning, title: title, body: body(sentences), link: todayLink,
                       question: morningQuestion, priority: priority)
    }

    static func isEasy(_ f: MorningFacts) -> Bool {
        if f.hrvBelowNormal || f.session?.easy == true { return true }
        guard let recovery = f.recovery else { return false }
        return recovery < RecoveryCalculator.moderateBand.lowerBound
    }

    /// "Recovery is 28% (resting heart rate up 5 bpm), so an easy day suits: lighter and shorter still counts."
    static func morningState(_ f: MorningFacts, easy: Bool) -> String? {
        guard let recovery = f.recovery else {
            guard let session = f.session, !f.restDay else { return nil }
            return session.moved ? (session.note ?? "\(session.name) moved to today.") : "\(session.name) is next in your week."
        }
        let detail = [f.recoveryReason, f.recoveryCalibrated ? nil : "baseline still building"].compactMap { $0 }
        let reading = "Recovery is \(recovery)%" + (detail.isEmpty ? "" : " (\(detail.joined(separator: "; ")))")
        if f.restDay { return "\(reading); a walk or easy mobility is plenty on a rest day." }
        if f.hrvBelowNormal { return "\(reading) and your 7-day HRV is below normal, so an easy day suits." }
        if easy { return "\(reading), so an easy day suits: lighter and shorter still counts." }
        if recovery < RecoveryCalculator.highBand.lowerBound { return "\(reading): normal, so your usual session suits." }
        return "\(reading): a good day for a harder or longer session."
    }

    /// One thing to do, best first: the choice of the short version, then
    /// sleep debt, then caffeine after a short night.
    static func morningTip(_ f: MorningFacts, session: Session?, easy: Bool, debt: Double?) -> String? {
        if let session, let short = session.shortOption, easy || session.offerShort {
            return "Your call: \(session.minutes) min with lighter loads, or the \(short)-min version."
        }
        if let debt, let bedBy = f.bedByText {
            return "Sleep debt is \(hours(debt)) h; in bed by \(bedBy) tonight starts to repay it."
        }
        if let asleep = f.sleepHours, let need = f.sleepNeedHours, need - asleep >= shortNightHours,
           let cutoff = f.caffeineCutoffText {
            // Caffeine within about 9 h of bed costs ~45 min of sleep (Gardiner et al., Sleep Med Rev 2023).
            return "After a short night, a last coffee by \(cutoff) protects tonight's sleep."
        }
        if let session, let short = session.shortOption {
            return "If the day gets tight, the \(short)-min version counts too."
        }
        if let debt {
            return "Sleep debt is \(hours(debt)) h; an earlier night repays it best."
        }
        return nil
    }

    // MARK: - After a workout

    /// The note after a session, or nil for a session with no working sets.
    public static func postWorkout(_ f: PostWorkoutFacts) -> Message? {
        guard f.workingSets > 0 else { return nil }
        let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : f.name
        let title: String
        if !f.recordExercises.isEmpty {
            let bests = f.recordExercises.count == 1 ? "a new best" : "\(f.recordExercises.count) new bests"
            title = fit(name, maxTitleCharacters - bests.count - 7) + " done: " + bests
        } else if !f.progressions.isEmpty {
            let moved = f.progressions.count == 1 ? "1 lift up" : "\(f.progressions.count) lifts up"
            title = fit(name, maxTitleCharacters - moved.count - 7) + " done: " + moved
        } else {
            title = fit(name, maxTitleCharacters - 5) + " done"
        }

        var first = "\(f.workingSets) sets in \(f.minutes) min"
        if let volume = f.volumeText { first += ", \(volume) lifted" }
        if let record = f.recordExercises.first {
            first += ", with a new best on \(record)"
        } else if let step = f.progressions.first {
            first += "; \(step) since last time"
        }
        let sentences = [first + ".", recoveryAdvice(f)]
        let priority: Priority = (f.recordExercises.isEmpty && f.progressions.isEmpty) ? .low : .normal
        return Message(kind: .postWorkout, title: title, body: body(sentences),
                       link: coachLink(question: postWorkoutQuestion), question: postWorkoutQuestion, priority: priority)
    }

    /// Food, then sleep, then the next session, tailored to the goal:
    /// endurance adds carbohydrate (about 1-1.2 g/kg/h when the next session
    /// is within a day, Kerksick et al., JISSN 2017); every goal gets the
    /// protein line (Jäger et al., JISSN 2017), and losing weight keeps it
    /// because a deficit makes protein matter more for keeping muscle
    /// (Morton et al., Br J Sports Med 2018).
    static func recoveryAdvice(_ f: PostWorkoutFacts) -> String {
        let next = f.nextSession.map { session in
            "; next up: \(session.name)" + (f.nextDayText.map { " \($0)" } ?? "")
        } ?? ""
        let proteinDone: Bool = {
            guard let eaten = f.proteinSoFarGrams, let target = f.proteinTargetGrams, target > 0 else { return false }
            return eaten >= target
        }()
        if proteinDone {
            if let bedBy = f.bedByText {
                return "Protein is covered today, so sleep is the next lever: in bed by \(bedBy)" + next + "."
            }
            return "Protein is covered today, so a full night's sleep is the next lever" + next + "."
        }
        let grams = postWorkoutProteinGrams(bodyMassKg: f.bodyMassKg)
        let endurance = f.goals?.focuses.contains(.endurance) == true
        let meal = endurance ? "a meal with carbs and about \(grams) g of protein" : "a meal with about \(grams) g of protein"
        return "In the next couple of hours, \(meal) helps the session pay off" + next + "."
    }

    // MARK: - Evening

    /// The evening note, or nil when it would add nothing (no bed-by window,
    /// nothing planned tomorrow, nothing logged worth a word, check-in done).
    public static func evening(_ f: EveningFacts) -> Message? {
        let drinks = (f.drinksToday ?? 0) >= 1 ? f.drinksToday : nil
        guard f.bedByText != nil || f.tomorrowSession != nil || drinks != nil || f.lateCaffeine || !f.checkInDone else {
            return nil
        }
        let session = f.restMode ? nil : f.tomorrowSession
        let title: String
        if let bedBy = f.bedByText {
            title = fit("In bed by \(bedBy)", maxTitleCharacters)
        } else if let session {
            title = fit("Tomorrow: \(session.label)", maxTitleCharacters)
        } else {
            title = "Evening check-in"
        }

        var sentences: [String] = []
        if f.bedByText != nil, let reason = f.bedByReason {
            sentences.append("Worked back from \(reason)" + (session.map { ", ready for \($0.name) tomorrow." } ?? "."))
        } else if f.bedByText != nil, let session {
            sentences.append("That sets you up for \(session.label) tomorrow.")
        } else if let session {
            sentences.append(session.note ?? "\(session.name) is next, \(session.minutes) min.")
        }
        if let drinks {
            // Alcohol lowers overnight HRV, more with each drink (Pietilä et al., JMIR Ment Health 2018).
            let count = drinks == 1 ? "a drink" : "\(drinks) drinks"
            sentences.append("With \(count) today, tomorrow's recovery may read lower; water and your usual bedtime help.")
        } else if f.lateCaffeine {
            // Caffeine within about 9 h of bed cuts sleep by ~45 min on average (Gardiner et al., Sleep Med Rev 2023).
            sentences.append("Today's late caffeine can cost some sleep, so tomorrow's score may dip a little.")
        } else if !f.checkInDone {
            sentences.append("A 45-second check-in: one win and how today felt.")
        }
        guard !sentences.isEmpty else { return nil }
        let link = f.checkInDone ? coachLink(question: eveningQuestion) : eveningCheckInLink
        let priority: Priority = drinks != nil || f.lateCaffeine ? .normal : .low
        return Message(kind: .evening, title: title, body: body(Array(sentences.prefix(2))), link: link,
                       question: eveningQuestion, priority: priority)
    }

    // MARK: - Whether to send

    /// A coach message already scheduled or delivered (the app's inbox).
    public struct Sent: Codable, Sendable, Equatable {
        public var kind: Kind
        public var deliverAt: Date
        /// Sent as a notification (false: shown only in the Coach tab).
        public var notified: Bool
        /// Tapped, or seen in the Coach tab.
        public var opened: Bool
        public var key: String

        public init(kind: Kind, deliverAt: Date, notified: Bool, opened: Bool, key: String) {
            self.kind = kind
            self.deliverAt = deliverAt
            self.notified = notified
            self.opened = opened
            self.key = key
        }
    }

    public enum BackOff: Int, Sendable, Comparable {
        case none = 0
        /// The evening message goes to the Coach tab only.
        case noEvening
        /// Evening and morning go to the Coach tab only; after-workout notes still notify.
        case noEveningOrMorning

        public static func < (lhs: BackOff, rhs: BackOff) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Notified messages left unopened in a row, newest first, counting only
    /// those delivered at least `ignoredAfterHours` ago.
    public static func unopenedStreak(_ history: [Sent], now: Date) -> Int {
        let settled = now.addingTimeInterval(-ignoredAfterHours * 3600)
        var streak = 0
        for sent in history.filter({ $0.notified && $0.deliverAt <= settled }).sorted(by: { $0.deliverAt > $1.deliverAt }) {
            if sent.opened { break }
            streak += 1
        }
        return streak
    }

    public static func backOff(_ history: [Sent], now: Date) -> BackOff {
        let streak = unopenedStreak(history, now: now)
        if streak >= quietMorningAfterUnopened { return .noEveningOrMorning }
        if streak >= backOffAfterUnopened { return .noEvening }
        return .none
    }

    public enum Delivery: Sendable, Equatable {
        /// A notification at the fire time, and the Coach tab.
        case notify
        /// The Coach tab only.
        case inboxOnly
        /// Nothing: already said today, nothing new, or over the daily cap.
        case skip
    }

    /// How (and whether) to deliver `message` at `fire`. Messages of the same
    /// kind not yet delivered are being replaced, so they don't count.
    public static func delivery(for message: Message, at fire: Date, history: [Sent], now: Date,
                                calendar: Calendar = .current) -> Delivery {
        let delivered = history.filter { $0.deliverAt <= now }
        let sameDay = history.filter { calendar.isDate($0.deliverAt, inSameDayAs: fire) }
        let others = sameDay.filter { $0.kind != message.kind || $0.deliverAt <= now }
        if sameDay.contains(where: { $0.kind == message.kind && $0.deliverAt <= now }) { return .skip }
        if others.count >= maxPerDay { return .skip }
        if let last = delivered.filter({ $0.kind == message.kind }).max(by: { $0.deliverAt < $1.deliverAt }),
           last.key == message.key {
            return .skip
        }
        if fire <= now { return .inboxOnly }
        switch (message.kind, backOff(history, now: now)) {
        case (.evening, .noEvening), (.evening, .noEveningOrMorning), (.morning, .noEveningOrMorning):
            return .inboxOnly
        default:
            return .notify
        }
    }

    // MARK: - Timing

    /// Quiet hours, minutes after midnight; the span may cross midnight (22:00-07:00).
    public struct QuietHours: Codable, Sendable, Equatable {
        public var startMinutes: Int
        public var endMinutes: Int

        public init(startMinutes: Int, endMinutes: Int) {
            self.startMinutes = startMinutes
            self.endMinutes = endMinutes
        }

        public func contains(_ minutes: Int) -> Bool {
            let m = ((minutes % 1440) + 1440) % 1440
            if startMinutes == endMinutes { return false }
            if startMinutes < endMinutes { return m >= startMinutes && m < endMinutes }
            return m >= startMinutes || m < endMinutes
        }
    }

    /// Default quiet hours, 22:00-07:00 (app choice).
    public static let defaultQuietHours = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)

    /// The morning time: `morningMinutesAfterWake` after the next wake time, or the fallback day's 7:30.
    public static func morningFire(wake: Date?, fallbackDay: Date, calendar: Calendar = .current) -> Date? {
        if let wake { return wake.addingTimeInterval(TimeInterval(morningMinutesAfterWake * 60)) }
        return at(fallbackMorningMinutes, on: fallbackDay, calendar: calendar)
    }

    /// The evening time: `eveningMinutesBeforeBed` before the bed-by window, or the fallback day's 21:30.
    public static func eveningFire(bedByStart: Date?, fallbackDay: Date, calendar: Calendar = .current) -> Date? {
        if let bedByStart { return bedByStart.addingTimeInterval(TimeInterval(-eveningMinutesBeforeBed * 60)) }
        return at(fallbackEveningMinutes, on: fallbackDay, calendar: calendar)
    }

    /// `fire` moved out of quiet hours: the morning waits for their end, the
    /// evening comes 15 minutes before they start, and an after-workout note
    /// inside them isn't sent as a notification (nil).
    public static func outsideQuietHours(_ fire: Date, kind: Kind, quiet: QuietHours?, calendar: Calendar = .current) -> Date? {
        guard let quiet else { return fire }
        let parts = calendar.dateComponents([.hour, .minute], from: fire)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard quiet.contains(minutes) else { return fire }
        let day = calendar.startOfDay(for: fire)
        switch kind {
        case .postWorkout:
            return nil
        case .morning:
            guard let end = at(quiet.endMinutes, on: day, calendar: calendar) else { return nil }
            return end >= fire ? end : calendar.date(byAdding: .day, value: 1, to: end)
        case .evening:
            let target = quiet.startMinutes - 15
            guard target >= 0, !quiet.contains(target), let start = at(target, on: day, calendar: calendar) else { return nil }
            // After midnight inside quiet hours: the evening before has gone, so no notification.
            return start <= fire ? start : nil
        }
    }

    static func at(_ minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: calendar.startOfDay(for: day))
    }

    // MARK: - On-device rewording

    /// The model's reworded body if it is safe to show, else nil (the app
    /// keeps its own words): one or two sentences within the length limit,
    /// no number the original didn't have, none of the controlling words the
    /// coach avoids, and the prompt's training-log words turned back into the
    /// app's (`CoachPromptVocabulary` swaps them on the way in).
    public static func acceptRephrase(_ candidate: String, of original: String) -> String? {
        var text = candidate
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for (pattern, replacement) in appVocabulary {
            text = text.replacingOccurrences(of: "\\b\(pattern)\\b", with: replacement, options: .regularExpression)
        }
        guard text.count >= 12, text.count <= maxBodyCharacters, sentenceCount(text) <= 2 else { return nil }
        let words = Set(CoachIntent.words(text))
        guard words.isDisjoint(with: controllingWords) else { return nil }
        guard Set(numbers(in: text)).isSubset(of: Set(numbers(in: original))) else { return nil }
        return text
    }

    /// Words the coach never uses (autonomy support: Ntoumanis 2021).
    static let controllingWords: Set<String> = ["should", "must", "missed", "failed", "fail", "lazy", "guilty"]

    /// `CoachPromptVocabulary.replacements` in reverse, for the words that map back unambiguously.
    static let appVocabulary: [(pattern: String, replacement: String)] = [
        ("Readiness score", "Recovery"), ("readiness score", "recovery"),
        ("Readiness", "Recovery"), ("readiness", "recovery"),
        ("Rest shortfall", "Sleep debt"), ("rest shortfall", "sleep debt"),
        ("Rest quality", "Sleep score"), ("rest quality", "sleep score"),
        ("Training load", "Strain"), ("training load", "strain"),
        ("Morning pulse", "Resting heart rate"), ("morning pulse", "resting heart rate"),
    ]

    /// "2.5", "22:00" → ["2.5", "22", "00"]: every run of digits, decimals kept together.
    static func numbers(in text: String) -> [String] {
        text.matches(of: /\d+(?:[.,]\d+)?/).map { String($0.output) }
    }

    static func sentenceCount(_ text: String) -> Int {
        text.matches(of: /[.!?](?=\s|$)/).count + (text.last.map { ".!?".contains($0) } == false ? 1 : 0)
    }

    // MARK: - Helpers

    static func body(_ sentences: [String]) -> String {
        fit(sentences.prefix(2).joined(separator: " "), maxBodyCharacters)
    }

    /// `text` cut to `limit` characters at a word, with an ellipsis.
    static func fit(_ text: String, _ limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let cut = text.prefix(limit - 1)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")) + "…"
    }

    /// "3.5", "2"
    static func hours(_ value: Double) -> String {
        let rounded = (value * 2).rounded() / 2
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
