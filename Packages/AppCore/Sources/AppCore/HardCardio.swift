import Foundation

/// One hard cardio session a week, offered and never scheduled for you: four
/// rounds of four hard minutes with three easy (or three rounds), in place of
/// one of the week's easy sessions (`EasyCardio.hard`, `IntervalSession`).
///
/// Why offer it:
/// - Fitness matters: each 1-MET higher cardiorespiratory fitness goes with
///   11-17% lower all-cause mortality (Lang JJ et al., Br J Sports Med
///   2024;58(10):556-566; overview of meta-analyses, 199 cohorts; association).
/// - Intervals raise VO2max by about 5.5 mL/kg/min against no exercise and 1.2
///   more than steady endurance work (Milanović Z, Sporiš G, Weston M, Sports
///   Med 2015;45(10):1469-1481), most with long intervals and 15+ hard minutes
///   (Wen D et al., J Sci Med Sport 2019; see `IntervalSession`).
/// - 15-20 vigorous minutes a week went with 16-40% lower mortality in
///   wearable data, with the lowest risk at about 54 (Ahmadi MN et al., Eur
///   Heart J 2022;43(46):4801-4814; observational).
/// - Cardio beside lifting doesn't cost muscle or maximal strength; explosive
///   strength may suffer when both share a session (Schumann M et al., Sports
///   Med 2022;52:601-612).
/// Milanović 2015 and Ahmadi 2022 (Eur Heart J 2022;43(46):4801-4814: 15-20
/// vigorous minutes a week, 16-40% lower mortality hazard; optimum about 54)
/// were re-read from their PubMed abstracts on 2026-11-17. Lang 2024 and
/// Schumann 2022 are as read for docs/research/healthy-living-2026-11.md, not
/// re-verified here. The trials gave intervals two or three times a week
/// (Helgerud 2007: three); one a week is the app's smaller dose, chosen so the
/// lifting stays first, and the UI says the evidence for it is thinner.
///
/// The risks are rules:
/// - **Offered, never scheduled by default**, and only when a reason applies
///   (`Reason`). Once taken it stays until you switch it off.
/// - **Vigorous minutes, not a VO2 max number.** A watch estimates VO2 max
///   slowly and only from outdoor walks and runs, so the session promises its
///   hard minutes and nothing about that number (`promise`).
/// - **Never the day before heavy legs or on a heavy leg day** (`weekday`),
///   never as a hard session on a day that reads as easy (`dayNote`), and not
///   in a busy week, a planned deload week, rest mode, or a hard cut
///   (`blocker`): extra fatigue on a steep deficit is the risk the research
///   file names. Where the session goes in the week is the app's choice.
/// - **Only on what the gym has** (`modalities`): its bike, rower or
///   treadmill (`GymProfile.cardioMachines`), or outdoors.
public enum HardCardio {
    /// What you chose when you took the offer.
    public struct Choice: Codable, Sendable, Equatable {
        public var modality: IntervalSession.Modality
        /// Three rounds instead of four.
        public var isShort: Bool

        public init(modality: IntervalSession.Modality, isShort: Bool = false) {
            self.modality = modality
            self.isShort = isShort
        }

        /// The session, step by step.
        public var session: IntervalSession {
            isShort ? .threeByFour(modality) : .fourByFour(modality)
        }
    }

    // MARK: Constants

    /// Under this many vigorous minutes in the last 7 days the session is
    /// offered: the bottom of the 15-20 a week in Ahmadi 2022.
    public static let vigorousMinutesFloor = 15
    /// VO2 max counts as flat when it rose by less than this over a block
    /// (ml/kg/min). App's choice: about the size of week-to-week wobble in a
    /// watch estimate, not a published threshold.
    public static let flatChange = 1.0
    /// A VO2 max reading older than this says nothing about now. App's choice.
    public static let staleReadingDays = 28
    /// Losing this share of body weight a week or faster is a hard cut: no
    /// hard session is offered or run. App's choice inside the planner's 1% a
    /// week limit (`GoalPlanner.RateLimit`); the research file names extra
    /// fatigue during a cut as the risk without giving a line.
    public static let hardCutRatePercent = 0.75
    /// A workout this long of the session's type counts as it done. App's choice.
    public static let minimumDoneMinutes = 20

    // MARK: When it may run

    /// Losing weight at `hardCutRatePercent` a week or faster.
    public static func isHardCut(_ goals: Goals?) -> Bool {
        guard let goals else { return false }
        return goals.weight == .lose && goals.weeklyRatePercent >= hardCutRatePercent - 0.0001
    }

