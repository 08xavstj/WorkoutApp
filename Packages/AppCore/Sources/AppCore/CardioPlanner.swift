import Foundation

/// The weekly plan's easy cardio: 0-2 sessions of about 30 minutes, on a bike,
/// a rower or an incline walk.
///
/// - Adding cardio to lifting doesn't cost muscle growth or maximal strength;
///   explosive strength may suffer when both are done in the same session
///   (Schumann M, Feuerbacher JF, Sünkeler M, et al. Compatibility of
///   concurrent aerobic and strength training for skeletal muscle size and
///   function: an updated systematic review and meta-analysis. Sports Med
///   2022;52:601-612; 43 studies). Running, but not cycling, went with smaller
///   gains in type I muscle fibres (Lundberg TR, Feuerbacher JF, Sünkeler M,
///   Schumann M. The effects of concurrent aerobic and strength training on
///   muscle fiber hypertrophy: a systematic review and meta-analysis. Sports
///   Med 2022). So the choices are low-impact, the bike comes first for muscle
///   and strength goals, and a strength goal never gets cardio on a heavy
///   lower-body day.
/// - The minutes count toward WHO's 150-300 moderate minutes a week (Bull FC
///   et al., World Health Organization 2020 guidelines on physical activity
///   and sedentary behaviour, Br J Sports Med 2020;54:1451-1462): easy zone 2
///   work sits at about 40-55% of heart-rate reserve, which `IntensityMinutes`
///   counts as moderate (40%+).
/// - On the app's strain scale 30 minutes at 45% of reserve is about 15%
///   (`estimatedStrain`), inside a rest day's 0-25% (`TrainingDayPlanner`), so
///   a rest day can take it. On a low-recovery day it shrinks to the
///   15-minute version, the same rule as the lifting plan's short version.
/// - Where it goes in the week (rest days first, not the day before a leg
///   session, spread out) is the app's choice from the points above, not a
///   tested schedule.
public struct EasyCardio: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case bike, row, inclineWalk

        public var id: String { rawValue }

        /// "Bike", for pickers.
        public var label: String {
            switch self {
            case .bike: "Bike"
            case .row: "Row"
            case .inclineWalk: "Incline walk"
            }
        }

        /// "Easy ride", for the plan.
        public var title: String {
            switch self {
            case .bike: "Easy ride"
            case .row: "Easy row"
            case .inclineWalk: "Incline walk"
            }
        }

        public var systemImage: String {
            switch self {
            case .bike: "figure.outdoor.cycle"
            case .row: "figure.rower"
            case .inclineWalk: "figure.walk"
            }
        }

        /// Apple Health workout names (`HealthKitClient`) that count as this session.
        public var workoutNames: Set<String> {
            switch self {
            case .bike: ["Ride"]
            case .row: ["Row"]
            case .inclineWalk: ["Walk", "Hike", "Stairs"]
            }
        }
    }

    /// Sessions a week, 0-2.
    public var sessionsPerWeek: Int
    public var minutes: Int
    public var kind: Kind

    public init(sessionsPerWeek: Int, minutes: Int = EasyCardio.standardMinutes, kind: Kind = .bike) {
        self.sessionsPerWeek = max(0, min(EasyCardio.maximumPerWeek, sessionsPerWeek))
        self.minutes = minutes
        self.kind = kind
    }

    /// The most easy cardio sessions the plan schedules: the "1-2 easy
    /// sessions" of docs/research/lifting-features.md §3 pick 7, so lifting
    /// stays the main work for lifting goals (Schumann 2022 pooled programmes
    /// of a few sessions a week; the exact count is the app's choice).
    public static let maximumPerWeek = 2
    /// About 30 minutes a session: WHO's 150 moderate minutes a week is five
    /// such sessions (Bull et al. 2020), so two give 60 toward it.
    public static let standardMinutes = 30
    /// The short version on a low-recovery day, the same 15 minutes as the
    /// lifting plan's fallback (`PlannedDay.shortVersionMinutes`;
    /// docs/research/behaviour-change.md rec. 7).
    public static let shortMinutes = 15

    /// "Easy ride · 30 min".
    public var title: String { "\(kind.title) · \(minutes) min" }
}

public enum CardioPlanner {
    /// One cardio session in the week: on a weekday (fixed-day plans) or any
    /// day (flexible plans, `weekday` nil).
    public struct Slot: Sendable, Equatable, Identifiable {
        public var index: Int
        public var weekday: Int?
        public var kind: EasyCardio.Kind
        public var minutes: Int
        public var id: Int { index }

