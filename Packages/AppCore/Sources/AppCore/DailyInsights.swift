import Foundation

/// A short, ranked list of plain-language observations about the last week
/// against the weeks before it, plus one or two longer-running suggestions
/// ("for you"). Deterministic rules, no model: every line can be traced to
/// the numbers it quotes.
///
/// What a line is: what changed, compared with what, and at most one
/// suggested action. What it is not: a diagnosis, or advice for today's
/// training (Today's coaching line, Up next and the daily messages already
/// cover today's recovery, strain range, bedtime and plan, so nothing here
/// repeats them; this feed is about week-scale change).
///
/// Evidence and choices (docs/research/longevity-insights.md):
/// - **Compare with the person's own baseline.** Day-to-day wearable values
///   are noisy, and a 7-day average against the individual's own normal
///   range is the established way to read them (Plews et al., Sports Med
///   2013, for HRV). The trend rules compare the last 7 days with the 28
///   days before.
/// - **The trigger sizes are the app's choices, statistical not clinical.**
///   A weekly mean one day-to-day standard deviation away from the 4-week
///   mean is about 2.6 standard errors, unlikely to be noise; nothing says
///   that size matters for health, and the copy doesn't claim it does.
/// - **Fixed lines are published ones** (150 active minutes, 25 g of fibre,
///   the headphone limit, the sleep-regularity lines), cited at `Longevity`.
/// - **Few, and not daily.** Repeated prompts lose their effect within weeks
///   (Klasnja et al., Ann Behav Med 2019), so a line shows for at most
///   `maxRunDays` days running and then rests; the cap of 4 and the rest
///   lengths are app choices, untested.
/// - **Hysteresis.** A rule turns on at one size and off at about half of
///   it, so a value sitting on the line doesn't flip the insight on and off.
public enum DailyInsights {
    // MARK: Types

    public enum Category: String, CaseIterable, Sendable, Codable {
        case heart, sleep, recovery, fitness, vitals, nutrition, habits

        public var title: String {
            switch self {
            case .heart: "Heart"
            case .sleep: "Sleep"
            case .recovery: "Recovery"
            case .fitness: "Fitness"
            case .vitals: "Vitals"
            case .nutrition: "Nutrition"
            case .habits: "Habits"
            }
        }
    }

    public enum Tone: String, Sendable, Codable {
        case good, neutral, watch
    }

    public struct Insight: Sendable, Equatable, Identifiable, Codable {
        /// The rule that made it ("rhrTrend").
        public var id: String
        public var category: Category
        public var tone: Tone
        /// What changed.
        public var title: String
        /// Compared with what.
        public var comparison: String
        /// At most one suggested action.
        public var action: String?
    }

    /// A longer-running suggestion, from the Longevity page's off-target measures.
    public struct Suggestion: Sendable, Equatable, Identifiable, Codable {
        public var id: String
        public var title: String
        public var detail: String
        public var measure: Longevity.MeasureID?
    }

    public struct Feed: Sendable, Equatable {
        public var today: [Insight]
        public var forYou: [Suggestion]
        /// Why `today` is empty, when it is.
        public var emptyReason: String?

        public init(today: [Insight] = [], forYou: [Suggestion] = [], emptyReason: String? = nil) {
            self.today = today
            self.forYou = forYou
            self.emptyReason = emptyReason
        }

        /// The top lines for the coach's facts, or nil when there are none.
        public func coachSummary(limit: Int = 3) -> String? {
            guard !today.isEmpty else { return nil }
            return "This week's changes (from the Insights feed): "
                + today.prefix(limit).map { "\($0.title) (\($0.comparison))" }.joined(separator: " ")
        }
    }

    /// A personal pattern from the check-ins (`CheckInInsights`), passed through.
    public struct Pattern: Sendable, Equatable {
        public var sentence: String
        public var daysWith: Int
        public var daysWithout: Int

        public init(sentence: String, daysWith: Int, daysWithout: Int) {
            self.sentence = sentence
            self.daysWith = daysWith
            self.daysWithout = daysWithout
        }
    }

    public struct Inputs: Sendable {
        /// Any time on the day the feed is for.
        public var day: Date
        public var calendar: Calendar
        /// Daily or nightly values, any order; days without a value are just missing.
        public var restingHeartRate: [DayValue] = []
        public var hrv: [DayValue] = []
        public var sleepHours: [DayValue] = []
        public var sleepRegularity: Int?
        /// Full days only (leave today out until it is over).
        public var steps: [DayValue] = []
        public var vo2Max: [DayValue] = []
        /// Moderate-equivalent minutes per day (`IntensityMinutes.Result.total`).
        public var activeMinutes: [DayValue] = []
        /// Start of each logged strength session.
        public var strengthSessions: [Date] = []
        public var respiratoryRate: [DayValue] = []
        /// Percent, 0-100.
        public var bloodOxygen: [DayValue] = []
        public var proteinGrams: [DayValue] = []
        public var proteinTargetGrams: Double?
        /// 7-day average from the food log.
        public var fiberGrams: Double?
        /// Standard drinks per logged evening (zero counts as logged).
        public var drinks: [DayValue] = []
        /// State of Mind valence per entry or day, -1...1.
        public var mood: [DayValue] = []
        public var headphoneBudgetPercent: Double?
        public var pattern: Pattern?
        public var longevity: Longevity.Assessment?