    /// Why no hard session runs this week.
    public enum Blocker: Sendable, Equatable {
        case busyWeek, hardCut, restMode, deloadWeek
        /// A fixed-day week where every day is a heavy leg day or the day before one.
        case noDay

        /// One line for the plan.
        public var text: String {
            switch self {
            case .busyWeek: "No intervals in a busy week."
            case .hardCut: "No intervals while you're losing weight this fast: easy cardio only."
            case .restMode: "No intervals in rest mode."
            case .deloadWeek: "No intervals in the planned easier week."
            case .noDay: "No day suits intervals this week: every free day is a leg day or the day before one."
            }
        }
    }

    public static func blocker(plan: WeeklyPlan, goals: Goals?, restMode: Bool = false, isDeloadWeek: Bool = false) -> Blocker? {
        if plan.isBusy { return .busyWeek }
        if restMode { return .restMode }
        if isHardCut(goals) { return .hardCut }
        if isDeloadWeek { return .deloadWeek }
        if !plan.isFlexible, weekday(for: plan) == nil { return .noDay }
        return nil
    }

    // MARK: Where it goes

    /// The day for the hard session in a fixed-day week, best first: a rest
    /// day, then an upper-body day; a day after heavy legs only when nothing
    /// else is free. Never a heavy leg day (squats and hinges on tired legs,
    /// and both in one session may blunt explosive strength, Schumann 2022)
    /// and never the day before one (hard intervals tire the quads). Sunday's
    /// "day before" is next Monday, taken to be the same as this week's.
    /// Nil when no day is allowed, and for a flexible week (any day).
    public static func weekday(for plan: WeeklyPlan) -> Int? {
        guard !plan.isFlexible else { return nil }
        var best: (weekday: Int, score: Double)?
        for weekday in WeeklyPlan.weekdayOrder {
            let position = WeeklyPlan.order(weekday)
            let next = WeeklyPlan.weekdayOrder[(position + 1) % 7]
            let previous = WeeklyPlan.weekdayOrder[(position + 6) % 7]
            let lifting = plan.day(for: weekday)
            if let lifting, CardioPlanner.isHeavyLower(lifting.focus) { continue }
            if let tomorrow = plan.day(for: next), CardioPlanner.isHeavyLower(tomorrow.focus) { continue }
            var score = lifting == nil ? 0.0 : 2.0
            if let yesterday = plan.day(for: previous), CardioPlanner.isHeavyLower(yesterday.focus) { score += 1 }
            if score < (best?.score ?? .infinity) { best = (weekday, score) }
        }
        return best?.weekday
    }

    /// The week's hard session and its day.
    public struct Slot: Sendable, Equatable {
        /// Nil in a flexible week: any day that isn't before a leg session.
        public var weekday: Int?
        public var choice: Choice

        public var session: IntervalSession { choice.session }
    }

    /// The hard session as it runs in this plan's week: chosen, the week
    /// isn't busy, the cut isn't hard, and (fixed days) a day allows it.
    /// Rest mode and the block's deload week are the caller's to check
    /// (`blocker`): the plan doesn't know them.
    public static func slot(for plan: WeeklyPlan, goals: Goals?) -> Slot? {
        guard let choice = plan.cardio?.hard, !plan.isBusy, !isHardCut(goals) else { return nil }
        if plan.isFlexible { return Slot(weekday: nil, choice: choice) }
        guard let weekday = weekday(for: plan) else { return nil }
        return Slot(weekday: weekday, choice: choice)
    }

    /// Said on the session's own day when the day reads as easy (recovery
    /// under the moderate band or 7-day HRV below normal): never a hard
    /// session on an easy-recovery day. Also when the week's queue
    /// (`AdaptiveWeek`) has put a heavy leg session on that day or the next,
    /// as it does when a missed one moves: the same two days `weekday(for:)`
    /// keeps clear. Nil on any other day.
    /// - Parameters:
    ///   - queueToday: the focus the queue has today, if any.
    ///   - queueTomorrow: the focus the queue has tomorrow, if any.
    public static func dayNote(slot: Slot, weekday today: Int, lowRecovery: Bool,
                               queueToday: WorkoutFocus? = nil, queueTomorrow: WorkoutFocus? = nil) -> String? {
        guard slot.weekday == nil || slot.weekday == today else { return nil }
        if lowRecovery {
            return "Today reads as an easy day, so no intervals today: an easy \(EasyCardio.shortMinutes) minutes instead, or leave it. The intervals keep for another day."
        }
        if let queueToday, CardioPlanner.isHeavyLower(queueToday) {
            return "Legs are on today now, so no intervals today. They keep for another day."
        }
        if let queueTomorrow, CardioPlanner.isHeavyLower(queueTomorrow) {
            return "Legs are on tomorrow now, and intervals today would tire them. They keep for another day."
        }
        return nil
    }