        public init(index: Int, weekday: Int?, kind: EasyCardio.Kind, minutes: Int) {
            self.index = index
            self.weekday = weekday
            self.kind = kind
            self.minutes = minutes
        }
    }

    /// A finished cardio workout from Apple Health.
    public struct Workout: Sendable, Equatable {
        public var name: String
        public var start: Date
        public var minutes: Int

        public init(name: String, start: Date, minutes: Int) {
            self.name = name
            self.start = start
            self.minutes = minutes
        }
    }

    /// The easy kind to suggest: the bike for muscle and strength goals
    /// (Lundberg 2022: cycling, unlike running, didn't go with smaller fibre
    /// gains; low impact on the legs), an incline walk otherwise.
    public static func recommendedKind(goals: Goals?) -> EasyCardio.Kind {
        guard let goals else { return .inclineWalk }
        if goals.focuses.contains(.muscle) || goals.focuses.contains(.strength) { return .bike }
        return .inclineWalk
    }

    /// Sessions with heavy lower-body work: squats and hinges.
    public static func isHeavyLower(_ focus: WorkoutFocus) -> Bool {
        switch focus {
        case .legs, .lower, .fullBody: true
        case .push, .pull, .upper: false
        }
    }

    /// Where the week's easy cardio goes.
    ///
    /// Flexible plans: one slot per session, on any day. Fixed days, best
    /// first: a rest day that isn't the day before a heavy lower session (a
    /// ride or row tires the quads, `MuscleRecovery.Cardio`), then a rest day
    /// before one, then an upper-body day, then a lower day, which a strength
    /// goal never gets (Schumann 2022: explosive strength may suffer with both
    /// in one session). Slots aren't put on neighbouring days when another day
    /// is as good. Ties go to the earlier day.
    public static func slots(for plan: WeeklyPlan, goals: Goals?) -> [Slot] {
        guard let cardio = plan.cardio, cardio.sessionsPerWeek > 0 else { return [] }
        let count = min(EasyCardio.maximumPerWeek, cardio.sessionsPerWeek)
        if plan.isFlexible {
            return (0..<count).map { Slot(index: $0, weekday: nil, kind: cardio.kind, minutes: cardio.minutes) }
        }
        let strengthGoal = goals?.focuses.contains(.strength) == true
        // Score each weekday: lower is better; nil means not allowed.
        var scores: [Int: Double] = [:]
        for weekday in WeeklyPlan.weekdayOrder {
            if let lifting = plan.day(for: weekday) {
                if isHeavyLower(lifting.focus) {
                    if !strengthGoal { scores[weekday] = 4 }
                } else {
                    scores[weekday] = 2
                }
            } else {
                let nextOrder = (WeeklyPlan.order(weekday) + 1) % 7
                let next = WeeklyPlan.weekdayOrder[nextOrder]
                let beforeLower = plan.day(for: next).map { isHeavyLower($0.focus) } ?? false
                scores[weekday] = beforeLower ? 1 : 0
            }
        }
        var picked: [Int] = []
        while picked.count < count {
            var best: (weekday: Int, score: Double)?
            for weekday in WeeklyPlan.weekdayOrder {
                guard var score = scores[weekday], !picked.contains(weekday) else { continue }
                let position = WeeklyPlan.order(weekday)
                if picked.contains(where: { abs(WeeklyPlan.order($0) - position) == 1 }) { score += 0.5 }
                if score < (best?.score ?? .infinity) { best = (weekday, score) }
            }
            guard let best else { break }
            picked.append(best.weekday)
        }
        return picked
            .sorted { WeeklyPlan.order($0) < WeeklyPlan.order($1) }
            .enumerated()
            .map { Slot(index: $0.offset, weekday: $0.element, kind: cardio.kind, minutes: cardio.minutes) }
    }

    /// The shortest workout that counts as the session done: the short version.
    public static let minimumDoneMinutes = EasyCardio.shortMinutes

    /// Start-of-day dates with a finished workout of `kind` in the week from
    /// `weekStart`, at least `minimumDoneMinutes` long.
    public static func doneDays(kind: EasyCardio.Kind, workouts: [Workout], weekStart: Date,
                                calendar: Calendar = .current) -> Set<Date> {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return Set(workouts
            .filter { kind.workoutNames.contains($0.name) && $0.minutes >= minimumDoneMinutes
                && $0.start >= weekStart && $0.start < weekEnd }
            .map { calendar.startOfDay(for: $0.start) })
    }

