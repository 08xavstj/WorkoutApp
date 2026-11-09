import Foundation

/// A fixed-day week as a queue: the week's sessions in order, each day taking
/// the next one not done yet, so a missed or swapped session moves instead of
/// vanishing, and a session done early ticks its own place in the plan.
///
/// - **The queue, not the calendar.** The plan's sessions (Monday first) are
///   done in order. A logged session ticks the planned session with the same
///   focus (Lower ticks Lower, Legs ticks Lower too, Push or Pull tick Upper,
///   Full body ticks anything), whatever day it was planned for. Each day's
///   suggestion is the first session still to do. For equal weekly volume,
///   how the sessions fall across the week makes little difference to muscle
///   growth (Schoenfeld, Grgic & Krieger, J Sports Sci 2019, volume-equated
///   meta-analysis), so moving a session costs little and losing it costs more.
/// - **Rest days stay rest days unless the week needs them.** Planned training
///   days always train while sessions remain. A rest day takes a session only
///   when the sessions left outnumber the planned days left, and then the
///   earliest one does, so a missed session is done soon rather than piled up
///   at the end. Never two sessions a day, and never more than the plan's
///   sessions. An extra day is skipped after two training days in a row
///   unless every day left is needed. App choices, not from a study.
/// - **The same muscles not two days running.** A session isn't put the day
///   after one that loaded the same main muscles when another session can go
///   first, or the week has room to wait a day: big muscles take about
///   48-72 h to recover from a hard session (Bishop et al., J Strength Cond
///   Res 2008; Schoenfeld et al., Sports Med 2016, as in `MuscleRecovery`).
/// - **Sore muscles move a session later.** Muscle soreness after training
///   (DOMS) peaks 24-72 h after it, and while it lasts strength and range of
///   motion are lower (Cheung, Hume & Maxwell, Sports Med 2003). Training
///   through mild soreness is fine and doesn't slow recovery, but the session
///   goes less well, and soreness tracks muscle damage poorly (Nosaka et al.,
///   Scand J Med Sci Sports 2002). So soreness reported for a day (the "why a
///   different workout?" answer, or the morning check-in at 5/10 or more)
///   moves a session that loads those muscles behind one that doesn't, or a
///   day later when the week has room. The day after a report, the session
///   stays put with a note to swap if still sore: the user knows best (autonomy
///   support: Teixeira et al., Int J Behav Nutr Phys Act 2012; Ntoumanis et
///   al., Health Psychol Rev 2021). Which day a report counts for, the 5/10
///   line and the muscle groups each focus loads are app choices.
/// - **A week that runs out.** Sessions that no longer fit (fewer days left
///   than sessions) are "still to do this week", never "missed": one session
///   costs little, since strength and muscle take weeks without training to
///   fall off (Mujika & Padilla, Sports Med 2000). The next week doesn't owe
///   it (no doubling up), but it goes first: the week's order is rotated to
///   start at the first session left over (`leftOver`, `carriedOver`), so
///   the rotation carries on and the muscles that have rested longest train
///   next, the same rule a new plan starts from (`WorkoutPlanner.suggestedFocus`).
///   Keeping each muscle at about twice a week matters more than which day
///   it falls on (Schoenfeld, Ogborn & Krieger, Sports Med 2016; Schoenfeld,
///   Grgic & Krieger 2019). Rotating instead of skipping is an app choice.
///
/// Flexible weeks (`WeeklyPlan.Mode.flexible`) have no order or days and keep
/// their own rule (`TrainingDayPlanner.flexibleGuidance`); `make` returns nil
/// for them.
public enum AdaptiveWeek {
    public typealias Area = MorningCheckIn.BodyArea

    // MARK: Inputs

    /// One logged session (or watch training day) this week.
    public struct DoneSession: Sendable, Equatable {
        public var date: Date
        /// What it trained, from its name or exercises (`inferFocus`); nil when unknown.
        public var focus: WorkoutFocus?
        /// A gym session. False for a watch-only training day (a run, a ride),
        /// which counts for the week's total but doesn't tick a lifting session.
        public var isLifting: Bool

        public init(date: Date, focus: WorkoutFocus?, isLifting: Bool = true) {
            self.date = date
            self.focus = focus
            self.isLifting = isLifting
        }
    }

    /// A muscle group reported (or estimated) sore on a day.
    public struct SoreSignal: Sendable, Equatable {
        public enum Source: String, Sendable {
            /// Picked in the "why a different workout?" prompt.
            case reported
            /// The morning check-in (soreness at `checkInThreshold` or more).
            case checkIn
            /// The muscle-recovery model (`MuscleRecovery`), today only.
            case estimated
        }