    // MARK: What the gym has

    /// What the session can be done on here: the gym's own machines, the
    /// bike first (cycling, unlike running, didn't go with smaller fibre
    /// gains: Lundberg et al., Sports Med 2022, as in `CardioPlanner`), then
    /// outdoors. A gym that never said which machines it has offers outdoors only.
    public static func modalities(gym: GymProfile?) -> [IntervalSession.Modality] {
        let machines = gym?.cardioMachines ?? []
        var result: [IntervalSession.Modality] = []
        if machines.contains(.bike) { result.append(.bike) }
        if machines.contains(.rower) { result.append(.rower) }
        if machines.contains(.treadmill) { result.append(.treadmill) }
        return result + [.outdoorRide, .outdoorRun]
    }

    /// `choice` if this gym can do it, else the first thing it can.
    public static func supported(_ choice: Choice, gym: GymProfile?) -> Choice {
        let options = modalities(gym: gym)
        guard !options.contains(choice.modality), let first = options.first else { return choice }
        return Choice(modality: first, isShort: choice.isShort)
    }

    // MARK: The offer

    public enum Reason: Sendable, Equatable {
        /// VO2 max rose by less than `flatChange` over about this many weeks.
        case flatFitness(weeks: Int)
        /// Under "good" (the median) for age and sex (`VO2Norms`).
        case belowGood(category: String)
        /// Vigorous minutes in the last 7 days, under `vigorousMinutesFloor`.
        case fewVigorousMinutes(Int)

        public var text: String {
            switch self {
            case .flatFitness(let weeks):
                "Your cardio fitness has been flat for about \(weeks) weeks."
            case .belowGood(let category):
                "Your cardio fitness reads \(category.lowercased()) for your age, under \"good\"."
            case .fewVigorousMinutes(let minutes):
                "\(minutes) vigorous \(minutes == 1 ? "minute" : "minutes") in the last 7 days; 15-20 a week is where the evidence points."
            }
        }
    }

    public struct Offer: Sendable, Equatable {
        public var reasons: [Reason]
        /// What this gym can do it on, best first.
        public var modalities: [IntervalSession.Modality]
        /// The day it would take in a fixed-day week; nil in a flexible one.
        public var weekday: Int?
        /// True when it takes the place of an easy session the plan has.
        public var replacesEasy: Bool

        /// The first reason, as the offer's one line.
        public var reasonText: String { reasons.first?.text ?? "" }
    }

    /// True, false, or nil when the readings can't say: the newest reading
    /// against the newest one at least `weeks` weeks older (and no more than
    /// twice that), flat when it rose by less than `flatChange`.
    public static func isFlat(_ history: [DayValue], weeks: Int, now: Date) -> Bool? {
        let day = 86_400.0
        let readings = history.filter { $0.value > 0 && $0.date <= now }.sorted { $0.date < $1.date }
        guard weeks > 0, let latest = readings.last,
              now.timeIntervalSince(latest.date) <= Double(staleReadingDays) * day else { return nil }
        let span = Double(weeks) * 7 * day
        guard let earlier = readings.last(where: { latest.date.timeIntervalSince($0.date) >= span }),
              latest.date.timeIntervalSince(earlier.date) <= 2 * span else { return nil }
        return latest.value - earlier.value < flatChange
    }

    /// The offer for this plan's week, or nil when nothing calls for it or
    /// the week can't take it (`blocker`).
    /// - Parameters:
    ///   - vo2: the VO2 max the app scores with, with `age` and `sex` for the norm.
    ///   - vo2History: dated VO2 max readings (the watch's), for `isFlat`.
    ///   - blockWeeks: the training block's length: "flat for a block".
    ///   - weeklyVigorousMinutes: vigorous minutes in the last 7 days; nil without heart-rate data.
    public static func offer(plan: WeeklyPlan, goals: Goals?, gym: GymProfile?, vo2: Double?, age: Int?,
                             sex: BiologicalSex?, vo2History: [DayValue] = [], blockWeeks: Int,
                             weeklyVigorousMinutes: Int?, restMode: Bool = false, isDeloadWeek: Bool = false,
                             now: Date = .now) -> Offer? {
        guard blocker(plan: plan, goals: goals, restMode: restMode, isDeloadWeek: isDeloadWeek) == nil else { return nil }
        var reasons: [Reason] = []
        if isFlat(vo2History, weeks: blockWeeks, now: now) == true { reasons.append(.flatFitness(weeks: blockWeeks)) }
        if let vo2, vo2 > 0, let age, let sex {
            let category = VO2Norms.category(vo2: vo2, age: age, sex: sex)
            if category < .good { reasons.append(.belowGood(category: category.name)) }
        }
        if let minutes = weeklyVigorousMinutes, minutes < vigorousMinutesFloor {
            reasons.append(.fewVigorousMinutes(max(0, minutes)))
        }
        guard !reasons.isEmpty else { return nil }
        return Offer(reasons: reasons, modalities: modalities(gym: gym), weekday: weekday(for: plan),
                     replacesEasy: (plan.cardio?.sessionsPerWeek ?? 0) > 0)
    }

