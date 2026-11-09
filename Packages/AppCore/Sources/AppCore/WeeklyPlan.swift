import Foundation

// MARK: - The plan

/// One pre-committed training slot: when, what, for how long, and what to do
/// when the day goes wrong.
///
/// Deciding the "when and what" in advance is an implementation intention:
/// d = 0.65 across 94 tests (Gollwitzer & Sheeran, Adv Exp Soc Psychol 2006),
/// d = 0.31 for physical activity (Bélanger-Gravel et al., Health Psychol Rev
/// 2013). The if-then line is a coping plan, which predicted *maintenance* on
/// top of action planning (Sniehotta et al., Psychol Health 2005; cited from
/// memory in docs/research/behaviour-change.md).
public struct PlannedDay: Codable, Sendable, Equatable, Identifiable {
    /// `Calendar` weekday: 1 = Sunday … 7 = Saturday.
    public var weekday: Int
    /// Minutes after midnight, e.g. 18:00 = 1080.
    public var time: Int
    public var focus: WorkoutFocus
    /// Planned session length.
    public var minutes: Int
    /// Coping plan, e.g. "If I'm late, the 15-minute version".
    public var ifThen: String?
    /// The fallback length when the day goes wrong: two compound lifts, 2-3
    /// sets (docs/research/behaviour-change.md rec. 7; the habit is showing
    /// up, Lally et al., Eur J Soc Psychol 2010).
    public var shortVersionMinutes: Int = 15

    public var id: Int { weekday }

    public init(weekday: Int, time: Int, focus: WorkoutFocus, minutes: Int, ifThen: String? = nil, shortVersionMinutes: Int = 15) {
        self.weekday = weekday
        self.time = time
        self.focus = focus
        self.minutes = minutes
        self.ifThen = ifThen
        self.shortVersionMinutes = shortVersionMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case weekday, time, focus, minutes, ifThen, shortVersionMinutes
    }