    /// Which slots are done. Fixed days: a matching workout on the slot's day.
    /// Flexible: the first N slots for N days with one.
    public static func done(slots: [Slot], doneDays: Set<Date>, weekStart: Date, calendar: Calendar = .current) -> Set<Int> {
        if slots.contains(where: { $0.weekday == nil }) {
            return Set(slots.prefix(doneDays.count).map(\.index))
        }
        var result: Set<Int> = []
        for slot in slots {
            guard let weekday = slot.weekday,
                  let day = calendar.date(byAdding: .day, value: WeeklyPlan.order(weekday), to: weekStart) else { continue }
            if doneDays.contains(calendar.startOfDay(for: day)) { result.insert(slot.index) }
        }
        return result
    }

    /// Today's cardio, for Up next.
    public struct Today: Sendable, Equatable {
        public var kind: EasyCardio.Kind
        public var minutes: Int
        /// "Easy ride · 30 min".
        public var title: String
        public var detail: String
    }

    /// Today's cardio row, or nil when there's none today, it's done, or (in a
    /// flexible week) today already had a heavy lower session and the goal
    /// includes strength. A low-recovery day, or a strain range that 30
    /// minutes would pass, gets the 15-minute version.
    /// - Parameters:
    ///   - slots: this week's slots (`slots(for:goals:)`).
    ///   - doneSlots: slots already done (`done(slots:doneDays:weekStart:)`).
    ///   - doneToday: a matching workout was logged today.
    ///   - weekday: today's `Calendar` weekday.
    ///   - lowRecovery: recovery under 34 or the 7-day HRV below normal.
    ///   - liftedHeavyLowerToday: a legs, lower or full-body session today.
    ///   - strainRange: today's strain range (`TrainingDayPlanner.Guidance.strainRange`).
    public static func today(
        slots: [Slot],
        doneSlots: Set<Int>,
        doneToday: Bool,
        weekday: Int,
        goals: Goals?,
        lowRecovery: Bool,
        liftedHeavyLowerToday: Bool,
        strainRange: ClosedRange<Double>? = nil
    ) -> Today? {
        guard !doneToday else { return nil }
        let slot: Slot?
        if slots.contains(where: { $0.weekday == nil }) {
            let strengthGoal = goals?.focuses.contains(.strength) == true
            if strengthGoal && liftedHeavyLowerToday { return nil }
            slot = slots.first { !doneSlots.contains($0.index) }
        } else {
            slot = slots.first { $0.weekday == weekday && !doneSlots.contains($0.index) }
        }
        guard let slot else { return nil }
        let tooMuch = strainRange.map { estimatedStrain(minutes: slot.minutes) > $0.upperBound } ?? false
        if lowRecovery || tooMuch {
            let minutes = min(slot.minutes, EasyCardio.shortMinutes)
            return Today(kind: slot.kind, minutes: minutes, title: "\(slot.kind.title) · \(minutes) min",
                         detail: "Recovery is low: keep it to \(minutes) easy minutes, or skip it")
        }
        let when = slot.weekday == nil ? "Any day this week. " : ""
        return Today(kind: slot.kind, minutes: slot.minutes, title: "\(slot.kind.title) · \(slot.minutes) min",
                     detail: "\(when)Easy pace: you could hold a conversation")
    }

    /// Heart-rate reserve an easy zone 2 session is assumed to sit at
    /// (middle of 40-55%, ACSM's "moderate" band starts at 40%).
    public static let easyReserveFraction = 0.45

    /// Strain for a steady session on the app's scale (`StrainCalculator`,
    /// Banister TRIMP, men's curve; the women's curve gives a little more).
    public static func estimatedStrain(minutes: Int, reserveFraction: Double = easyReserveFraction,
                                       sex: BiologicalSex = .male) -> Double {
        let calculator = StrainCalculator()
        let load = calculator.trimp(minutes: Double(minutes), reserveFraction: reserveFraction, sex: sex)
        return calculator.strain(forLoad: load)
    }

    /// Planned cardio minutes for the week, toward the 150-300 band.
    public static func plannedMinutes(_ cardio: EasyCardio?) -> Int {
        guard let cardio else { return 0 }
        return min(EasyCardio.maximumPerWeek, cardio.sessionsPerWeek) * cardio.minutes
    }

    /// "60 planned minutes toward the 150-minute WHO floor (easy cardio counts as moderate)."
    public static func bandLine(_ cardio: EasyCardio?, goals: Goals?) -> String? {
        let minutes = plannedMinutes(cardio)
        guard minutes > 0 else { return nil }
        let target = WeeklyActivityBand.target(for: goals)
        return "\(minutes) planned minutes toward your \(target) a week (WHO 2020); easy zone 2 counts as moderate."
    }
}