    // MARK: Words

    /// What the session gives, and what it doesn't promise.
    public static func promise(_ session: IntervalSession) -> String {
        var text = "About \(session.totalMinutes) minutes, \(session.hardMinutes) of them hard: vigorous minutes toward the 15-20 a week linked with lower mortality in wearable data (Ahmadi 2022; an association, not proof). No promise about your VO2 max number: a watch estimates it slowly, and only from outdoor walks and runs. The interval trials ran two or three sessions a week; one a week is a smaller dose with less evidence behind it."
        if session.hardMinutes < 15 {
            text += " The longer session's 16 hard minutes are nearer what the trials found works best (Wen 2019)."
        }
        return text
    }

    /// Where it sits in the week, for the plan editor.
    public static func placementText(weekday: Int?, replacesEasy: Bool, calendar: Calendar = .current) -> String {
        let place = weekday.map { "On \(WeeklyPlan.weekdayName($0, calendar: calendar))" } ?? "On any day"
        let swap = replacesEasy ? ", in place of one easy session" : ", as the week's one cardio session"
        let rule = weekday == nil ? " Not the day before a leg session, and not on a day that reads as easy."
                                  : " Never the day before heavy legs; on a day that reads as easy it waits."
        return place + swap + "." + rule
    }

    // MARK: Done

    /// Whether the week's hard session is done, and which easy slots are,
    /// from Apple Health workouts. Fixed days: a workout of the session's
    /// type on its day. Flexible: any such workout of `minimumDoneMinutes`;
    /// when the easy sessions are the same type, that one workout day isn't
    /// counted for them too.
    public static func weekDone(plan: WeeklyPlan, goals: Goals?, workouts: [CardioPlanner.Workout],
                                calendar: Calendar = .current) -> (hard: Bool, easy: Set<Int>) {
        let weekStart = plan.weekStart
        let slots = CardioPlanner.slots(for: plan, goals: goals)
        var easyDays: Set<Date> = []
        if let kind = slots.first?.kind {
            easyDays = CardioPlanner.doneDays(kind: kind, workouts: workouts, weekStart: weekStart, calendar: calendar)
        }
        guard let hard = slot(for: plan, goals: goals) else {
            return (false, CardioPlanner.done(slots: slots, doneDays: easyDays, weekStart: weekStart, calendar: calendar))
        }
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let names = hard.choice.modality.workoutNames
        let hardDays = Set(workouts
            .filter { names.contains($0.name) && $0.minutes >= minimumDoneMinutes && $0.start >= weekStart && $0.start < weekEnd }
            .map { calendar.startOfDay(for: $0.start) })
        if let weekday = hard.weekday {
            let day = calendar.date(byAdding: .day, value: WeeklyPlan.order(weekday), to: weekStart).map { calendar.startOfDay(for: $0) }
            let done = day.map { hardDays.contains($0) } ?? false
            return (done, CardioPlanner.done(slots: slots, doneDays: easyDays, weekStart: weekStart, calendar: calendar))
        }
        guard let first = hardDays.min() else {
            return (false, CardioPlanner.done(slots: slots, doneDays: easyDays, weekStart: weekStart, calendar: calendar))
        }
        // The same type as the easy sessions: that workout day is the hard one, not an easy one too.
        if let kind = slots.first?.kind, !kind.workoutNames.isDisjoint(with: names) { easyDays.remove(first) }
        return (true, CardioPlanner.done(slots: slots, doneDays: easyDays, weekStart: weekStart, calendar: calendar))
    }
}

extension IntervalSession.Modality {
    /// Apple Health workout names (`HealthKitClient`) that count as a session on it.
    public var workoutNames: Set<String> {
        switch self {
        case .bike, .outdoorRide: ["Ride"]
        case .rower: ["Row"]
        case .treadmill, .outdoorRun: ["Run"]
        }
    }
}