    /// Plans saved before `shortVersionMinutes` existed decode with the 15-minute default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try container.decode(Int.self, forKey: .weekday)
        time = try container.decode(Int.self, forKey: .time)
        focus = try container.decode(WorkoutFocus.self, forKey: .focus)
        minutes = try container.decode(Int.self, forKey: .minutes)
        ifThen = try container.decodeIfPresent(String.self, forKey: .ifThen)
        shortVersionMinutes = try container.decodeIfPresent(Int.self, forKey: .shortVersionMinutes) ?? 15
    }

    /// e.g. "6:00 pm" in the user's locale.
    public func clockText(calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: .now)
        let date = calendar.date(bySettingHour: time / 60, minute: time % 60, second: 0, of: day) ?? day
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// A week (Monday start) of planned training days, plus the changes chosen
/// at the weekly review.
///
/// Which training-block week a plan falls in (sets ramp, RIR target, planned
/// deload) is not stored here: the block lives beside the plans
/// (`TrainingBlock`, kept by the app's `WeeklyPlanStore`) and its
/// `weekStart` says which plan week it covers.
public struct WeeklyPlan: Codable, Sendable, Equatable {
    /// How the week's sessions are held to days.
    ///
    /// - `fixedDays`: each session has its weekday and time, an implementation
    ///   intention (Gollwitzer & Sheeran 2006, d = 0.65; Bélanger-Gravel 2013,
    ///   d = 0.31 for physical activity). The stronger evidence is here.
    /// - `flexible`: a number of sessions a week, done on whichever days feel
    ///   right. The evidence is thinner and indirect: autonomy support
    ///   predicts adherence (Teixeira et al. 2012; Ntoumanis et al. 2021,
    ///   docs/research/behaviour-change.md rec. 5), HRV-guided day selection
    ///   (train when recovered, go easy when not) did as well as or better
    ///   than fixed plans in small trials (Kiviniemi et al., Eur J Appl Physiol
    ///   2007; Javaloyes et al., IJSPP 2019; both from memory in
    ///   docs/research/strain-science.md), and for equal weekly volume the
    ///   spread across the week makes little difference (Schoenfeld, Grgic &
    ///   Krieger 2019). No trial has compared flexible with fixed training
    ///   days directly, so the editor says so.
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case fixedDays
        case flexible
    }

    /// Start of the Monday that begins the week.
    public var weekStart: Date
    /// The week's sessions. In `fixedDays` mode each is tied to its weekday;
    /// in `flexible` mode they are the sessions to get done in any order on
    /// any day (the weekday is only the session's id and a default time).
    public var plannedDays: [PlannedDay]
    /// Up to three changes the user confirmed for this week at the review
    /// (review of goals: Michie et al., Health Psychol 2009).
    public var changes: [String]
    /// Fixed weekdays (plans saved before modes existed decode as this) or a
    /// weekly quota on any days.
    public var mode: Mode
    /// Sessions to do this week in `flexible` mode; nil means one per
    /// `plannedDays` entry.
    public var sessionsPerWeek: Int?
    /// Easy cardio sessions this week (`EasyCardio`, placed by `CardioPlanner`).
    /// They never count toward the lifting quota: `sessionTarget` is lifting only.
    public var cardio: EasyCardio?

    public init(weekStart: Date, plannedDays: [PlannedDay] = [], changes: [String] = [],
                mode: Mode = .fixedDays, sessionsPerWeek: Int? = nil, cardio: EasyCardio? = nil) {
        self.weekStart = weekStart
        self.plannedDays = plannedDays
        self.changes = changes
        self.mode = mode
        self.sessionsPerWeek = sessionsPerWeek
        self.cardio = cardio
    }

    private enum CodingKeys: String, CodingKey {
        case weekStart, plannedDays, changes, mode, sessionsPerWeek, cardio
    }

    /// Plans saved before `mode` existed are fixed-day plans.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decode(Date.self, forKey: .weekStart)
        plannedDays = try container.decodeIfPresent([PlannedDay].self, forKey: .plannedDays) ?? []
        changes = try container.decodeIfPresent([String].self, forKey: .changes) ?? []
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .fixedDays
        sessionsPerWeek = try container.decodeIfPresent(Int.self, forKey: .sessionsPerWeek)
        // Plans saved before easy cardio existed have none.
        cardio = try container.decodeIfPresent(EasyCardio.self, forKey: .cardio)
    }

    public var isFlexible: Bool { mode == .flexible }

    /// Sessions the week asks for: the quota in flexible mode, else the
    /// number of planned days. What the consistency score counts against.
    public var sessionTarget: Int {
        isFlexible ? (sessionsPerWeek ?? plannedDays.count) : plannedDays.count
    }

    /// Days left in the week containing `now`, today included (Monday 7 …
    /// Sunday 1).
    public static func daysLeft(now: Date, calendar: Calendar = .current) -> Int {
        7 - order(calendar.component(.weekday, from: now))
    }

    /// Where a week stands against its session target.
    public struct Progress: Sendable, Equatable {
        public var target: Int
        /// Training days so far this week (any day counts).
        public var done: Int
        /// Days left this week, today included.
        public var daysLeft: Int
        public var trainedToday: Bool

        public init(target: Int, done: Int, daysLeft: Int, trainedToday: Bool) {
            self.target = target
            self.done = done
            self.daysLeft = daysLeft
            self.trainedToday = trainedToday
        }

        /// Sessions still to do, never negative.
        public var remaining: Int { max(0, target - done) }
        public var isMet: Bool { remaining == 0 }
        /// Rest days still available after the remaining sessions; 0 or less
        /// means every day left is needed.
        public var slack: Int { daysLeft - remaining - (trainedToday ? 1 : 0) }
        /// "2 of 4 done · 3 days left".
        public var label: String {
            "\(min(done, target)) of \(target) done · \(daysLeft) \(daysLeft == 1 ? "day" : "days") left"
        }
    }

    /// Sessions done against the target as of `now` (which must fall in this
    /// plan's week).
    public func progress(trainingDays: [Date], now: Date = .now, calendar: Calendar = .current) -> Progress {
        let days = Set(trainingDays.map { calendar.startOfDay(for: $0) })
            .filter { $0 >= weekStart && $0 < (calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart) }
        let today = calendar.startOfDay(for: now)
        return Progress(target: sessionTarget, done: days.count, daysLeft: Self.daysLeft(now: now, calendar: calendar),
                        trainedToday: days.contains(today))
    }

    /// In flexible mode, the session to do next: the first of the week's
    /// sessions not yet done (by count, since days aren't fixed). Nil when
    /// the quota is met or the plan has fixed days.
    public func nextFlexibleSession(done: Int) -> PlannedDay? {
        guard isFlexible, done < sessionTarget else { return nil }
        let sessions = sortedDays
        guard !sessions.isEmpty else { return nil }
        return sessions[min(done, sessions.count - 1)]
    }

    /// The fewest and most training days a week the planner offers.
    public static let dayRange = 2...6

    /// Calendar weekdays in Monday-first order.
    public static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    /// Planned days, Monday first.
    public var sortedDays: [PlannedDay] {
        plannedDays.sorted { Self.order($0.weekday) < Self.order($1.weekday) }
    }

    public func day(for weekday: Int) -> PlannedDay? {
        plannedDays.first { $0.weekday == weekday }
    }

    /// When a planned day starts, as a date in this plan's week (for
    /// reminders tied to the planned slot).
    public func start(of day: PlannedDay, calendar: Calendar = .current) -> Date? {
        guard let date = calendar.date(byAdding: .day, value: Self.order(day.weekday), to: weekStart) else { return nil }
        return calendar.date(bySettingHour: day.time / 60, minute: day.time % 60, second: 0, of: date)
    }

    /// The Monday (start of day) of the week containing `date`, whatever the
    /// calendar's first weekday is.
    public static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysBack = (weekday + 5) % 7 // Sunday (1) → 6, Monday (2) → 0, Tuesday (3) → 1 …
        return calendar.date(byAdding: .day, value: -daysBack, to: day) ?? day
    }

    /// Position of a weekday in a Monday-first week (0 = Monday … 6 = Sunday).
    public static func order(_ weekday: Int) -> Int {
        weekdayOrder.firstIndex(of: weekday) ?? 0
    }

    /// Short weekday name for a `Calendar` weekday, e.g. "Mon".
    public static func weekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        guard (1...7).contains(weekday), symbols.count == 7 else { return "" }
        return symbols[weekday - 1]
    }

    /// Weekdays in this week that have at least one logged training day.
    public func doneWeekdays(trainingDays: [Date], calendar: Calendar = .current) -> Set<Int> {
        guard let end = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return [] }
        return Set(trainingDays.filter { $0 >= weekStart && $0 < end }.map { calendar.component(.weekday, from: $0) })
    }

    /// Days per week to suggest for a goal: 2-3 for health, 3-4 for muscle
    /// and strength (docs/research/behaviour-change.md rec. 2 tailoring),
    /// kept to the lower end so the plan is easy to keep (Lally 2010:
    /// consistency builds the habit, not volume).
    public static func suggestedDayCount(goals: Goals?) -> Int {
        guard let goals else { return 3 }
        if goals.focuses.contains(.muscle) || goals.focuses.contains(.strength) { return 4 }
        return 3
    }

    /// The default session for each planned day, so every muscle is trained
    /// at least twice a week (ACSM position stand, Med Sci Sports Exerc 2026:
    /// every major muscle group ≥2 days a week; frequency matters for
    /// strength: Grgic et al., Sports Med 2018; and one session can only hold
    /// about 6-10 productive sets for a muscle: Pelland et al., Sports Med
    /// 2026): 1 day full body; 2 days full body twice; 3 days upper, lower,
    /// full body; 4 days upper/lower twice; 5 days upper, lower, push, pull,
    /// legs; 6 days push/pull/legs twice. Starts from the focus that has
    /// rested longest (`WorkoutPlanner.suggestedFocus`) where the split
    /// allows. Every focus is a session the trainer can build. Only new plans
    /// use this; saved plans keep their days (audit 2026-11 §6: 3- and 5-day
    /// push/pull/legs trained each muscle about once a week).
    public static func focusRotation(start: WorkoutFocus, count: Int) -> [WorkoutFocus] {
        guard count > 0 else { return [] }
        let lowerFirst = start == .legs || start == .lower
        switch count {
        case 1, 2: return Array(repeating: .fullBody, count: count)
        case 3: return lowerFirst ? [.lower, .upper, .fullBody] : [.upper, .lower, .fullBody]
        case 4: return lowerFirst ? [.lower, .upper, .lower, .upper] : [.upper, .lower, .upper, .lower]
        case 5: return lowerFirst ? [.lower, .upper, .push, .pull, .legs] : [.upper, .lower, .push, .pull, .legs]
        default:
            let cycle: [WorkoutFocus] = [.push, .pull, .legs]
            let first: WorkoutFocus = switch start {
            case .pull: .pull
            case .legs, .lower: .legs
            default: .push
            }
            let offset = cycle.firstIndex(of: first) ?? 0
            return (0..<count).map { cycle[($0 + offset) % cycle.count] }
        }
    }

    /// Weekdays to suggest for `count` sessions, spread across Monday-Saturday
    /// with Sunday free: 2 → Tue, Fri; 3 → Mon, Wed, Fri; 4 → Mon, Tue, Thu,
    /// Fri; 5 → Mon-Fri; 6 → Mon-Sat.
    public static func suggestedWeekdays(count: Int) -> [Int] {
        switch count {
        case ...0: []
        case 1: [3]
        case 2: [3, 6]
        case 3: [2, 4, 6]
        case 4: [2, 3, 5, 6]
        case 5: [2, 3, 4, 5, 6]
        default: [2, 3, 4, 5, 6, 7]
        }
    }

    /// Ready-made coping plans for the three commonest obstacles (travel, low
    /// energy, running late; docs/research/behaviour-change.md rec. 3).
    public static let ifThenSuggestions = [
        "If I'm late, the 15-minute version",
        "If I'm tired, an easy-day session",
        "If I'm travelling, bodyweight at the hotel",
    ]
}