        public var area: Area
        /// The day it counts for (any time that day).
        public var day: Date
        public var source: Source

        public init(area: Area, day: Date, source: Source) {
            self.area = area
            self.day = day
            self.source = source
        }
    }

    /// Why the user did a different session than the one suggested.
    public enum Reason: String, Codable, Sendable, CaseIterable, Identifiable {
        case sore, tired, shortOnTime, equipment, pain, prefer

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .sore: "Sore muscles"
            case .tired: "Low energy / tired"
            case .shortOnTime: "Short on time"
            case .equipment: "Equipment busy / not available"
            case .pain: "Pain or niggle"
            case .prefer: "Just prefer it today"
            }
        }

        /// For "Swapped: tired".
        public var shortText: String {
            switch self {
            case .sore: "sore"
            case .tired: "tired"
            case .shortOnTime: "short on time"
            case .equipment: "equipment busy"
            case .pain: "pain"
            case .prefer: "preferred"
            }
        }

        public var systemImage: String {
            switch self {
            case .sore: "figure.cooldown"
            case .tired: "battery.25"
            case .shortOnTime: "clock"
            case .equipment: "dumbbell"
            case .pain: "bandage"
            case .prefer: "hand.thumbsup"
            }
        }
    }

    /// The groups the reason prompt offers for "Sore muscles".
    public static let promptAreas: [Area] = [.legs, .chest, .back, .shoulders, .arms]

    /// Morning check-in soreness (0-10) that counts as sore for the plan: the
    /// same line as `CheckInCoaching.focus(for:)`. App choice; below it,
    /// training through mild soreness is fine (Cheung et al. 2003).
    public static let checkInThreshold = 5

    /// One "why a different workout?" answer, kept with its day.
    public struct Swap: Codable, Sendable, Equatable, Identifiable {
        /// Start of the day it happened.
        public var day: Date
        /// The session that was suggested, if any.
        public var planned: WorkoutFocus?
        public var chosen: WorkoutFocus
        /// Nil when skipped.
        public var reason: Reason?
        /// For `.sore`: the groups picked.
        public var soreAreas: [Area]
        public var recordedAt: Date

        public var id: Date { day }

        public init(day: Date, planned: WorkoutFocus?, chosen: WorkoutFocus, reason: Reason?, soreAreas: [Area] = [], recordedAt: Date = .now) {
            self.day = day
            self.planned = planned
            self.chosen = chosen
            self.reason = reason
            self.soreAreas = soreAreas
            self.recordedAt = recordedAt
        }

        /// "legs sore", "tired"; nil when skipped.
        public var reasonText: String? {
            guard let reason else { return nil }
            if reason == .sore, !soreAreas.isEmpty { return AdaptiveWeek.areaText(Set(soreAreas)) + " sore" }
            return reason.shortText
        }

        /// "Upper for Lower · legs sore".
        public var label: String {
            var text = chosen.shortTitle
            if let planned { text += " for " + planned.shortTitle }
            if let why = reasonText { text += " · " + why }
            return text
        }
    }

    // MARK: Output

    /// A day in the rest of the week that takes a session.
    public struct Slot: Sendable, Equatable, Identifiable {
        /// Start of the day.
        public var date: Date
        /// The session, with its weekday and time set to this day (the planned
        /// time when the day had a session in the plan, else the session's own).
        public var session: PlannedDay
        /// The weekday the session sits on in the plan.
        public var plannedWeekday: Int
        /// The plan had a session on this weekday (false: a rest day that takes one).
        public var isPlannedDay: Bool
        /// Why it's here or what to do if sore, e.g. "Lower moved to Thu: legs still sore."
        public var note: String?
        /// Go easy: the muscles it loads are sore and the week has no room to wait.
        public var easy: Bool
        /// Offer the short version (short on time or tired, said today).
        public var short: Bool

        public var id: Date { date }
        public var focus: WorkoutFocus { session.focus }
        /// Not on its planned weekday.
        public var isMoved: Bool { plannedWeekday != session.weekday }
    }

    public struct Result: Sendable, Equatable {
        public var weekStart: Date
        /// Start of the day the result is for.
        public var day: Date
        /// The plan's sessions in order (Monday first).
        public var queue: [PlannedDay]
        /// Queue index → the day it was done.
        public var done: [Int: Date]
        /// Sessions that ticked nothing in the plan (watch-only days, extras).
        public var otherSessions: Int
        /// A gym session was logged today.
        public var liftedToday: Bool
        /// The rest of the week's sessions, from today (tomorrow once today is done).
        public var slots: [Slot]
        /// Sessions that no longer fit this week.
        public var stillToDo: [PlannedDay]
        /// The first session moved for soreness: "Lower moved to Thu: legs still sore."
        public var moveNote: String?
        /// Whether yesterday took a session in the queue as it stood then; nil
        /// when yesterday was in another week.
        public var yesterdayWasSlot: Bool?

        /// Today's session, if today takes one.
        public var today: Slot? { slots.first { $0.date == day } }
        /// The next session to do (today's, or the next day's).
        public var next: Slot? { slots.first }
        /// Planned weekdays whose session is done (for the week's dots).
        public var doneWeekdays: Set<Int> { Set(done.keys.compactMap { queue.indices.contains($0) ? queue[$0].weekday : nil }) }
        public var remaining: Int { max(0, queue.count - done.count) }

        public func slot(on date: Date, calendar: Calendar = .current) -> Slot? {
            slots.first { calendar.isDate($0.date, inSameDayAs: date) }
        }

        /// "Next: Lower · 60 min".
        public var nextLabel: String? {
            next.map { "Next: \($0.focus.shortTitle) · \($0.session.minutes) min" }
        }

        /// Shown when sessions don't fit: a choice, never a debt.
        public var stillToDoNote: String? {
            guard !stillToDo.isEmpty else { return nil }
            let names = AdaptiveWeek.list(stillToDo.map(\.focus.shortTitle))
            return "\(names) didn't fit this week. Fit it in if a day suits, or let it go: one session makes little difference, and next week starts fresh."
        }
    }

    // MARK: Building the week

    /// The rest of the week for a fixed-day plan, as of `now`. Nil for a
    /// flexible plan or one without sessions.
    /// - Parameters:
    ///   - done: logged sessions and watch training days (any range; this week's are used).
    ///   - soreness: sore signals by day (`signals(from:)`, `signals(fromSwaps:)`, `fatiguedAreas`).
    ///   - swaps: this week's "why a different workout?" answers.
    ///   - carriedOver: the first session last week left undone (`leftOver`); the week starts with it.
    public static func make(plan: WeeklyPlan, done: [DoneSession], now: Date, soreness: [SoreSignal] = [],
                            swaps: [Swap] = [], carriedOver: WorkoutFocus? = nil, calendar: Calendar = .current) -> Result? {
        guard !plan.isFlexible, !plan.plannedDays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        var result = simulate(plan: plan, done: done, today: today, soreness: soreness, swaps: swaps,
                              carriedOver: carriedOver, calendar: calendar)
        let weekStart = calendar.startOfDay(for: plan.weekStart)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), yesterday >= weekStart {
            let then = simulate(plan: plan, done: done.filter { $0.date < yesterday }, today: yesterday,
                                soreness: soreness.filter { $0.day < today }, swaps: swaps.filter { $0.day < today },
                                carriedOver: carriedOver, calendar: calendar)
            result.yesterdayWasSlot = then.today != nil
        }
        return result
    }

    // MARK: Carrying over

    /// The plan's sessions its week didn't tick, in plan order: what the next
    /// week starts with (`carriedOver`, `rotated`). Works for flexible plans
    /// too, where the sessions are the ones still to do.
    /// - Parameter done: logged sessions (any range; that week's are used).
    public static func leftOver(plan: WeeklyPlan, done: [DoneSession], calendar: Calendar = .current) -> [PlannedDay] {
        guard !plan.plannedDays.isEmpty else { return [] }
        let weekStart = calendar.startOfDay(for: plan.weekStart)
        let lastDay = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        var counted = plan
        counted.mode = .fixedDays
        let week = simulate(plan: counted, done: done, today: lastDay, soreness: [], swaps: [], carriedOver: nil, calendar: calendar)
        var left = week.queue.indices.filter { week.done[$0] == nil }
        if plan.isFlexible, let target = plan.sessionsPerWeek {
            // A quota under the number of sessions: only what the quota still asks for.
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let lifted = done.filter { $0.isLifting && $0.date >= weekStart && $0.date < weekEnd }.count
            let owed = max(0, target - lifted)
            left = Array(left.prefix(owed))
        }
        return left.map { week.queue[$0] }
    }

    /// The queue's order with the first session matching `first` leading and
    /// the rest following in turn (Upper, Lower, Upper, Lower with Lower
    /// first: Lower, Upper, Lower, Upper). Plan order when nothing matches.
    static func rotation(_ queue: [PlannedDay], startingWith first: WorkoutFocus?) -> [Int] {
        let indices = Array(queue.indices)
        guard let first,
              let start = queue.firstIndex(where: { $0.focus == first })
                ?? queue.firstIndex(where: { isSameSession($0.focus, first) }) else { return indices }
        return Array(indices[start...] + indices[..<start])
    }

    /// A new week's days from a template, with the sessions moved round so
    /// `first` (last week's left-over, `leftOver`) is on the first day. Each
    /// day keeps its weekday, time and length; only what it trains moves.
    /// Unchanged when `first` is nil, already first, or not in the plan.
    public static func rotated(_ days: [PlannedDay], startingWith first: WorkoutFocus?) -> [PlannedDay] {
        let sorted = days.sorted { WeeklyPlan.order($0.weekday) < WeeklyPlan.order($1.weekday) }
        let order = rotation(sorted, startingWith: first)
        return sorted.indices.map { index in
            var day = sorted[index]
            day.focus = sorted[order[index]].focus
            return day
        }
    }

    private static func simulate(plan: WeeklyPlan, done: [DoneSession], today: Date, soreness: [SoreSignal],
                                 swaps: [Swap], carriedOver: WorkoutFocus?, calendar: Calendar) -> Result {
        let queue = plan.sortedDays
        // Last week's left-over goes first; the rest follow in turn.
        let order = rotation(queue, startingWith: carriedOver)
        let weekStart = calendar.startOfDay(for: plan.weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        func dayOf(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        func shift(_ date: Date, _ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }

        // 1. Tick the plan's sessions from what was logged.
        let thisWeek = done
            .filter { $0.date >= weekStart && $0.date < min(weekEnd, endOfToday) }
            .sorted { $0.date < $1.date }
        var doneIndices: [Int: Date] = [:]
        var other = 0
        var trainedDays: Set<Date> = []
        var areasByDay: [Date: Set<Area>] = [:]
        for session in thisWeek {
            let day = dayOf(session.date)
            trainedDays.insert(day)
            if let focus = session.focus { areasByDay[day, default: []].formUnion(loads(focus)) }
            let open = order.filter { doneIndices[$0] == nil }
            var pick: Int?
            if let focus = session.focus {
                pick = open
                    .compactMap { index in matchRank(planned: queue[index].focus, done: focus).map { (index, $0) } }
                    .min { $0.1 < $1.1 }?.0
            } else if session.isLifting {
                // A gym session of unknown focus: the day's planned session, else the next one.
                let weekday = calendar.component(.weekday, from: day)
                pick = open.first { queue[$0].weekday == weekday } ?? open.first
            }
            if let pick { doneIndices[pick] = day } else { other += 1 }
        }
        let liftedToday = thisWeek.contains { $0.isLifting && dayOf($0.date) == today }

        // 2. Place what's left on the days left.
        var pending = order.filter { doneIndices[$0] == nil }
        let start = liftedToday ? shift(today, 1) : today
        var forced: [Date: WorkoutFocus] = [:]
        for swap in swaps where swap.reason == .equipment {
            // Equipment busy: the planned session goes first the next day.
            if let planned = swap.planned { forced[shift(dayOf(swap.day), 1)] = planned }
        }
        var slots: [Slot] = []
        var moveNote: String?
        var pendingMove: (index: Int, areas: Set<Area>, slotDay: Date)?
        var day = start
        while day < weekEnd, !pending.isEmpty {
            let weekday = calendar.component(.weekday, from: day)
            var daysLeft = 0
            var plannedLeft = 0
            var cursor = day
            while cursor < weekEnd {
                daysLeft += 1
                if plan.day(for: calendar.component(.weekday, from: cursor)) != nil { plannedLeft += 1 }
                cursor = shift(cursor, 1)
            }
            let plannedHere = plan.day(for: weekday)
            if let focus = forced[day], let position = pending.firstIndex(where: { queue[$0].focus == focus }), position > 0 {
                pending.insert(pending.remove(at: position), at: 0)
            }
            let isForced = forced[day] != nil
            let tight = pending.count >= daysLeft
            var train = plannedHere != nil || pending.count > plannedLeft || isForced
            let twoInARow = trainedDays.contains(shift(day, -1)) && trainedDays.contains(shift(day, -2))
            if train, plannedHere == nil, !isForced, twoInARow, !tight { train = false }

            var note: String?
            var easy = false
            var position = 0
            if train {
                let sore = Set(soreness.filter { dayOf($0.day) == day }.map(\.area))
                let yesterday = (areasByDay[shift(day, -1)] ?? []).intersection(majorAreas)
                func soreClash(_ index: Int) -> Set<Area> { loads(queue[index].focus).intersection(sore) }
                // Back to back with yesterday's muscles only reorders, or rests an
                // extra day; a planned day still trains unless the muscles are sore.
                func clash(_ index: Int) -> Bool {
                    let backToBack = !loads(queue[index].focus).intersection(majorAreas).intersection(yesterday).isEmpty
                    return !soreClash(index).isEmpty || backToBack
                }
                let head = pending[0]
                if clash(head) {
                    let headSore = soreClash(head)
                    if let alternative = pending.indices.dropFirst().first(where: { !clash(pending[$0]) }) {
                        position = alternative
                        if !headSore.isEmpty, pendingMove == nil { pendingMove = (head, headSore, day) }
                    } else if !tight && (!headSore.isEmpty || plannedHere == nil) {
                        train = false
                        if !headSore.isEmpty, pendingMove == nil { pendingMove = (head, headSore, day) }
                    } else if !headSore.isEmpty {
                        easy = true
                        note = capitalized(areaText(headSore)) + " still sore and the week has no room to wait: go lighter today, it still counts."
                    }
                }
            }
            if train {
                let index = pending.remove(at: position)
                let item = queue[index]
                // Reported sore yesterday: keep the session, with a way out.
                let lastReport = Set(soreness.filter { $0.source != .estimated && dayOf($0.day) == shift(day, -1) }.map(\.area))
                let soft = loads(item.focus).intersection(lastReport)
                if note == nil, !soft.isEmpty {
                    let names = capitalized(areaText(soft))
                    if let swap = pending.first(where: { loads(queue[$0].focus).intersection(soft).isEmpty }) {
                        note = "\(names) still sore? Do \(queue[swap].focus.shortTitle) first and \(item.focus.shortTitle) the day after."
                    } else {
                        note = "\(names) still sore? Go lighter, or move it a day if the week has room."
                    }
                }
                let todaysSwap = swaps.first { dayOf($0.day) == day }
                let tired = todaysSwap?.reason == .tired
                var session = item
                session.weekday = weekday
                session.time = plannedHere?.time ?? item.time
                slots.append(Slot(date: day, session: session, plannedWeekday: item.weekday, isPlannedDay: plannedHere != nil,
                                  note: note, easy: easy || tired, short: tired || todaysSwap?.reason == .shortOnTime))
                trainedDays.insert(day)
                areasByDay[day] = loads(item.focus)
            }
            day = shift(day, 1)
        }

        // 3. Say why last week's left-over leads, on its day.
        if let lead = order.first, lead != 0, let index = slots.firstIndex(where: { $0.plannedWeekday == queue[lead].weekday }),
           slots[index].note == nil {
            slots[index].note = "\(queue[lead].focus.shortTitle) first: it didn't fit last week."
        }

        // 4. Say where a session moved for soreness went.
        if let move = pendingMove {
            let focus = queue[move.index].focus.shortTitle
            let sore = areaText(move.areas)
            if let placed = slots.first(where: { $0.plannedWeekday == queue[move.index].weekday && $0.date > move.slotDay }) {
                let name = WeeklyPlan.weekdayName(placed.session.weekday, calendar: calendar)
                moveNote = "\(focus) moved to \(name): \(sore) still sore."
            } else {
                moveNote = "\(focus) is still to do: \(sore) still sore."
            }
            if let index = slots.firstIndex(where: { $0.date == move.slotDay }), slots[index].note == nil {
                slots[index].note = moveNote
            }
        }

        return Result(weekStart: weekStart, day: today, queue: queue, done: doneIndices, otherSessions: other,
                      liftedToday: liftedToday, slots: slots, stillToDo: pending.map { queue[$0] },
                      moveNote: moveNote, yesterdayWasSlot: nil)
    }

    // MARK: Matching

    /// How well a done session stands in for a planned one: 0 same focus,
    /// 1 Legs for Lower (or back), 2 Push or Pull for Upper (or back), 3 Full
    /// body for anything; nil when it doesn't (Upper for Lower).
    public static func matchRank(planned: WorkoutFocus, done: WorkoutFocus) -> Int? {
        if planned == done { return 0 }
        let legs: Set<WorkoutFocus> = [.legs, .lower]
        if legs.contains(planned), legs.contains(done) { return 1 }
        let halves: Set<WorkoutFocus> = [.push, .pull]
        if (planned == .upper && halves.contains(done)) || (done == .upper && halves.contains(planned)) { return 2 }
        if planned == .fullBody || done == .fullBody { return 3 }
        return nil
    }

    /// The same session for the "why a different workout?" prompt: same
    /// focus, or Legs and Lower.
    public static func isSameSession(_ a: WorkoutFocus, _ b: WorkoutFocus) -> Bool {
        (matchRank(planned: a, done: b) ?? 9) <= 1
    }

    /// A session's focus from its name ("Upper A", "Leg Day") or, failing
    /// that, from its exercises' movement groups. Nil when neither says.
    public static func inferFocus(name: String, exerciseIDs: [String]) -> WorkoutFocus? {
        let lower = name.lowercased()
        let words = Set(lower.split { !$0.isLetter }.map(String.init))
        if words.contains("full") || words.contains("fullbody") { return .fullBody }
        if words.contains("upper") { return .upper }
        if words.contains("lower") { return .lower }
        if words.contains("push") { return .push }
        if words.contains("pull") { return .pull }
        if words.contains("leg") || words.contains("legs") { return .legs }
        let groups = Set(exerciseIDs.compactMap { ExerciseCatalog.slot(for: $0)?.muscleGroup }).subtracting([.core])
        let push = groups.contains(.push), pull = groups.contains(.pull), legs = groups.contains(.legs)
        switch (push, pull, legs) {
        case (_, _, true) where push || pull: return .fullBody
        case (false, false, true): return .lower
        case (true, true, false): return .upper
        case (true, false, false): return .push
        case (false, true, false): return .pull
        default: return nil
        }
    }

    // MARK: Muscles

    /// The groups whose soreness moves a session and that shouldn't train two
    /// days running. Arms are left out: they help in both pushing and pulling,
    /// so Push then Pull is a normal week.
    public static let majorAreas: Set<Area> = [.legs, .glutes, .chest, .back, .shoulders]

    /// The main groups a session loads (app choice from each focus's lifts, `WorkoutFocus.slots`).
    public static func loads(_ focus: WorkoutFocus) -> Set<Area> {
        switch focus {
        case .push: [.chest, .shoulders, .arms]
        case .pull: [.back, .arms]
        case .legs, .lower: [.legs, .glutes]
        case .upper: [.chest, .back, .shoulders, .arms]
        case .fullBody: [.legs, .glutes, .chest, .back, .shoulders]
        }
    }

    /// Sore groups from a morning check-in at `checkInThreshold` or more, for its day.
    public static func signals(from checkIn: MorningCheckIn?) -> [SoreSignal] {
        guard let checkIn, (checkIn.soreness ?? 0) >= checkInThreshold else { return [] }
        return checkIn.soreAreas.filter { $0 != .core }.map { SoreSignal(area: $0, day: checkIn.day, source: .checkIn) }
    }

    /// Sore groups picked in the reason prompt, each for its day.
    public static func signals(fromSwaps swaps: [Swap]) -> [SoreSignal] {
        swaps.filter { $0.reason == .sore }.flatMap { swap in
            swap.soreAreas.map { SoreSignal(area: $0, day: swap.day, source: .reported) }
        }
    }

    /// Groups the muscle-recovery model has under 50% recovered (its
    /// "fatigued" status), as signals for `day`. A model estimate, not a
    /// measurement, so callers pass it for today only.
    public static func fatiguedAreas(_ states: [Muscle: MuscleRecovery.State], day: Date) -> [SoreSignal] {
        let groups: [(Area, [Muscle])] = [
            (.legs, [.quadriceps, .hamstrings]), (.glutes, [.glutes]), (.chest, [.chest]),
            (.back, [.lats, .middleBack]), (.shoulders, [.shoulders]),
        ]
        return groups.compactMap { area, muscles in
            let values = muscles.compactMap { states[$0]?.recovery }
            guard !values.isEmpty, values.reduce(0, +) / Double(values.count) < 50 else { return nil }
            return SoreSignal(area: area, day: day, source: .estimated)
        }
    }

    // MARK: Words

    /// "legs", "legs and back".
    public static func areaText(_ areas: Set<Area>) -> String {
        let ordered = Area.allCases.filter { areas.contains($0) }.map { $0.rawValue.lowercased() }
        return list(ordered)
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