        public init(day: Date, calendar: Calendar = .current) {
            self.day = day
            self.calendar = calendar
        }
    }

    /// What the feed remembers between days, so lines neither flicker nor
    /// repeat. Codable: the app keeps it in UserDefaults (not SwiftData).
    public struct State: Codable, Sendable, Equatable {
        public struct Entry: Codable, Sendable, Equatable {
            /// The direction or kind that was active ("up", "down", "low").
            public var variant: String
            /// The last day the rule's condition held.
            public var lastActive: Date
            /// The last day it was shown, and how many days running.
            public var lastShown: Date?
            public var runDays: Int
        }

        public var entries: [String: Entry]

        public init(entries: [String: Entry] = [:]) {
            self.entries = entries
        }
    }

    public struct Result: Sendable, Equatable {
        public var feed: Feed
        public var state: State
    }

    // MARK: Limits (app choices; see the type's comment)

    /// Most lines shown at once.
    public static let maxShown = 4
    public static let maxPerCategory = 2
    /// Most amber lines at once: status colour only where it earns it
    /// (docs/research/cleanup-2026-11.md).
    public static let maxWatch = 2
    /// Days a line may show in a row before it rests.
    public static let maxRunDays = 3
    /// Days a line rests after its last showing.
    public static let restDays = 7
    /// A line that reports a standing good state ("protein is on target")
    /// and not a change shows for two days and then rests three weeks: worth
    /// hearing now and then, not weekly.
    public static let standingRunDays = 2
    public static let standingRestDays = 21
    public static let maxForYou = 2

    /// A weekly mean this many day-to-day standard deviations from the
    /// 4-week mean turns a trend rule on; it turns off under `shiftExitSD`.
    public static let shiftEnterSD = 1.0
    public static let shiftExitSD = 0.5
    /// Days of data needed: 4 of the last 7 and 14 of the 28 before.
    public static let minimumRecentDays = 4
    public static let minimumBaselineDays = 14

    // MARK: Evaluate

    /// The feed for `inputs.day`, and the state to pass in next time.
    /// Calling it again the same day with the same inputs gives the same feed.
    public static func evaluate(_ inputs: Inputs, state: State = State()) -> Result {
        let today = inputs.calendar.startOfDay(for: inputs.day)
        let context = Context(inputs: inputs, state: state, today: today)
        var candidates = [
            restingHeartRate(context), hrv(context), sleepLength(context), sleepRegularity(context),
            steps(context), vo2Max(context), activeMinutes(context), strength(context),
            vitals(context), protein(context), fiber(context), alcohol(context),
            mood(context), hearing(context), pattern(context)
        ].compactMap { $0 }
        candidates = withoutMixedRecovery(candidates)

        var next = state
        for candidate in candidates {
            var entry = next.entries[candidate.insight.id]
            if entry == nil || entry?.variant != candidate.variant {
                entry = State.Entry(variant: candidate.variant, lastActive: today, lastShown: nil, runDays: 0)
            }
            entry?.lastActive = today
            next.entries[candidate.insight.id] = entry
        }

        let shown = select(candidates, state: next, context: context)
        for insight in shown {
            guard var entry = next.entries[insight.id] else { continue }
            if let last = entry.lastShown, context.daysBetween(last, today) == 0 {
                // Already counted today.
            } else if let last = entry.lastShown, context.daysBetween(last, today) == 1 {
                entry.runDays += 1
            } else {
                entry.runDays = 1
            }
            entry.lastShown = today
            next.entries[insight.id] = entry
        }
        // Forget rules that have been quiet for two months.
        next.entries = next.entries.filter { context.daysBetween($0.value.lastActive, today) <= 60 }

        var feed = Feed(today: shown)
        if shown.isEmpty {
            if let steady = steadyWeek(context, active: Set(candidates.map(\.subject))) {
                feed.today = [steady]
            } else {
                feed.emptyReason = candidates.isEmpty
                    ? "Needs about three weeks of watch data to compare this week with your usual."
                    : "Nothing new today. This week's earlier observations still hold."
            }
        }
        feed.forYou = forYou(inputs.longevity, shown: feed.today, today: today)
        return Result(feed: feed, state: next)
    }

    // MARK: Selection

    struct Candidate {
        var insight: Insight
        var variant: String
        /// What it is about; one line per subject.
        var subject: String
        /// 0...1 or so, for ranking.
        var strength: Double
        var maxRun = DailyInsights.maxRunDays
        var rest = DailyInsights.restDays
    }

    struct Context {
        var inputs: Inputs
        var state: State
        var today: Date

        /// Whole days from `a` to `b` (both any time of day).
        func daysBetween(_ a: Date, _ b: Date) -> Int {
            let calendar = inputs.calendar
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
        }