// MARK: - What happened

/// One week's planned and done sessions, for the consistency score.
public struct WeekRecord: Codable, Sendable, Equatable {
    public var weekStart: Date
    public var planned: Int
    /// Days with a logged session that week (any day counts, planned or not:
    /// weekly total matters, not the pattern; dos Santos et al., JAMA Intern
    /// Med 2022, from memory in docs/research/behaviour-change.md). So the
    /// score is sessions against the week's target in both plan modes, never
    /// weekday matches.
    public var done: Int

    public init(weekStart: Date, planned: Int, done: Int) {
        self.weekStart = weekStart
        self.planned = planned
        self.done = done
    }

    /// Distinct training days in the plan's week.
    public static func make(plan: WeeklyPlan, trainingDays: [Date], calendar: Calendar = .current) -> WeekRecord {
        let days = Set(trainingDays.map { calendar.startOfDay(for: $0) })
            .filter { $0 >= plan.weekStart && $0 < (calendar.date(byAdding: .day, value: 7, to: plan.weekStart) ?? plan.weekStart) }
        return WeekRecord(weekStart: plan.weekStart, planned: plan.sessionTarget, done: days.count)
    }
}

/// Rolling 4-week consistency: weeks kept of weeks planned. Never a streak
/// and never a "broken chain": missing a single day did not derail habit
/// formation (Lally et al. 2010), and *displaying* a broken streak lowers
/// later engagement, less so when it can be repaired (Silverman & Barasch,
/// J Consum Res 2023). Monitoring progress against a plan is what helps
/// (Harkin et al., Psychol Bull 2016, d = 0.40).
public enum Consistency {
    /// Weeks the score looks back over.
    public static let windowWeeks = 4
    /// A week is kept at 3 of 4 planned sessions (docs/research/behaviour-change.md rec. 4).
    public static let keptFraction = 0.75

