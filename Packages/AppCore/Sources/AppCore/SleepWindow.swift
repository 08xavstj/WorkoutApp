import Foundation

/// The insomnia path: a shorter, fixed sleep window for a few weeks, for
/// someone who says he struggles to fall or stay asleep three or more nights a
/// week and that it affects his days. It is a mode of the bed-by window
/// (`BedtimeWindow.sleepWindow`), shown only when it applies; for everyone
/// else nothing here appears. Research: docs/research/sleep-window.md.
///
/// What it is, and why these parts and no others:
/// - A fixed wake time every day and a time in bed set to recent sleep, widened
///   as sleep fills it ("sleep restriction"), with bed only when sleepy and out
///   of bed when awake ("stimulus control"). In a component network
///   meta-analysis of 241 trials these two were the behavioural parts that
///   added to remission (odds ratios 1.49 and 1.43); sleep-hygiene education
///   added nothing (1.01) and relaxation may hinder (0.81) (Furukawa et al.,
///   JAMA Psychiatry 2024). So there are no tips, breathing or relaxation here.
/// - Alone, the window beat sleep-hygiene advice in 642 adults in primary
///   care: insomnia severity −3.05 points at six months, d = −0.74 (Kyle et
///   al., Lancet 2023, the HABIT trial); as a single component it has a
///   conditional recommendation (Edinger et al., J Clin Sleep Med 2021, AASM).
/// - The rules are the HABIT trial's, from its published intervention table
///   (Kyle et al., BMJ Open 2020;10:e036248, supplementary table 1), because
///   it is the largest trial, was delivered briefly and then self-run by the
///   participant, and is the more cautious rule where manuals differ.
///
/// Limits, all from the sources:
/// - It makes people sleepier and slower for the first weeks: objective sleep
///   fell by 91, 78 and 69 minutes on nights 1, 8 and 22, sleepiness scores
///   were raised in weeks 1-3 and reaction times slowed, all back to baseline
///   at three months (Kyle et al., Sleep 2014). The app warns about driving
///   every time the plan is shown.
/// - It is not offered with the conditions in `Exclusion`.
/// - A wrist tracker over-counts sleep in people lying awake (European
///   Insomnia Guideline, Riemann et al., J Sleep Res 2023: devices based on
///   actigraphy "overestimate sleep" and trackers "should in general be
///   discouraged for patients with insomnia" until validated). So the owner's
///   answers open the path, never the tracker; the tracker's efficiency is
///   called an estimate; and every place the tracker's error matters it errs
///   towards a longer window.
/// - Nothing here is care from a clinician and the copy never says so.
public enum SleepWindow {

    // MARK: - Numbers

    /// Nights a week of trouble that count: "at least three nights per week
    /// for 3 months with associated daytime sequelae" are the minimal criteria
    /// for chronic insomnia (European Insomnia Guideline 2023, after DSM-5 and
    /// ICSD-3). The app applies them to the owner's answers; it diagnoses nothing.
    public static let nightsPerWeek = 3
    /// See `nightsPerWeek`.
    public static let months = 3

    /// Minutes added to recent average sleep for the first window. The HABIT
    /// trial and Spielman's original method use average sleep alone; a
    /// variant uses sleep plus 30 minutes (Edinger et al., JAMA 2001, as
    /// described in Kyle et al., Sleep 2014; Edinger's paper not re-verified).
    /// The longer window is the more cautious one, so +30.
    public static let extraMinutes = 30
    /// Shortest time in bed, minutes. Trials used 4.5 h (Spielman 1987, per
    /// Kyle 2014) or 5 h (Kyle 2014; HABIT); the European guideline lists
    /// "4.5, 5 or 6 hr" as the minimums in use. Six is the most cautious, and
    /// Kyle 2014 warns a 4.5 h minimum "may lead to impairment greater than
    /// that observed" at 5 h. Without a clinician watching, six.
    public static let floorMinutes = 360
    /// Minutes the window moves at a weekly review (HABIT; Kyle 2014).
    public static let stepMinutes = 15
    /// Days between reviews: weekly, on the week's average (HABIT).
    public static let reviewDays = 7
    /// Whole-percent sleep efficiency from which the window widens. HABIT:
    /// "SE ≥ 85% increase TIB by 15 minutes". Spielman's rule as used in Kyle
    /// 2014 widens only at 90%; widening sooner is the more cautious choice
    /// (the guideline gives both: "thresholds of > 85% or 90%").
    public static let widenPercent = 85
    /// Whole-percent sleep efficiency under which the window narrows. HABIT:
    /// "SE = 80-84% no change", "SE ≤ 79% decrease TIB by 15 minutes". Kyle
    /// 2014 narrows under 85%; narrowing later is the more cautious choice.
    public static let narrowBelowPercent = 80
    /// Nights with data a week needs before the window is changed (app's
    /// choice; HABIT averaged a 7-day diary, and a missing night is not a bad night).
    public static let minimumReviewNights = 5
    /// Nights the first window is averaged over, and the fewest needed. HABIT
    /// used a 7-day diary; the app has more nights and uses up to 14, like
    /// `SleepDebt`, so one odd night counts for less (app's choice).
    public static let baselineNights = 14
    public static let minimumBaselineNights = 7
    /// Weeks after which the path ends by itself. Spielman's programme ran 8
    /// weeks (Spielman et al., Sleep 1987) and "CBT-I and classic SRT ... often
    /// last for 6-8 w" (Kyle 2014). Past that, still struggling means seeing someone.
    public static let maximumWeeks = 8
    /// Weekly reviews in a row without a wider window after which the app
    /// suggests seeing someone (app's choice; four weeks was the whole of
    /// HABIT's nurse-led phase).
    public static let stalledReviews = 4
    /// "About 20 minutes" awake before getting up. The guideline's rule has no
    /// number ("get out of bed when unable to sleep", AASM 2021); 15-20 minutes
    /// is the usual clinic handout wording (seen in a search summary only, not
    /// re-verified). The copy says "what feels like" so nobody watches a clock.
    public static let awakeMinutes = 20
    /// Sleep efficiency under which four weeks of tracker nights make the app
    /// ask the question: 85% or more is the mark of good sleep (Ohayon et al.,
    /// Sleep Health 2017). It only opens the question, never the path.
    public static let askBelowPercent = 85
    /// Days of history the "should the app ask" check looks at, the nights it
    /// needs, and the poor mornings that count (three a week for four weeks:
    /// `nightsPerWeek`; app's choice of window).
    public static let askDays = 28
    public static let askMinimumNights = 20
    public static let askPoorMornings = 12
    /// After an answer the app doesn't raise the question again by itself for
    /// this long (app's choice: the criteria look back three months).
    public static let askAgainDays = 90
    /// Main sleeps in the daytime, out of the last 14, that read as shift
    /// work or a body clock far off the night (app's choice).
    public static let shiftDaytimeSleeps = 3
    /// The share of time in bed asleep that the regular bed-by window assumes
    /// (`BedtimeWindow.assumedSleepEfficiency`); the path ends when the window
    /// is back to need ÷ this.
    static var regularEfficiency: Double { BedtimeWindow.assumedSleepEfficiency }