        /// True when the rule held this variant yesterday or today: it then
        /// only needs its exit size to stay on.
        func wasActive(_ id: String, _ variant: String) -> Bool {
            guard let entry = state.entries[id], entry.variant == variant else { return false }
            return (0...1).contains(daysBetween(entry.lastActive, today))
        }

        /// The threshold to use: the exit size while on, the enter size otherwise.
        func needed(_ id: String, _ variant: String, enter: Double, exit: Double) -> Double {
            wasActive(id, variant) ? exit : enter
        }
    }

    /// May this candidate show today, given when it last showed?
    static func isEligible(_ candidate: Candidate, entry: State.Entry?, context: Context) -> Bool {
        guard let entry, entry.variant == candidate.variant, let last = entry.lastShown else { return true }
        let gap = context.daysBetween(last, context.today)
        if gap <= 0 { return true }
        if gap == 1 { return entry.runDays < candidate.maxRun }
        return gap >= candidate.rest
    }

    static func select(_ candidates: [Candidate], state: State, context: Context) -> [Insight] {
        func shownToday(_ candidate: Candidate) -> Bool {
            guard let entry = state.entries[candidate.insight.id], entry.variant == candidate.variant,
                  let last = entry.lastShown else { return false }
            return context.daysBetween(last, context.today) == 0
        }
        func score(_ candidate: Candidate) -> Double {
            // Lines already shown today stay (the feed doesn't reshuffle on a refresh);
            // then things to watch, then by size.
            (shownToday(candidate) ? 10 : 0) + (candidate.insight.tone == .watch ? 0.3 : 0) + min(1, candidate.strength)
        }
        let ranked = candidates
            .filter { isEligible($0, entry: state.entries[$0.insight.id], context: context) }
            .sorted { a, b in
                let (x, y) = (score(a), score(b))
                return x != y ? x > y : a.insight.id < b.insight.id
            }
        var picked: [Candidate] = []
        func canAdd(_ candidate: Candidate, perCategory: Int) -> Bool {
            guard picked.count < maxShown, !picked.contains(where: { $0.insight.id == candidate.insight.id }) else { return false }
            if picked.filter({ $0.insight.category == candidate.insight.category }).count >= perCategory { return false }
            if candidate.insight.tone == .watch, picked.filter({ $0.insight.tone == .watch }).count >= maxWatch { return false }
            return true
        }
        // One per category first, so the list is varied; then a second where there's room.
        for limit in 1...maxPerCategory {
            for candidate in ranked where canAdd(candidate, perCategory: limit) {
                picked.append(candidate)
            }
        }
        return picked.map(\.insight)
    }

    /// Resting heart rate and HRV pointing opposite ways (one good, one to
    /// watch) read as a contradiction side by side: keep the larger one.
    static func withoutMixedRecovery(_ candidates: [Candidate]) -> [Candidate] {
        guard let rhr = candidates.first(where: { $0.subject == "rhr" }),
              let hrv = candidates.first(where: { $0.subject == "hrv" }),
              rhr.insight.tone != hrv.insight.tone else { return candidates }
        let drop = rhr.strength >= hrv.strength ? "hrv" : "rhr"
        return candidates.filter { $0.subject != drop }
    }

    // MARK: Windows

    struct Shift {
        var recent: Double
        var baseline: Double
        /// Day-to-day standard deviation of the baseline days.
        var sd: Double
        var recentDays: Int
        var baselineDays: Int
        var delta: Double { recent - baseline }
        var percent: Double { baseline != 0 ? delta / baseline * 100 : 0 }
        /// The change in day-to-day standard deviations.
        var z: Double { sd > 0 ? delta / sd : 0 }
    }

    /// Values in the window `from...to` days before today (0 = today).
    static func values(_ series: [DayValue], _ context: Context, daysAgo: ClosedRange<Int>) -> [Double] {
        series.filter { daysAgo.contains(context.daysBetween($0.date, context.today)) }.map(\.value)
    }