    public struct Result: Sendable, Equatable {
        /// Weeks that were kept, of the weeks that had a plan.
        public var keptWeeks: Int
        public var plannedWeeks: Int
        /// kept ÷ planned, 0 when nothing was planned yet.
        public var score: Double
        /// "3 of 4 weeks" or "Getting going".
        public var label: String
        /// Shown after a week that wasn't kept: what to do, never what was lost.
        public var note: String?
    }

    /// Sessions needed for a week to count: 3/4 of planned, rounded up, but
    /// never more than planned − 1 for small plans (so 2 planned needs 1,
    /// 3 needs 2). One planned session needs that one.
    public static func sessionsNeeded(planned: Int) -> Int {
        guard planned > 0 else { return 0 }
        let fraction = Int((Double(planned) * keptFraction).rounded(.up))
        return max(1, min(fraction, planned - 1))
    }

    public static func weekKept(planned: Int, done: Int) -> Bool {
        planned > 0 && done >= sessionsNeeded(planned: planned)
    }

    /// Score over the last `windowWeeks` weeks ending with the week that
    /// contains `now`. The current week is still in progress, so it counts
    /// only once it is already kept; it can never pull the score down.
    public static func score(records: [WeekRecord], now: Date = .now, calendar: Calendar = .current) -> Result {
        let thisWeek = WeeklyPlan.weekStart(containing: now, calendar: calendar)
        guard let windowStart = calendar.date(byAdding: .day, value: -7 * (windowWeeks - 1), to: thisWeek) else {
            return Result(keptWeeks: 0, plannedWeeks: 0, score: 0, label: "Getting going", note: nil)
        }
        let window = records
            .filter { $0.planned > 0 && $0.weekStart >= windowStart && $0.weekStart <= thisWeek }
            .sorted { $0.weekStart < $1.weekStart }
        var kept = 0
        var counted = 0
        for record in window {
            let isKept = weekKept(planned: record.planned, done: record.done)
            if calendar.isDate(record.weekStart, inSameDayAs: thisWeek) {
                if isKept { kept += 1; counted += 1 }
            } else {
                counted += 1
                if isKept { kept += 1 }
            }
        }
        let score = counted > 0 ? Double(kept) / Double(counted) : 0
        let label = counted >= 2 ? "\(kept) of \(counted) weeks" : "Getting going"
        // The most recent finished week, if it wasn't kept.
        let lastFinished = window.last { !calendar.isDate($0.weekStart, inSameDayAs: thisWeek) }
        let note: String? = lastFinished.map { weekKept(planned: $0.planned, done: $0.done) } == false
            ? "Last week was lighter than planned. One week off changes nothing; this week counts as soon as you show up."
            : nil
        return Result(keptWeeks: kept, plannedWeeks: counted, score: score, label: label, note: note)
    }