    // MARK: - The two questions

    /// How often, and for how long.
    public enum Frequency: String, Codable, Sendable, CaseIterable, Identifiable {
        case fewer
        case recent
        case lasting

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .fewer: "Fewer than \(SleepWindow.nightsPerWeek) nights a week"
            case .recent: "\(SleepWindow.nightsPerWeek) or more nights a week, for under \(SleepWindow.months) months"
            case .lasting: "\(SleepWindow.nightsPerWeek) or more nights a week, for \(SleepWindow.months) months or longer"
            }
        }
    }

    public static let frequencyQuestion = "How often is it hard to fall asleep or to stay asleep?"
    public static let daytimeQuestion = "Does it affect your days: tired, low, or hard to concentrate?"

    public struct Answers: Codable, Sendable, Equatable {
        public var frequency: Frequency
        public var affectsDay: Bool
        /// Start of the day they were given.
        public var day: Date

        public init(frequency: Frequency, affectsDay: Bool, day: Date) {
            self.frequency = frequency
            self.affectsDay = affectsDay
            self.day = day
        }

        /// Three or more nights a week, for three months, and the days suffer.
        public var applies: Bool { frequency == .lasting && affectsDay }

        /// What the app says when the path doesn't apply (nil when it does).
        public var note: String? {
            if applies { return nil }
            switch frequency {
            case .fewer:
                return "Then there's nothing to change. The odd bad night is normal."
            case .recent:
                return "A rough few weeks usually passes by itself, so the app leaves your nights alone. If it's still going after \(SleepWindow.months) months, answer again in Settings › Sleep & nutrition."
            case .lasting:
                return "If your days are fine, your sleep is doing its job. Nothing to change."
            }
        }
    }

    // MARK: - When the app asks by itself

    /// One morning check-in, as far as sleep goes.
    public struct MorningReport: Sendable, Equatable {
        public var day: Date
        /// 1 (exhausted) to 5 (great).
        public var rested: Int?
        /// 0, 1 or 2 (= 2 or more).
        public var nightWakings: Int?

        public init(day: Date, rested: Int? = nil, nightWakings: Int? = nil) {
            self.day = day
            self.rested = rested
            self.nightWakings = nightWakings
        }

        /// "Exhausted" or "Tired", or awake twice or more.
        public var isPoor: Bool { (rested ?? 5) <= 2 || (nightWakings ?? 0) >= 2 }
    }

    /// Why the app raises the question.
    public enum AskReason: Sendable, Equatable {
        /// Poor mornings in his own check-ins over the last four weeks.
        case mornings(Int)
        /// Tracker sleep efficiency over the last four weeks, whole percent.
        case efficiency(Int)

        public var text: String {
            switch self {
            case .mornings(let count):
                "You logged a tired morning or a broken night on \(count) of the last \(SleepWindow.askDays) days."
            case .efficiency(let percent):
                "Your tracker has you asleep for about \(percent)% of your nights over the last four weeks (an estimate)."
            }
        }
    }

    /// The data's reason to ask, his own check-ins first; nil when there is none.
    public static func askReason(mornings: [MorningReport], nights: [Night], now: Date = .now,
                                 calendar: Calendar = .current) -> AskReason? {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -askDays, to: today) else { return nil }
        let poor = mornings.filter { $0.day > from && $0.day <= now && $0.isPoor }.count
        if poor >= askPoorMornings { return .mornings(poor) }
        let recent = nights.filter { $0.date > from && $0.date <= now }
        if recent.count >= askMinimumNights, let percent = efficiencyPercent(recent), percent < askBelowPercent {
            return .efficiency(percent)
        }
        return nil
    }

    // MARK: - Who it isn't for

    /// Reasons not to offer the window. Each is from a source:
    /// - HABIT's exclusions (Kyle et al., BMJ Open 2020): pregnant or planning
    ///   pregnancy in the next 6 months; another sleep disorder (restless legs,
    ///   obstructive sleep apnoea, narcolepsy) diagnosed or positive on a
    ///   screening questionnaire; dementia or mild cognitive impairment;
    ///   epilepsy, schizophrenia or bipolar disorder; current suicidal ideation
    ///   with intent, or an attempt in the past 2 months; cancer treatment now
    ///   or major surgery planned; night, evening, early-morning or rotating
    ///   shift work; already having psychological help for insomnia.
    /// - AASM 2021: "may be contraindicated in ... those working in high risk
    ///   occupations (eg, heavy machinery operators or drivers) or those
    ///   predisposed to mania/hypomania poorly controlled seizure disorders or
    ///   excessive daytime sleepiness".
    /// - European guideline 2023: "any kind of epilepsy and conditions that
    ///   might be aggravated by sleep loss".
    /// The app is stricter than any one of them: it takes them all.
    public enum Exclusion: String, Codable, Sendable, CaseIterable, Identifiable {
        case shiftWork
        case apnoea
        case otherSleepDisorder
        case bipolarOrPsychosis
        case seizures
        case pregnancy
        case safetyCriticalWork
        case verySleepy
        case selfHarm
        case otherCondition
        case alreadyHelped

        public var id: String { rawValue }

        /// The line the owner ticks.
        public var question: String {
            switch self {
            case .shiftWork: "I work nights, evenings, early mornings or rotating shifts"
            case .apnoea: "I have sleep apnoea, or I've been told I stop breathing in my sleep"
            case .otherSleepDisorder: "I have restless legs, narcolepsy or another sleep disorder"
            case .bipolarOrPsychosis: "I have bipolar disorder, have had mania or hypomania, or have schizophrenia"
            case .seizures: "I have epilepsy or have had seizures"
            case .pregnancy: "I'm pregnant, or may be in the next six months"
            case .safetyCriticalWork: "I drive for work, or operate heavy machinery"
            case .verySleepy: "I already fight to stay awake in the day"
            case .selfHarm: "I've had thoughts of ending my life"
            case .otherCondition: "I have dementia or memory problems, am having cancer treatment, have major surgery coming, or have a condition that gets worse when I lose sleep"
            case .alreadyHelped: "I'm already working on my sleep with a clinician or a programme"
            }
        }

        /// Why the window isn't offered with it.
        public var reason: String {
            switch self {
            case .shiftWork:
                "A fixed wake time can't hold when your shifts move, and sleep on shifts needs a different plan."
            case .apnoea:
                "Sleep apnoea breaks up sleep and makes days sleepy by itself. Less time in bed on top of it isn't safe until it's been looked at."
            case .otherSleepDisorder:
                "Another sleep disorder needs its own plan first; a shorter window can make it worse."
            case .bipolarOrPsychosis:
                "Losing sleep can set off a manic episode or make symptoms worse."
            case .seizures:
                "Losing sleep can bring on seizures."
            case .pregnancy:
                "Trials of a shorter sleep window left out pregnancy, so there's nothing to say it's safe."
            case .safetyCriticalWork:
                "The first weeks slow your reactions. That's not a risk to take at the wheel or at a machine for a living."
            case .verySleepy:
                "If you're already fighting sleep in the day, less time in bed makes that worse, and something else may be behind it."
            case .selfHarm:
                "That matters more than a sleep schedule. Talk to a doctor or a crisis line today; if you're in danger, call your local emergency number."
            case .otherCondition:
                "With these, a few weeks of shorter sleep can do harm, so it needs a clinician's eye."
            case .alreadyHelped:
                "Follow the plan you already have. Two sets of rules get in each other's way."
            }
        }

        /// The ones the owner is asked about. Pregnancy isn't asked of a man.
        public static func asked(sex: BiologicalSex) -> [Exclusion] {
            allCases.filter { $0 != .pregnancy || sex != .male }
        }
    }

    /// What the app knows before it offers anything.
    public struct Screening: Sendable, Equatable {
        /// The lines the owner ticked.
        public var declared: Set<Exclusion>
        /// His STOP-Bang score; nil when never answered or over a year old.
        public var stopBangScore: Int?
        /// Nights in the last 30 on which Apple Watch flagged possible sleep apnoea.
        public var apnoeaFlaggedNights: Int
        /// Apple Watch's nightly breathing disturbances are running above his usual.
        public var breathingDisturbancesUp: Bool
        /// Main sleeps in the daytime over the last 14 nights (`daytimeSleeps`).
        public var daytimeSleeps: Int

        public init(declared: Set<Exclusion> = [], stopBangScore: Int? = nil, apnoeaFlaggedNights: Int = 0,
                    breathingDisturbancesUp: Bool = false, daytimeSleeps: Int = 0) {
            self.declared = declared
            self.stopBangScore = stopBangScore
            self.apnoeaFlaggedNights = apnoeaFlaggedNights
            self.breathingDisturbancesUp = breathingDisturbancesUp
            self.daytimeSleeps = daytimeSleeps
        }
    }

    /// One reason the window isn't offered, in words.
    public struct Refusal: Codable, Sendable, Equatable, Identifiable {
        public var exclusion: Exclusion
        public var reason: String
        public var id: String { exclusion.rawValue }

        public init(exclusion: Exclusion, reason: String) {
            self.exclusion = exclusion
            self.reason = reason
        }
    }

    public enum Decision: Sendable, Equatable {
        /// The apnoea screen (`StopBang`) hasn't been answered: that comes first.
        case screenApnoeaFirst
        case refuse([Refusal])
        case offer
    }

    public static let screenFirstText = "First, the sleep apnoea screen: eight yes/no questions. Apnoea breaks up sleep too, and a shorter window on top of it isn't safe, so it has to be ruled out before anything else."
    /// Said under every refusal.
    public static let refusalAdvice = "A GP or a sleep clinic can do this with you safely, or offer something that fits better. The app won't set a sleep window."
    public static let refusalTitle = "Not one to do alone"

    /// The data's refusals come first (apnoea, shift pattern), then what he
    /// ticked. With none, a missing apnoea screen is asked for before any offer:
    /// HABIT left out anyone positive on a sleep-disorder screening
    /// questionnaire; the app's is STOP-Bang, where 3 or more is a positive
    /// screen (Chung et al., Chest 2016).
    public static func decide(_ screening: Screening) -> Decision {
        var refusals: [Refusal] = []
        var apnoea: [String] = []
        if screening.apnoeaFlaggedNights > 0 {
            let nights = screening.apnoeaFlaggedNights
            apnoea.append("Your watch flagged possible sleep apnoea on \(nights) night\(nights == 1 ? "" : "s") in the last 30.")
        } else if screening.breathingDisturbancesUp {
            apnoea.append("Your watch's breathing disturbances are running above your usual this week.")
        }
        if let score = screening.stopBangScore, StopBang.risk(score: score) != .low {
            apnoea.append("Your sleep apnoea screen scored \(score) of 8, which is \(StopBang.risk(score: score).rawValue.lowercased()). The screen flags many people who turn out not to have apnoea, and only a sleep study can tell.")
        }
        if !apnoea.isEmpty || screening.declared.contains(.apnoea) {
            refusals.append(Refusal(exclusion: .apnoea, reason: (apnoea + [Exclusion.apnoea.reason]).joined(separator: " ")))
        }
        if screening.daytimeSleeps >= shiftDaytimeSleeps {
            refusals.append(Refusal(exclusion: .shiftWork, reason: "Your main sleep fell in the daytime on \(screening.daytimeSleeps) of the last 14 days. That reads as shift work, jet lag or a body clock running very late, and a fixed sleep window isn't the tool for any of them."))
        } else if screening.declared.contains(.shiftWork) {
            refusals.append(Refusal(exclusion: .shiftWork, reason: Exclusion.shiftWork.reason))
        }
        for exclusion in Exclusion.allCases where screening.declared.contains(exclusion) && exclusion != .apnoea && exclusion != .shiftWork {
            refusals.append(Refusal(exclusion: exclusion, reason: exclusion.reason))
        }
        if !refusals.isEmpty { return .refuse(refusals) }
        return screening.stopBangScore == nil ? .screenApnoeaFirst : .offer
    }

    /// Main sleeps among the last 14 nights whose midpoint falls between 08:00
    /// and 20:00: asleep through the day, as on night shifts.
    public static func daytimeSleeps(_ nights: [Night], calendar: Calendar = .current) -> Int {
        nights.suffix(baselineNights).filter { night in
            guard night.wake > night.bedtime else { return false }
            let middle = night.bedtime.addingTimeInterval(night.wake.timeIntervalSince(night.bedtime) / 2)
            let hour = calendar.component(.hour, from: middle)
            return hour >= 8 && hour < 20
        }.count
    }

    // MARK: - Nights and efficiency

    /// One night's main sleep from the tracker.
    public struct Night: Sendable, Equatable {
        /// Start of the day the night ended on.
        public var date: Date
        public var asleepHours: Double
        /// First fell asleep, and last woke.
        public var bedtime: Date
        public var wake: Date

        public init(date: Date, asleepHours: Double, bedtime: Date, wake: Date) {
            self.date = date
            self.asleepHours = asleepHours
            self.bedtime = bedtime
            self.wake = wake
        }

        /// Share of the night asleep, 0...1. An estimate that reads high: the
        /// tracker's night runs from first asleep to last awake, so time
        /// lying awake before sleep isn't in it, and lying still can count as
        /// sleep. Reading high widens the window sooner, the safe direction.
        public var efficiency: Double? {
            let span = wake.timeIntervalSince(bedtime)
            guard span > 0, asleepHours > 0 else { return nil }
            return min(1, asleepHours * 3600 / span)
        }
    }

    /// The nights' average efficiency as a whole percent (HABIT: "average
    /// sleep efficiency for 7 days"); nil without any.
    public static func efficiencyPercent(_ nights: [Night]) -> Int? {
        let values = nights.compactMap(\.efficiency)
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count) * 100).rounded())
    }

    /// The regular time in bed for a sleep need, minutes, to 5 (`BedtimeWindow`: need ÷ 0.9).
    public static func regularMinutes(sleepNeedHours: Double) -> Int {
        let need = min(11, max(6, sleepNeedHours))
        return Int((need / regularEfficiency * 60 / 5).rounded()) * 5
    }

    // MARK: - The first window

    public struct Proposal: Sendable, Equatable {
        /// Time in bed, minutes.
        public var windowMinutes: Int
        /// Recent average sleep it came from, minutes, and over how many nights.
        public var averageSleepMinutes: Int
        public var nightsUsed: Int
        /// The regular bed-by window's time in bed, minutes.
        public var regularMinutes: Int
        /// The fixed wake time offered, minutes after midnight (he can change it).
        public var wakeMinutes: Int

        /// False when recent sleep already fills the regular window: there's nothing to shorten.
        public var isShorter: Bool { windowMinutes <= regularMinutes - SleepWindow.stepMinutes }
    }

    /// Recent average sleep plus 30 minutes, never under six hours and never
    /// over the regular window; nil with under a week of nights or no wake time.
    public static func propose(nights: [Night], sleepNeedHours: Double, usualWakeMinutes: Int?) -> Proposal? {
        let recent = nights.suffix(baselineNights).filter { $0.asleepHours > 0 }
        guard recent.count >= minimumBaselineNights, let usualWakeMinutes else { return nil }
        let average = recent.map(\.asleepHours).reduce(0, +) / Double(recent.count) * 60
        let regular = regularMinutes(sleepNeedHours: sleepNeedHours)
        // Up to the next 5 minutes: the longer side.
        let raw = Int(((average + Double(extraMinutes)) / 5).rounded(.up)) * 5
        let window = min(regular, max(floorMinutes, raw))
        // The wake time to the nearest 5 minutes, so the bedtime is a round time too.
        let wake = (Int((Double(usualWakeMinutes) / 5).rounded()) * 5) % 1440
        return Proposal(windowMinutes: window, averageSleepMinutes: Int(average.rounded()), nightsUsed: recent.count,
                        regularMinutes: regular, wakeMinutes: wake)
    }

    /// Said instead of an offer when `Proposal.isShorter` is false.
    public static func nothingToShortenText(_ proposal: Proposal) -> String {
        "Your tracker has you asleep \(duration(proposal.averageSleepMinutes)) a night, close to all of your regular time in bed, so a shorter window has nothing to take away. What's left is the same wake time every day and bed only when sleepy. If nights are still bad in a month, a GP or a sleep clinic is the next step: a tracker can count lying still as sleep."
    }

    public static let needsNightsText = "This needs a week of nights from your watch or ring and a usual wake time. Wear it to bed and come back."

    // MARK: - The course

    /// What a weekly review did to the window.
    public enum Change: String, Codable, Sendable {
        case widened
        case held
        case narrowed
        /// Under 80% but already at six hours.
        case heldAtFloor
        /// Under 80% in a week he said he was too sleepy: never narrowed then.
        case heldSleepy
        /// Fewer than five nights recorded.
        case heldFewNights
        /// Rest mode (ill): nothing is tightened or judged.
        case heldResting
    }

    public struct Review: Codable, Sendable, Equatable {
        /// 1 for the first week.
        public var week: Int
        public var nights: Int
        /// Whole percent; nil with too few nights.
        public var efficiencyPercent: Int?
        public var change: Change
        /// The window after the review, minutes.
        public var windowMinutes: Int

        public init(week: Int, nights: Int, efficiencyPercent: Int?, change: Change, windowMinutes: Int) {
            self.week = week
            self.nights = nights
            self.efficiencyPercent = efficiencyPercent
            self.change = change
            self.windowMinutes = windowMinutes
        }

        /// "Week 2: asleep for about 88% of the window (an estimate), so it's 15 minutes longer."
        public var text: String {
            let step = SleepWindow.stepMinutes
            let measured = efficiencyPercent.map { "asleep for about \($0)% of your time in bed (an estimate)" }
            switch change {
            case .widened:
                return "Week \(week): \(measured ?? "sleep filled the window"), so the window is \(step) minutes longer."
            case .held:
                return "Week \(week): \(measured ?? "no clear change"), so the window stays."
            case .narrowed:
                return "Week \(week): \(measured ?? "a lot of time awake"), so the window is \(step) minutes shorter."
            case .heldAtFloor:
                return "Week \(week): \(measured ?? "a lot of time awake"). The window stays at \(SleepWindow.duration(SleepWindow.floorMinutes)); it never goes lower."
            case .heldSleepy:
                return "Week \(week): \(measured ?? "a lot of time awake"), but you were too sleepy, so the window stays."
            case .heldFewNights:
                return "Week \(week): only \(nights) night\(nights == 1 ? "" : "s") recorded, too few to judge, so the window stays."
            case .heldResting:
                return "Week \(week): rest mode was on, so the window stays."
            }
        }
    }

    public struct Course: Codable, Sendable, Equatable {
        /// Start of the day it began; the first night is that evening's.
        public var startDay: Date
        /// The fixed wake time, minutes after midnight.
        public var wakeMinutes: Int
        /// Time in bed now, minutes.
        public var windowMinutes: Int
        public var initialWindowMinutes: Int
        public var averageSleepMinutes: Int
        public var reviews: [Review]
        /// Days he tapped "Too sleepy" (each widened the window by a step).
        public var sleepyDays: [Date]
        /// He chose to keep going after the app suggested seeing someone.
        public var continuedPastStall: Bool

        public init(startDay: Date, wakeMinutes: Int, windowMinutes: Int, averageSleepMinutes: Int) {
            self.startDay = startDay
            self.wakeMinutes = wakeMinutes
            self.windowMinutes = windowMinutes
            self.initialWindowMinutes = windowMinutes
            self.averageSleepMinutes = averageSleepMinutes
            self.reviews = []
            self.sleepyDays = []
            self.continuedPastStall = false
        }

        /// The week it is in, 1...8.
        public var week: Int { min(SleepWindow.maximumWeeks, reviews.count + 1) }

        /// Earliest bedtime, minutes after midnight: the wake time minus the window.
        public var bedMinutes: Int { ((wakeMinutes - windowMinutes) % 1440 + 1440) % 1440 }

        /// Four judged reviews in a row with no wider window: time to see
        /// someone rather than push on alone. Weeks without enough nights, or
        /// in rest mode, are skipped over, not counted.
        public var isStalled: Bool {
            let judged = reviews.filter { $0.change != .heldFewNights && $0.change != .heldResting }
            guard judged.count >= SleepWindow.stalledReviews else { return false }
            return judged.suffix(SleepWindow.stalledReviews).allSatisfy { $0.change != .widened }
        }

        /// When review `week` is due: noon on the day that week's last night
        /// ended, by when the night is in Apple Health (app's choice).
        public func reviewDue(week: Int, calendar: Calendar = .current) -> Date {
            let day = calendar.date(byAdding: .day, value: week * SleepWindow.reviewDays, to: startDay)
                ?? startDay.addingTimeInterval(Double(week * SleepWindow.reviewDays) * 86_400)
            return calendar.date(byAdding: .hour, value: 12, to: day) ?? day.addingTimeInterval(12 * 3600)
        }

        /// The day of the next review, nil after the last.
        public func nextReviewDay(calendar: Calendar = .current) -> Date? {
            reviews.count < SleepWindow.maximumWeeks ? reviewDue(week: reviews.count + 1, calendar: calendar) : nil
        }
    }

    /// How a course ended.
    public enum Ending: String, Codable, Sendable {
        /// The window widened back to the regular time in bed.
        case reachedRegular
        /// Eight weeks are up.
        case timeLimit
        /// He stopped it.
        case stopped
        /// Something in `Exclusion` turned up while it was running.
        case excluded
    }

    public struct Outcome: Codable, Sendable, Equatable {
        public var ending: Ending
        public var day: Date
        public var weeks: Int
        public var wakeMinutes: Int
        /// Why, when `ending` is `.excluded`.
        public var refusals: [Refusal]
        /// After eight weeks: is it still three or more nights a week? Nil until answered.
        public var stillStruggling: Bool?

        public init(ending: Ending, day: Date, weeks: Int, wakeMinutes: Int, refusals: [Refusal] = [], stillStruggling: Bool? = nil) {
            self.ending = ending
            self.day = day
            self.weeks = weeks
            self.wakeMinutes = wakeMinutes
            self.refusals = refusals
            self.stillStruggling = stillStruggling
        }

        /// The eight-week question is still open.
        public var needsAnswer: Bool { ending == .timeLimit && stillStruggling == nil }
    }

    public static func start(_ proposal: Proposal, wakeMinutes: Int, now: Date = .now, calendar: Calendar = .current) -> Course {
        Course(startDay: calendar.startOfDay(for: now), wakeMinutes: ((wakeMinutes % 1440) + 1440) % 1440,
               windowMinutes: proposal.windowMinutes, averageSleepMinutes: proposal.averageSleepMinutes)
    }

    /// One week's rule (HABIT): 85% or more, 15 minutes longer; 80-84%, no
    /// change; 79% or less, 15 minutes shorter, but never under six hours,
    /// never in a week he said he was too sleepy, and never on fewer than five nights.
    public static func review(week: Int, windowMinutes: Int, nights: [Night], regularMinutes: Int,
                              sleepy: Bool = false, resting: Bool = false) -> Review {
        let percent = efficiencyPercent(nights)
        if resting {
            return Review(week: week, nights: nights.count, efficiencyPercent: percent, change: .heldResting, windowMinutes: windowMinutes)
        }
        guard nights.count >= minimumReviewNights, let percent else {
            return Review(week: week, nights: nights.count, efficiencyPercent: nil, change: .heldFewNights, windowMinutes: windowMinutes)
        }
        if percent >= widenPercent {
            let wider = min(max(regularMinutes, windowMinutes), windowMinutes + stepMinutes)
            return Review(week: week, nights: nights.count, efficiencyPercent: percent, change: wider > windowMinutes ? .widened : .held, windowMinutes: wider)
        }
        if percent >= narrowBelowPercent {
            return Review(week: week, nights: nights.count, efficiencyPercent: percent, change: .held, windowMinutes: windowMinutes)
        }
        if sleepy {
            return Review(week: week, nights: nights.count, efficiencyPercent: percent, change: .heldSleepy, windowMinutes: windowMinutes)
        }
        let narrower = max(floorMinutes, windowMinutes - stepMinutes)
        return Review(week: week, nights: nights.count, efficiencyPercent: percent,
                      change: narrower < windowMinutes ? .narrowed : .heldAtFloor, windowMinutes: narrower)
    }

    /// The nights of week `week`: those that ended on its seven days.
    static func nights(ofWeek week: Int, course: Course, from nights: [Night], calendar: Calendar) -> [Night] {
        let days = (week - 1) * reviewDays
        guard let after = calendar.date(byAdding: .day, value: days, to: course.startDay),
              let through = calendar.date(byAdding: .day, value: days + reviewDays, to: course.startDay) else { return [] }
        return nights.filter { $0.date > after && $0.date <= through }
    }

    /// Runs every weekly review that has come due, oldest first, and ends the
    /// course when the window is back to the regular one or eight weeks are up.
    /// Safe to call on every refresh: a review is made once.
    /// - Parameters:
    ///   - regularMinutes: `regularMinutes(sleepNeedHours:)` now.
    ///   - resting: rest mode is on (ill): due reviews hold the window.
    /// - Returns: the course as it stands, and how it ended if it did.
    public static func advance(_ course: Course, nights: [Night], regularMinutes: Int, resting: Bool = false,
                               now: Date = .now, calendar: Calendar = .current) -> (course: Course, outcome: Outcome?) {
        var course = course
        while course.reviews.count < maximumWeeks {
            let week = course.reviews.count + 1
            guard now >= course.reviewDue(week: week, calendar: calendar) else { break }
            let weekNights = Self.nights(ofWeek: week, course: course, from: nights, calendar: calendar)
            let days = (week - 1) * reviewDays
            let weekStart = calendar.date(byAdding: .day, value: days, to: course.startDay) ?? course.startDay
            let weekEnd = calendar.date(byAdding: .day, value: days + reviewDays, to: course.startDay) ?? course.startDay
            let sleepy = course.sleepyDays.contains { $0 >= weekStart && $0 < weekEnd }
            let review = Self.review(week: week, windowMinutes: course.windowMinutes, nights: weekNights,
                                     regularMinutes: regularMinutes, sleepy: sleepy, resting: resting)
            course.reviews.append(review)
            course.windowMinutes = review.windowMinutes
            if let outcome = ending(course, regularMinutes: regularMinutes, now: now, calendar: calendar) {
                return (course, outcome)
            }
        }
        return (course, ending(course, regularMinutes: regularMinutes, now: now, calendar: calendar))
    }

    static func ending(_ course: Course, regularMinutes: Int, now: Date, calendar: Calendar) -> Outcome? {
        let day = calendar.startOfDay(for: now)
        if course.windowMinutes >= regularMinutes {
            return Outcome(ending: .reachedRegular, day: day, weeks: course.reviews.count, wakeMinutes: course.wakeMinutes)
        }
        if course.reviews.count >= maximumWeeks {
            return Outcome(ending: .timeLimit, day: day, weeks: course.reviews.count, wakeMinutes: course.wakeMinutes)
        }
        return nil
    }

    /// "Too sleepy": 15 minutes longer at once, any day. HABIT: when "patient
    /// is excessively sleepy" the time in bed is revised, "increasing in 15
    /// minute blocks", until it can be lived with.
    public static func tooSleepy(_ course: Course, regularMinutes: Int, now: Date = .now, calendar: Calendar = .current) -> Course {
        var course = course
        course.windowMinutes = min(max(regularMinutes, course.windowMinutes), course.windowMinutes + stepMinutes)
        course.sleepyDays.append(calendar.startOfDay(for: now))
        return course
    }

    /// A reason to stop a running course: the watch flags possible apnoea, or
    /// his sleep turns into a shift pattern. Nil while it's safe to go on.
    public static func stopReasons(apnoeaFlaggedNights: Int, nights: [Night], calendar: Calendar = .current) -> [Refusal] {
        guard case .refuse(let refusals) = decide(Screening(
            stopBangScore: 0, apnoeaFlaggedNights: apnoeaFlaggedNights,
            daytimeSleeps: daytimeSleeps(nights, calendar: calendar))) else { return [] }
        return refusals
    }

    // MARK: - What is saved

    /// Everything the app keeps about the path (a small JSON file).
    public struct State: Codable, Sendable, Equatable {
        public var answers: Answers?
        /// The lines he ticked, kept so a later look shows why.
        public var refusals: [Refusal]?
        public var refusedDay: Date?
        public var course: Course?
        /// The last course's ending, until he has read it.
        public var outcome: Outcome?
        /// The day the last course ended.
        public var endedDay: Date?

        public init(answers: Answers? = nil, refusals: [Refusal]? = nil, refusedDay: Date? = nil,
                    course: Course? = nil, outcome: Outcome? = nil, endedDay: Date? = nil) {
            self.answers = answers
            self.refusals = refusals
            self.refusedDay = refusedDay
            self.course = course
            self.outcome = outcome
            self.endedDay = endedDay
        }

        /// Whether the app may raise the question by itself: never while a
        /// course runs or an ending is unread, and not within 90 days of an
        /// answer, a refusal or a course.
        public func mayAsk(now: Date = .now) -> Bool {
            guard course == nil, outcome == nil else { return false }
            let last = [answers?.day, refusedDay, endedDay].compactMap { $0 }.max()
            guard let last else { return true }
            return now.timeIntervalSince(last) >= Double(SleepWindow.askAgainDays) * 86_400
        }
    }

    // MARK: - Words

    public static let questionTitle = "Trouble sleeping?"
    public static let questionIntro = "Two questions. Depending on your answers the app sets up a sleep window for a few weeks, or drops the subject."
    public static let screeningTitle = "Before you start"
    public static let screeningIntro = "A shorter sleep window makes most people sleepier for the first few weeks, so it isn't for everyone. Tick anything that applies."

    /// Shown with the plan before it starts and on the card while it runs
    /// (Kyle et al., Sleep 2014: sleepier in weeks 1-3, slower reactions, back
    /// to normal by three months; patients "advised not to drive or operate
    /// heavy machinery if they feel excessively sleepy").
    public static let sleepinessWarning = "Expect to be sleepier and slower to react for the first two or three weeks. Don't drive or use machinery when you feel drowsy. If it's too much, tap Too sleepy and the window gets longer."
    /// What the efficiency number is.
    public static let estimateNote = "The app judges each week by how much of your time in bed your tracker has you asleep. That number is an estimate and tends to read high when you lie awake, so go by how you feel as well."
    public static let notCareNote = "This is a routine to try, not medical care, and the app can't tell what is behind poor sleep. Stop any time."
    /// Said wherever sleep debt would be.
    public static let debtPausedNote = "Sleep debt is paused while your sleep window is on: a shorter time in bed for a few weeks is the plan, and catching up would undo it."
    public static let restingNote = "Paused while rest mode is on. When you're ill, sleep as much as you need."
    public static let stalledText = "Four weeks without the window getting longer. That's the point to see a GP or a sleep clinic rather than push on alone: face-to-face help does better than an app (Furukawa 2024)."

    /// The rules, in order. No tips: only the four things the method is.
    public static func rules(_ course: Course) -> [String] {
        rules(wakeMinutes: course.wakeMinutes, bedMinutes: course.bedMinutes)
    }

    public static func rules(wakeMinutes: Int, bedMinutes: Int) -> [String] {
        let wake = clock(wakeMinutes)
        return [
            "Up at \(wake) every day, weekends too, however the night went.",
            "Bed no earlier than \(clock(bedMinutes)), and only when you're sleepy.",
            "Awake for what feels like \(awakeMinutes) minutes? Get up, and go back when you're sleepy. Don't watch the clock.",
        ]
    }

    /// "Each week …": how the window moves and when it ends.
    public static var howItChanges: String {
        "Each week: asleep for \(widenPercent)% or more of your time in bed and the window gets \(stepMinutes) minutes longer; under \(narrowBelowPercent)% and it gets \(stepMinutes) minutes shorter, never under \(duration(floorMinutes)). It ends when the window is back to your regular one, or after \(maximumWeeks) weeks."
    }

    /// "6 h 45 min in bed: 23:45 to 6:30"
    public static func windowText(windowMinutes: Int, wakeMinutes: Int) -> String {
        let bed = ((wakeMinutes - windowMinutes) % 1440 + 1440) % 1440
        return "\(duration(windowMinutes)) in bed: \(clock(bed)) to \(clock(wakeMinutes))"
    }

    /// Where the first window came from.
    public static func basisText(_ proposal: Proposal) -> String {
        var text = "From \(duration(proposal.averageSleepMinutes)) asleep a night over your last \(proposal.nightsUsed) nights, plus \(extraMinutes) minutes"
        if proposal.windowMinutes == floorMinutes, proposal.averageSleepMinutes + extraMinutes < floorMinutes {
            text += ", held at the \(duration(floorMinutes)) minimum"
        }
        return text + ". Your tracker's figure is an estimate and tends to read high when you lie awake, which only makes the window longer."
    }

    /// "Sleep window · week 2 of 8"
    public static func heading(_ course: Course) -> String {
        "Sleep window · week \(course.week) of \(maximumWeeks)"
    }

    /// What an ending says, and what to do next.
    public static func outcomeText(_ outcome: Outcome) -> String {
        let wake = clock(outcome.wakeMinutes)
        switch outcome.ending {
        case .reachedRegular:
            return "Your sleep window is back to your regular time in bed, so it's finished. Keep getting up at \(wake)."
        case .timeLimit:
            switch outcome.stillStruggling {
            case nil:
                return "\(maximumWeeks) weeks are up, which is as long as this runs. Is it still hard to fall or stay asleep \(nightsPerWeek) or more nights a week?"
            case true?:
                return "Then it's time to see a GP or a sleep clinic. They can look for what's behind it and go further than an app can; face-to-face help does better (Furukawa 2024). Keep getting up at \(wake) in the meantime."
            case false?:
                return "Good. The sleep window is off and the regular bed-by window is back. Keep getting up at \(wake)."
            }
        case .stopped:
            return "The sleep window is off and the regular bed-by window is back."
        case .excluded:
            return "The sleep window has been turned off. " + outcome.refusals.map(\.reason).joined(separator: " ") + " " + refusalAdvice
        }
    }

    /// The studies behind it, for the evidence disclosure.
    public static let evidence = [
        "A shorter, fixed sleep window beat sleep-hygiene advice in 642 adults in primary care (Kyle et al., Lancet 2023). The weekly rule here is that trial's.",
        "Across 241 trials, a restricted sleep window and getting out of bed when awake were among the parts that helped; sleep-hygiene advice added nothing and relaxation may get in the way (Furukawa et al., JAMA Psychiatry 2024). That's why there are no tips here.",
        "It makes people sleepier and slower to react for the first weeks (Kyle et al., Sleep 2014).",
        "The six-hour minimum is the app's choice, the longest of the minimums in use (4.5, 5 or 6 hours: European Insomnia Guideline 2023).",
        "Wrist trackers overestimate sleep in people who lie awake (European Insomnia Guideline 2023), so your answers start this, not the tracker.",
    ]

    /// "6 h 45 min"
    public static func duration(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// A time of day from minutes after midnight, in the device's format ("6:30 AM", "06:30").
    public static func clock(_ minutes: Int) -> String {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let date = calendar.date(byAdding: .minute, value: ((minutes % 1440) + 1440) % 1440, to: midnight) ?? midnight
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - The bed-by window in sleep-window mode

extension BedtimeWindow {
    /// Tonight's window while the insomnia path is on (`SleepWindow`): worked
    /// back from the fixed wake time by the sleep window, with no debt to
    /// repay and no change for a planned session, because the fixed wake time
    /// wins. `start` is the earliest bedtime; `end` is 30 minutes later only
    /// so callers that show a span still can ("bed only when sleepy" may make
    /// the real bedtime later still).
    public static func sleepWindow(minutes: Int, wakeMinutes: Int, sleepNeedHours: Double, now: Date = .now,
                                   calendar: Calendar = .current) -> Result {
        let today = calendar.startOfDay(for: now)
        let earliest = now.addingTimeInterval(minimumHoursAhead * 3600)
        var wake = today.addingTimeInterval(TimeInterval(wakeMinutes * 60))
        while wake < earliest {
            wake = calendar.date(byAdding: .day, value: 1, to: wake) ?? wake.addingTimeInterval(86_400)
        }
        let start = wake.addingTimeInterval(-TimeInterval(minutes * 60))
        return Result(start: start, end: start.addingTimeInterval(TimeInterval(windowMinutes * 60)), wake: wake,
                      needHours: min(11, max(6, sleepNeedHours)), timeInBedHours: Double(minutes) / 60,
                      repaymentMinutes: 0, wakeForSession: false, regularityNote: nil, isSleepWindow: true)
    }
}