    /// The last 7 days against the 28 before them; nil without enough of either.
    static func shift(_ series: [DayValue], _ context: Context, includesToday: Bool = true,
                      minimumRecent: Int = minimumRecentDays, minimumBaseline: Int = minimumBaselineDays) -> Shift? {
        let start = includesToday ? 0 : 1
        let recent = values(series, context, daysAgo: start...(start + 6))
        let baseline = values(series, context, daysAgo: (start + 7)...(start + 34))
        guard recent.count >= minimumRecent, baseline.count >= minimumBaseline else { return nil }
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        let variance = baseline.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, baseline.count - 1))
        return Shift(recent: recent.reduce(0, +) / Double(recent.count), baseline: mean, sd: variance.squareRoot(),
                     recentDays: recent.count, baselineDays: baseline.count)
    }

    /// A trend rule's direction, with hysteresis: on at `shiftEnterSD` and at
    /// least `floor` in the metric's own unit, off under half of both.
    static func direction(_ shift: Shift, id: String, floor: Double, magnitude: Double? = nil, _ context: Context) -> String? {
        let size = abs(magnitude ?? shift.delta)
        let variant = shift.delta >= 0 ? "up" : "down"
        let needSD = context.needed(id, variant, enter: shiftEnterSD, exit: shiftExitSD)
        let needFloor = context.needed(id, variant, enter: floor, exit: floor / 2)
        return abs(shift.z) >= needSD && size >= needFloor ? variant : nil
    }

    // MARK: - Rules

    /// Smallest weekly change in resting heart rate worth a line, bpm (app's choice).
    public static let restingHeartRateFloor = 2.0

    static func restingHeartRate(_ c: Context) -> Candidate? {
        guard let shift = Self.shift(c.inputs.restingHeartRate, c),
              let variant = direction(shift, id: "rhrTrend", floor: restingHeartRateFloor, c) else { return nil }
        let up = variant == "up"
        let size = max(1, Int(abs(shift.delta).rounded()))
        return Candidate(
            insight: Insight(
                id: "rhrTrend", category: .heart, tone: up ? .watch : .good,
                title: "Resting heart rate is \(up ? "up" : "down") \(size) bpm",
                comparison: "\(whole(shift.recent)) bpm this week against \(whole(shift.baseline)) over the 4 weeks before.",
                action: up ? "Short sleep, alcohol, heat and a cold coming on are the usual causes. See if it settles in a few days." : nil),
            variant: variant, subject: "rhr", strength: abs(shift.z) / 2)
    }

    /// Smallest weekly change in HRV worth a line, percent (app's choice).
    public static let hrvFloorPercent = 5.0

    static func hrv(_ c: Context) -> Candidate? {
        guard let shift = Self.shift(c.inputs.hrv, c),
              let variant = direction(shift, id: "hrvTrend", floor: hrvFloorPercent, magnitude: shift.percent, c) else { return nil }
        let up = variant == "up"
        return Candidate(
            insight: Insight(
                id: "hrvTrend", category: .recovery, tone: up ? .good : .watch,
                title: "HRV is \(up ? "up" : "down") \(max(1, Int(abs(shift.percent).rounded())))%",
                comparison: "\(whole(shift.recent)) ms this week against \(whole(shift.baseline)) ms over the 4 weeks before.",
                // Today's plan already eases training when HRV is low; no second instruction here.
                action: nil),
            variant: variant, subject: "hrv", strength: abs(shift.z) / 2)
    }

    /// Weekly change in nightly sleep that turns the line on and off, hours
    /// (app's choice: half an hour a night is 3.5 hours over the week).
    public static let sleepEnterHours = 0.5
    public static let sleepExitHours = 0.25

    static func sleepLength(_ c: Context) -> Candidate? {
        guard let shift = Self.shift(c.inputs.sleepHours, c) else { return nil }
        let variant = shift.delta >= 0 ? "up" : "down"
        guard abs(shift.delta) >= c.needed("sleepWeek", variant, enter: sleepEnterHours, exit: sleepExitHours) else { return nil }
        let up = variant == "up"
        let minutes = max(5, Int((abs(shift.delta) * 60 / 5).rounded()) * 5)
        return Candidate(
            insight: Insight(
                id: "sleepWeek", category: .sleep, tone: up ? .good : .watch,
                title: "You're sleeping \(minutes) min \(up ? "longer" : "less")",
                comparison: "\(Longevity.hoursText(shift.recent)) a night this week against \(Longevity.hoursText(shift.baseline)) over the 4 weeks before.",
                action: up ? nil : "Check what changed: later evenings, late caffeine or earlier alarms."),
            variant: variant, subject: "sleepLength", strength: abs(shift.delta))
    }

    /// Sleep Regularity Index lines: low under `Longevity.sleepRegularityLow`
    /// (74, off again from 78); very regular from 87 (the study's top
    /// quarter started at 86.3; off again under 83). Windred et al., Sleep 2024.
    public static let sleepRegularityLowExit = 78
    public static let sleepRegularityHigh = 87
    public static let sleepRegularityHighExit = 83

    static func sleepRegularity(_ c: Context) -> Candidate? {
        guard let index = c.inputs.sleepRegularity else { return nil }
        let id = "sleepRegularity"
        if Double(index) < c.needed(id, "low", enter: Double(Longevity.sleepRegularityLow), exit: Double(sleepRegularityLowExit)) {
            return Candidate(
                insight: Insight(
                    id: id, category: .sleep, tone: .watch,
                    title: "Your sleep times are irregular",
                    comparison: "Regularity index \(index). 81 is typical, and under about 74 was the least regular quarter in a UK study of 61,000 adults.",
                    action: "Keep one wake time for 7 days, weekends too."),
                variant: "low", subject: "sleepRegularity", strength: Double(Longevity.sleepRegularityTarget - index) / 20)
        }
        if Double(index) >= c.needed(id, "high", enter: Double(sleepRegularityHigh), exit: Double(sleepRegularityHighExit)) {
            return Candidate(
                insight: Insight(
                    id: id, category: .sleep, tone: .good,
                    title: "Your sleep times are very regular",
                    comparison: "Regularity index \(index). 81 is typical in a UK study of 61,000 adults.",
                    action: nil),
                variant: "high", subject: "sleepRegularity", strength: 0.3, maxRun: standingRunDays, rest: standingRestDays)
        }
        return nil
    }

    /// Weekly change in steps that turns the line on: 20% and 1,000 a day
    /// (off under 10% and 500). App's choice.
    public static let stepsEnterPercent = 20.0
    public static let stepsFloor = 1_000.0

    static func steps(_ c: Context) -> Candidate? {
        guard let shift = Self.shift(c.inputs.steps, c, includesToday: false), shift.baseline > 0 else { return nil }
        let variant = shift.delta >= 0 ? "up" : "down"
        let percent = c.needed("stepsWeek", variant, enter: stepsEnterPercent, exit: stepsEnterPercent / 2)
        let floor = c.needed("stepsWeek", variant, enter: stepsFloor, exit: stepsFloor / 2)
        guard abs(shift.percent) >= percent, abs(shift.delta) >= floor else { return nil }
        let up = variant == "up"
        return Candidate(
            insight: Insight(
                id: "stepsWeek", category: .fitness, tone: up ? .good : .watch,
                title: "Steps are \(up ? "up" : "down") \(Int(abs(shift.percent).rounded()))%",
                comparison: "\(Longevity.grouped(shift.recent)) a day this week against \(Longevity.grouped(shift.baseline)) over the 4 weeks before.",
                action: up ? nil : "A daily 15-minute walk is the easiest way back."),
            variant: variant, subject: "steps", strength: abs(shift.percent) / 50)
    }

    /// VO₂ max change over about two months that turns the line on,
    /// ml/kg/min (off under half). Watch estimates move by about 1 on their
    /// own (`CardioFitness.meaningfulChange`), so this sits above that. App's choice.
    public static let vo2EnterChange = 1.5

    static func vo2Max(_ c: Context) -> Candidate? {
        let recent = values(c.inputs.vo2Max, c, daysAgo: 0...20)
        let earlier = values(c.inputs.vo2Max, c, daysAgo: 49...90)
        guard recent.count >= 2, earlier.count >= 2 else { return nil }
        let now = recent.reduce(0, +) / Double(recent.count)
        let before = earlier.reduce(0, +) / Double(earlier.count)
        let delta = now - before
        let variant = delta >= 0 ? "up" : "down"
        guard abs(delta) >= c.needed("vo2Trend", variant, enter: vo2EnterChange, exit: vo2EnterChange / 2) else { return nil }
        let up = variant == "up"
        return Candidate(
            insight: Insight(
                id: "vo2Trend", category: .fitness, tone: up ? .good : .watch,
                title: "VO₂ max is \(up ? "up" : "down") \(Longevity.one(abs(delta)))",
                comparison: "\(Longevity.one(now)) now against \(Longevity.one(before)) about two months ago. It's a watch estimate, so trust the direction more than the decimal.",
                action: up ? nil : "One interval session a week is the lever that moves it most."),
            variant: variant, subject: "vo2", strength: abs(delta) / 4, rest: 14)
    }

    /// Active minutes: "reached" when the week gets to WHO's 150 after a
    /// week under it (off under 120), so it marks the change and isn't
    /// repeated to someone who is always there; "low" under 75 (off from
    /// 100). The off lines are app choices.
    static func activeMinutes(_ c: Context) -> Candidate? {
        let week = values(c.inputs.activeMinutes, c, daysAgo: 0...6)
        let before = values(c.inputs.activeMinutes, c, daysAgo: 7...13)
        // A full week of days on file, so three days of data isn't read as a low week.
        guard week.count >= 5, !before.isEmpty else { return nil }
        let total = week.reduce(0, +)
        let goal = Double(IntensityMinutes.weeklyGoal)
        let id = "activeMinutes"
        let weekBefore = before.reduce(0, +)
        if total >= c.needed(id, "reached", enter: goal, exit: goal * 0.8), c.wasActive(id, "reached") || weekBefore < goal {
            return Candidate(
                insight: Insight(
                    id: id, category: .fitness, tone: .good,
                    title: "\(IntensityMinutes.weeklyGoal) active minutes reached",
                    comparison: "\(whole(total)) in the last 7 days, \(whole(weekBefore)) the week before. WHO's range is 150-300 a week.",
                    action: nil),
                variant: "reached", subject: "activeMinutes", strength: 0.3)
        }
        if total < c.needed(id, "low", enter: goal / 2, exit: goal * 2 / 3) {
            return Candidate(
                insight: Insight(
                    id: id, category: .fitness, tone: .watch,
                    title: "Active minutes are low this week",
                    comparison: "\(whole(total)) in the last 7 days against WHO's 150.",
                    action: "Brisk walking counts: 20 minutes a day reaches 150."),
                variant: "low", subject: "activeMinutes", strength: 1 - total / goal)
        }
        return nil
    }

    /// Days without a strength session, after a month with at least 3, that
    /// turn the "gap" line on (app's choice).
    public static let strengthGapDays = 10

    static func strength(_ c: Context) -> Candidate? {
        let sessions = c.inputs.strengthSessions
        guard !sessions.isEmpty else { return nil }
        let id = "strengthWeeks"
        // 7-day blocks ending today, newest first.
        let weeks = (0..<4).map { week in
            Set(sessions.map { c.daysBetween($0, c.today) }.filter { ((week * 7)...(week * 7 + 6)).contains($0) }).count
        }
        let target = StrengthDays.weeklyTarget
        let held = c.wasActive(id, "held")
            ? weeks.filter { $0 >= target }.count >= 3 && weeks[0] >= 1
            : weeks.allSatisfy { $0 >= target }
        if held {
            return Candidate(
                insight: Insight(
                    id: id, category: .fitness, tone: .good,
                    title: "4 weeks with \(target) or more strength days",
                    comparison: "\(weeks.reversed().map(String.init).joined(separator: ", ")) days in the last four weeks. The health guideline is \(target) a week.",
                    action: nil),
                variant: "held", subject: "strength", strength: 0.25, maxRun: standingRunDays, rest: standingRestDays)
        }
        let sinceLast = sessions.map { c.daysBetween($0, c.today) }.filter { $0 >= 0 }.min() ?? 0
        let monthBefore = sessions.map { c.daysBetween($0, c.today) }.filter { (sinceLast...(sinceLast + 27)).contains($0) }.count
        let needed = c.wasActive(id, "gap") ? 8 : strengthGapDays
        if sinceLast >= needed, monthBefore >= 3 {
            return Candidate(
                insight: Insight(
                    id: id, category: .fitness, tone: .watch,
                    title: "No strength session in \(sinceLast) days",
                    comparison: "You logged \(monthBefore) in the four weeks before that.",
                    action: "One short full-body session gets the week going again."),
                variant: "gap", subject: "strength", strength: min(1, Double(sinceLast) / 21))
        }
        return nil
    }

    /// Overnight breathing rate: a line when the week runs `respirationFloor`
    /// breaths a minute and one standard deviation above the 4 weeks before
    /// (app's choice; the illness watch on Today handles the day-to-day
    /// signs). Otherwise, with breathing rate and blood oxygen both close to
    /// usual, one "in your usual range" line.
    public static let respirationFloor = 0.8

    static func vitals(_ c: Context) -> Candidate? {
        guard let breathing = shift(c.inputs.respiratoryRate, c) else { return nil }
        let id = "vitals"
        if breathing.delta > 0, direction(breathing, id: id, floor: respirationFloor, c) == "up" {
            return Candidate(
                insight: Insight(
                    id: id, category: .vitals, tone: .watch,
                    title: "Breathing rate is up \(Longevity.one(breathing.delta)) a minute",
                    comparison: "\(Longevity.one(breathing.recent)) a minute asleep this week against \(Longevity.one(breathing.baseline)) over the 4 weeks before.",
                    action: nil),
                variant: "up", subject: "vitals", strength: abs(breathing.z) / 2)
        }
        guard abs(breathing.z) < shiftExitSD || abs(breathing.delta) < respirationFloor / 2 else { return nil }
        var parts = ["Breathing rate \(Longevity.one(breathing.recent)) a minute"]
        if let oxygen = shift(c.inputs.bloodOxygen, c) {
            guard abs(oxygen.delta) < 1 else { return nil }
            parts.append("blood oxygen \(whole(oxygen.recent))%")
        }
        return Candidate(
            insight: Insight(
                id: id, category: .vitals, tone: .neutral,
                title: "Overnight vitals are in your usual range",
                comparison: parts.joined(separator: " and ") + ", close to your last 4 weeks.",
                action: nil),
            variant: "usual", subject: "vitals", strength: 0.1, maxRun: 1, rest: 10)
    }

    /// Protein against the user's target: "on target" from 100% of it (off
    /// under 90%), "under" below 80% (off from 88%). App's choices; the
    /// target itself follows the goal (Morton et al., Br J Sports Med 2018).
    static func protein(_ c: Context) -> Candidate? {
        guard let target = c.inputs.proteinTargetGrams, target > 0 else { return nil }
        // Yesterday back: today's log is still filling up.
        let week = values(c.inputs.proteinGrams, c, daysAgo: 1...7).filter { $0 > 0 }
        guard week.count >= minimumRecentDays else { return nil }
        let average = week.reduce(0, +) / Double(week.count)
        let share = average / target
        let id = "proteinWeek"
        let comparison = "\(whole(average)) g a day over \(week.count) logged days. Your target is \(whole(target)) g."
        if share >= c.needed(id, "met", enter: 1.0, exit: 0.9) {
            return Candidate(
                insight: Insight(id: id, category: .nutrition, tone: .good, title: "Protein is on target", comparison: comparison, action: nil),
                variant: "met", subject: "protein", strength: 0.2, maxRun: standingRunDays, rest: standingRestDays)
        }
        if share < c.needed(id, "under", enter: 0.8, exit: 0.88) {
            return Candidate(
                insight: Insight(
                    id: id, category: .nutrition, tone: .watch,
                    title: "Protein is \(whole(target - average)) g under target",
                    comparison: comparison,
                    action: "One extra portion of meat, fish, tofu or dairy a day closes most of it."),
                variant: "under", subject: "protein", strength: 1 - share)
        }
        return nil
    }

    /// Fibre: low under 20 g (off from 22), on target from 25 g (off under
    /// 23). 25-29 g a day is the range from Reynolds et al., Lancet 2019;
    /// the off lines are app choices.
    static func fiber(_ c: Context) -> Candidate? {
        guard let grams = c.inputs.fiberGrams, grams > 0 else { return nil }
        let id = "fiberWeek"
        let target = NutritionTargets.fiberTargetGrams.lowerBound
        let reference = "25-29 g a day went with the lowest risk across 185 studies."
        if grams < c.needed(id, "low", enter: NutritionTargets.fiberLowGrams, exit: NutritionTargets.fiberLowGrams + 2) {
            return Candidate(
                insight: Insight(
                    id: id, category: .nutrition, tone: .watch,
                    title: "Fibre is low: \(whole(grams)) g a day", comparison: reference,
                    action: "Add beans, lentils, oats or berries once a day."),
                variant: "low", subject: "fiber", strength: 1 - grams / target)
        }
        if grams >= c.needed(id, "met", enter: target, exit: target - 2) {
            return Candidate(
                insight: Insight(id: id, category: .nutrition, tone: .good, title: "Fibre is on target: \(whole(grams)) g a day",
                                 comparison: reference, action: nil),
                variant: "met", subject: "fiber", strength: 0.15, maxRun: standingRunDays, rest: standingRestDays)
        }
        return nil
    }

    /// Drinks this week against the usual week: a line from 3 standard
    /// drinks more or fewer (off under 1.5). App's choice; the weekly bands
    /// themselves are on the Longevity page.
    public static let alcoholEnterDrinks = 3.0

    static func alcohol(_ c: Context) -> Candidate? {
        let week = values(c.inputs.drinks, c, daysAgo: 0...6)
        let before = values(c.inputs.drinks, c, daysAgo: 7...34)
        guard week.count >= Longevity.alcoholMinimumNights, before.count >= 10 else { return nil }
        let total = week.reduce(0, +)
        let usual = before.reduce(0, +) / Double(before.count) * 7
        let delta = total - usual
        let variant = delta >= 0 ? "more" : "fewer"
        guard abs(delta) >= c.needed("alcoholWeek", variant, enter: alcoholEnterDrinks, exit: alcoholEnterDrinks / 2) else { return nil }
        let more = variant == "more"
        return Candidate(
            insight: Insight(
                id: "alcoholWeek", category: .habits, tone: more ? .watch : .good,
                title: "\(more ? "More" : "Fewer") drinks than usual this week",
                comparison: "\(Longevity.one(total)) in the last 7 evenings against about \(Longevity.one(usual)) in a usual week.",
                action: more ? "Alcohol and your sleep, under Patterns, shows what it does to your mornings." : nil),
            variant: variant, subject: "alcohol", strength: abs(delta) / 8)
    }

    /// Change in the week's average mood (valence, -1...1) that turns the
    /// line on (off under half). App's choice: a quarter of a point is more
    /// than half a step on the check-in's five-point scale.
    public static let moodEnterChange = 0.25

    static func mood(_ c: Context) -> Candidate? {
        guard let shift = Self.shift(c.inputs.mood, c, minimumBaseline: 8) else { return nil }
        let variant = shift.delta >= 0 ? "up" : "down"
        guard abs(shift.delta) >= c.needed("moodWeek", variant, enter: moodEnterChange, exit: moodEnterChange / 2) else { return nil }
        let up = variant == "up"
        let (before, now) = (MoodScale.word(valence: shift.baseline), MoodScale.word(valence: shift.recent))
        return Candidate(
            insight: Insight(
                id: "moodWeek", category: .habits, tone: up ? .good : .watch,
                title: "Your mood is \(up ? "up" : "lower") this week",
                comparison: before == now
                    ? "Your check-ins average \"\(now)\", a little \(up ? "higher" : "lower") than over the 4 weeks before."
                    : "Your check-ins average \"\(now)\" this week against \"\(before)\" over the 4 weeks before.",
                action: up ? nil : "Exercise and sleep are the two levers with trial evidence behind them."),
            variant: variant, subject: "mood", strength: abs(shift.delta))
    }

    /// Headphone sound over the WHO-ITU weekly limit (off again under 85%).
    static func hearing(_ c: Context) -> Candidate? {
        guard let percent = c.inputs.headphoneBudgetPercent,
              percent >= c.needed("hearing", "over", enter: 100, exit: 85) else { return nil }
        return Candidate(
            insight: Insight(
                id: "hearing", category: .habits, tone: .watch,
                title: "Headphone sound is over the weekly limit",
                comparison: "\(whole(percent))% of WHO's limit of 80 dB for 40 hours a week.",
                action: "One notch lower on the volume: 3 dB less doubles the safe time."),
            variant: "over", subject: "hearing", strength: min(1, percent / 200))
    }

    /// The strongest personal pattern from the check-ins, shown for two days
    /// and then not for three weeks (or until the pattern changes).
    static func pattern(_ c: Context) -> Candidate? {
        guard let pattern = c.inputs.pattern, !pattern.sentence.isEmpty else { return nil }
        return Candidate(
            insight: Insight(
                id: "pattern", category: .habits, tone: .neutral,
                title: pattern.sentence,
                comparison: "\(pattern.daysWith) days with against \(pattern.daysWithout) without. A pattern, not proof.",
                action: nil),
            variant: pattern.sentence, subject: "pattern", strength: 0.2, maxRun: standingRunDays, rest: standingRestDays)
    }

    /// When nothing else shows: one line naming the core measures that are
    /// close to usual. Never names a measure that has an active change.
    static func steadyWeek(_ c: Context, active: Set<String>) -> Insight? {
        var parts: [String] = []
        if !active.contains("rhr"), let rhr = shift(c.inputs.restingHeartRate, c) {
            parts.append("resting heart rate \(whole(rhr.recent)) bpm")
        }
        if !active.contains("hrv"), let hrv = shift(c.inputs.hrv, c) {
            parts.append("HRV \(whole(hrv.recent)) ms")
        }
        if !active.contains("sleepLength"), let sleep = shift(c.inputs.sleepHours, c) {
            parts.append("sleep \(Longevity.hoursText(sleep.recent)) a night")
        }
        guard !parts.isEmpty else { return nil }
        let last = parts.removeLast()
        let list = parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
        let sentence = list.prefix(1).uppercased() + String(list.dropFirst())
        return Insight(
            id: "steady", category: .recovery, tone: .neutral,
            title: "A steady week",
            comparison: sentence + ": close to your last 4 weeks.",
            action: nil)
    }

    // MARK: - For you

    /// The Longevity measure an insight is about, so "for you" doesn't say
    /// the same thing as a line above it.
    static let measureForInsight: [String: Longevity.MeasureID] = [
        "rhrTrend": .restingHeartRate, "vo2Trend": .vo2Max, "stepsWeek": .steps, "activeMinutes": .activeMinutes,
        "strengthWeeks": .strengthDays, "sleepWeek": .sleepDuration, "sleepRegularity": .sleepRegularity,
        "fiberWeek": .fiber, "proteinWeek": .protein, "alcoholWeek": .alcohol, "hearing": .headphoneSound
    ]

    /// Measures worth adding when missing: the strong-evidence ones a tape,
    /// a cuff or a walk can supply.
    static let worthAdding: [Longevity.MeasureID] = [.waistToHeight, .bloodPressure, .vo2Max]

    /// One or two longer-running suggestions: the most useful off-target
    /// Longevity measure, then one of the others, changing weekly so it
    /// isn't the same pair for months. With nothing off target: a missing
    /// measure worth adding, or one line saying so.
    static func forYou(_ assessment: Longevity.Assessment?, shown: [Insight], today: Date) -> [Suggestion] {
        guard let assessment else { return [] }
        let covered = Set(shown.compactMap { measureForInsight[$0.id] })
        let week = Int((today.timeIntervalSinceReferenceDate / 86_400).rounded(.down)) / 7
        func suggestion(_ measure: Longevity.Measure) -> Suggestion {
            let title: String
            if measure.status != .noData {
                title = "\(measure.title): \(measure.valueText ?? measure.status.label.lowercased())"
            } else {
                switch measure.id {
                case .waistToHeight: title = "Add a waist measurement"
                case .bloodPressure: title = "Add a blood pressure check"
                case .vo2Max: title = "Get a VO₂ max reading"
                default: title = "Add \(measure.title)"
                }
            }
            return Suggestion(id: measure.id.rawValue, title: title, detail: measure.nextStep, measure: measure.id)
        }
        var result: [Suggestion] = []
        let work = assessment.toWorkOn.filter { !covered.contains($0.id) }
        if let first = work.first {
            result.append(suggestion(first))
            let rest = Array(work.dropFirst())
            if !rest.isEmpty { result.append(suggestion(rest[week % rest.count])) }
        }
        if result.count < maxForYou {
            let missing = worthAdding.compactMap { assessment.measure($0) }.filter { $0.status == .noData }
            if !missing.isEmpty { result.append(suggestion(missing[week % missing.count])) }
        }
        if result.isEmpty, assessment.count(.onTarget) > 0 {
            result.append(Suggestion(id: "allOnTarget", title: "Everything measured is on target",
                                     detail: "Nothing to change. Longevity shows what each target is based on.", measure: nil))
        }
        return Array(result.prefix(maxForYou))
    }

    static func whole(_ value: Double) -> String { Longevity.whole(value) }
}