    /// How many recent finished weeks in a row had at least `minimum`
    /// sessions, for the identity line ("you're someone who trains twice a
    /// week": identity–behaviour r = 0.44, Rhodes et al., Health Psychol Rev
    /// 2016). Positive only: callers show it from 3 weeks and say nothing
    /// otherwise, so there is no chain to break.
    public static func weeksTrainingAtLeast(_ minimum: Int, records: [WeekRecord], now: Date = .now, calendar: Calendar = .current) -> Int {
        let thisWeek = WeeklyPlan.weekStart(containing: now, calendar: calendar)
        let byWeek = Dictionary(records.map { ($0.weekStart, $0) }, uniquingKeysWith: { _, latest in latest })
        var weeks = 0
        var cursor = calendar.date(byAdding: .day, value: -7, to: thisWeek)
        while let week = cursor, let record = byWeek[week], record.done >= minimum {
            weeks += 1
            cursor = calendar.date(byAdding: .day, value: -7, to: week)
        }
        return weeks
    }
}

// MARK: - Coming back

/// After a week or more off: a smaller plan and a message without guilt.
///
/// A lapse becomes a relapse when it is read as failure (Marlatt & Gordon
/// 1985); self-compassion after a setback predicts getting back (Semenchuk
/// et al., J Sport Exerc Psychol 2018); strength and VO₂max fall little in
/// 2-3 weeks of not training (Mujika & Padilla, Sports Med 2000). All three
/// cited from memory in docs/research/behaviour-change.md, so the wording
/// stays cautious.
public enum RestartPlan {
    /// Days without a session before the restart path shows (report rec. 11).
    public static let daysOffThreshold = 7
    /// The fewest sessions a restart week has.
    public static let minimumDays = 2

    public struct Result: Sendable, Equatable {
        public var plannedDays: [PlannedDay]
        public var message: String
    }

    /// Whole days since the last training day, nil when there has never been one.
    public static func daysOff(lastTrained: Date?, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let lastTrained else { return nil }
        let from = calendar.startOfDay(for: lastTrained)
        let to = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Half the last plan's days (at least two), each at its short version for
    /// the first week back. With no earlier plan, two short full-body sessions.
    /// Returns nil under `daysOffThreshold` days off.
    public static func make(daysOff: Int, lastPlan: WeeklyPlan?, goals: Goals? = nil) -> Result? {
        guard daysOff >= daysOffThreshold else { return nil }
        let previous = lastPlan?.sortedDays ?? []
        var days: [PlannedDay]
        if previous.count > minimumDays {
            let target = max(minimumDays, Int((Double(previous.count) / 2).rounded(.up)))
            let step = Double(previous.count - 1) / Double(target - 1)
            let indices = (0..<target).map { Int((Double($0) * step).rounded()) }
            days = indices.map { previous[$0] }
        } else if !previous.isEmpty {
            days = previous
        } else {
            days = WeeklyPlan.suggestedWeekdays(count: minimumDays).map {
                PlannedDay(weekday: $0, time: 18 * 60, focus: .fullBody, minutes: 15, ifThen: WeeklyPlan.ifThenSuggestions[0])
            }
        }
        for index in days.indices {
            days[index].minutes = days[index].shortVersionMinutes
        }
        var message = "Little fitness is lost in two weeks; the first week back is about showing up. Here's a lighter week: \(days.count) short sessions."
        if goals?.focuses.contains(.strength) == true {
            // Report rec. 11 tailoring: strength goals resume at 85-90% of the last loads.
            message += " Start lifts at about 85-90% of where you left off."
        }
        return Result(plannedDays: days, message: message)
    }
}
