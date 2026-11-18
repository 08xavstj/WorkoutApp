import Foundation

/// What the Plan widget (iPhone Lock Screen, Home Screen, StandBy) and the
/// Watch's "Today's plan" complication say at a given moment, and when the
/// data behind a glance is too old to show.
///
/// Why a plan widget: there is no health evidence for widgets. The case is
/// usability (docs/research/healthy-living-2026-11.md §3 item 5):
/// - Over 70% of activity-tracker sessions were glances of about five
///   seconds with no further interaction (Gouveia R, Pereira F, Caraban A,
///   Munson SA, Karapanos E. You have 5 seconds: designing glanceable
///   feedback for physical activity trackers. UbiComp/ISWC 2015 Adjunct).
///   Verified from the abstract.
/// - In a 4-week study, reminders helped people repeat a behaviour but got in
///   the way of it becoming automatic; cues tied to events went with more
///   automaticity (Stawarz K, Cox AL, Blandford A. Beyond self-tracking and
///   reminders: designing smartphone apps that support habit formation. CHI
///   2015: 2653-2662, doi:10.1145/2702123.2702230). Verified from the
///   abstract. A widget is a cue the user looks at, not an event cue, so this
///   only supports "a glance instead of another reminder"; small studies.
///
/// Why "--": a widget that disagrees with the app is a top complaint about
/// competing apps (docs/research/competitors-2026-11.md, lesson 4). So every
/// rule here prefers blank over stale. The windows below are the app's
/// choices, not research.
///
/// This file has no dependencies on the rest of AppCore, so the Watch widget
/// extension compiles it on its own (project.yml).
nonisolated public enum PlanGlance {
    // MARK: Rules (app's choices)

    /// A session shows its clock time until this long after its start; after
    /// that it reads "today" (still to do, without a time that has passed).
    public static let sessionWindow: TimeInterval = 2 * 3600
    /// On a day with nothing left to train, the bed-by window takes over this
    /// long before it starts. After training it shows straight away.
    public static let bedByLead: TimeInterval = 2 * 3600
    /// The bed-by window stays up this long after it ends.
    public static let bedByGrace: TimeInterval = 3600
    /// The plan is trusted on the day the phone wrote it and this many days
    /// after. Later than that the widget shows "--".
    public static let carryDays = 1
    /// Smart Stack: the plan is offered this long before a planned session
    /// (the same hour the complications have used since they shipped).
    public static let sessionRelevanceLead: TimeInterval = 3600
    /// Smart Stack: and this long before tonight's bed-by window (the lead of
    /// the coach's evening note, `CoachCheckIns.eveningMinutesBeforeBed`).
    public static let bedRelevanceLead: TimeInterval = 3600
    /// Smart Stack intervals handed to the system at once.
    public static let maximumRelevantIntervals = 10
    /// Timeline entries are laid out this far ahead (the provider asks again
    /// after midnight, and the app reloads on every change).
    public static let timelineHorizon: TimeInterval = 48 * 3600

    // MARK: Data

    /// One planned session on a date.
    nonisolated public struct Slot: Codable, Sendable, Equatable {
        public var start: Date
        /// e.g. "Push Day".
        public var title: String
        /// e.g. "Push".
        public var shortTitle: String
        /// SF Symbol for the focus.
        public var symbol: String?
        /// Planned length.
        public var minutes: Int?

        public init(start: Date, title: String, shortTitle: String, symbol: String? = nil, minutes: Int? = nil) {
            self.start = start
            self.title = title
            self.shortTitle = shortTitle
            self.symbol = symbol
            self.minutes = minutes
        }
    }

    /// What the phone knew about the week after the one it wrote the plan in.
    nonisolated public enum NextWeek: String, Codable, Sendable {
        /// No plan saved for it: those days read "No plan yet".
        case unplanned
        /// Fixed days, and its sessions are in `Plan.slots`.
        case planned
        /// A flexible week: its sessions float, so they aren't known until
        /// the app has looked again ("--").
        case open
    }

    /// The plan as the phone last wrote it.
    nonisolated public struct Plan: Codable, Sendable, Equatable {
        /// When the phone wrote it.
        public var updated: Date
        /// The week it was written in has a plan with sessions.
        public var hasPlan: Bool
        /// Planned sessions from the start of the day it was written, about a
        /// week ahead. A session done that day may be missing.
        public var slots: [Slot]
        /// End of the week it was written in (the next Monday 00:00).
        public var weekEnd: Date
        public var nextWeek: NextWeek
        /// The latest lifting session's end (or the start of a day with a
        /// lift recorded elsewhere): sessions planned that day are done.
        public var doneAt: Date?
        /// The app called the day it was written a rest day (rest mode, or
        /// the day's guidance), whatever the plan had on it.
        public var restToday: Bool
        /// Tonight's bed-by window (`BedtimeWindow`).
        public var bedByStart: Date?
        public var bedByEnd: Date?
        /// Sessions done and planned in the week it was written in.
        public var weekDone: Int?
        public var weekPlanned: Int?
        /// Rest mode is on until then (Settings): sessions before it are rest days.
        public var restUntil: Date?

        public init(updated: Date, hasPlan: Bool, slots: [Slot], weekEnd: Date, nextWeek: NextWeek = .unplanned,
                    doneAt: Date? = nil, restToday: Bool = false, bedByStart: Date? = nil, bedByEnd: Date? = nil,
                    weekDone: Int? = nil, weekPlanned: Int? = nil, restUntil: Date? = nil) {
            self.updated = updated
            self.hasPlan = hasPlan
            self.slots = slots
            self.weekEnd = weekEnd
            self.nextWeek = nextWeek
            self.doneAt = doneAt
            self.restToday = restToday
            self.bedByStart = bedByStart
            self.bedByEnd = bedByEnd
            self.weekDone = weekDone
            self.weekPlanned = weekPlanned
            self.restUntil = restUntil
        }

        /// Sample data for the widget gallery and placeholders: a session
        /// this evening and one in two days, two of four done.
        public static func sample(now: Date = Date(), calendar: Calendar = .current) -> Plan {
            let today = calendar.startOfDay(for: now)
            let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) ?? now
            let start = evening > now ? evening : now.addingTimeInterval(3600)
            let later = calendar.date(byAdding: .day, value: 2, to: start) ?? start
            let bed = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today) ?? now
            return Plan(
                updated: now, hasPlan: true,
                slots: [
                    Slot(start: start, title: "Push Day", shortTitle: "Push", symbol: "dumbbell.fill", minutes: 60),
                    Slot(start: later, title: "Pull Day", shortTitle: "Pull", symbol: "dumbbell.fill", minutes: 60),
                ],
                weekEnd: calendar.date(byAdding: .day, value: 7, to: today) ?? now.addingTimeInterval(7 * 86_400),
                nextWeek: .unplanned, doneAt: nil, restToday: false,
                bedByStart: bed, bedByEnd: bed.addingTimeInterval(30 * 60), weekDone: 2, weekPlanned: 4
            )
        }
    }

    /// What the glance shows.
    nonisolated public enum State: Sendable, Equatable {
        /// Today's session, still to do. `timed` is false once its clock time
        /// is more than `sessionWindow` past.
        case session(Slot, timed: Bool)
        /// Tonight's bed-by window, with the session after it if there is one.
        case bedBy(start: Date, end: Date, next: Slot?)
        /// Nothing to train today.
        case rest(next: Slot?)
        /// Trained today, no bed-by window known: the next session.
        case next(Slot)
        /// Trained today and nothing further is planned.
        case done
        /// No plan for this week.
        case noPlan
        /// Nothing from the phone yet, or too old to trust: "--".
        case stale
    }

    /// Why the Smart Stack should offer the plan during `interval`.
    nonisolated public struct Window: Sendable, Equatable {
        nonisolated public enum Reason: Sendable, Equatable {
            /// The hour before a planned session.
            case session
            /// From an hour before tonight's bed-by window to its end.
            case bedtime
        }

        public var interval: DateInterval
        public var reason: Reason

        public init(interval: DateInterval, reason: Reason) {
            self.interval = interval
            self.reason = reason
        }
    }

    /// Sessions done against planned this week.
    nonisolated public struct Week: Sendable, Equatable {
        public var done: Int
        public var planned: Int

        public init(done: Int, planned: Int) {
            self.done = done
            self.planned = planned
        }
    }

    // MARK: What to show

    /// Whole days from the day the plan was written to `now`, or nil when
    /// that is outside `0...carryDays` (too old, or the clock went back).
    static func age(of plan: Plan, at now: Date, calendar: Calendar) -> Int? {
        let written = calendar.startOfDay(for: plan.updated)
        let today = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: written, to: today).day,
              (0...carryDays).contains(days) else { return nil }
        return days
    }

    /// What the glance shows at `now`.
    ///
    /// Rules, in order:
    /// 1. No data, or written before yesterday: "--".
    /// 2. Written yesterday and a session planned then was left open: "--".
    ///    The week's queue may have moved it to today, and only the app knows.
    /// 3. No plan this week (or the new week has none): "No plan yet". A new
    ///    flexible week isn't known until the app has looked: "--".
    /// 4. Today's session, until it's done. In the evening the bed-by window
    ///    replaces a session whose time has passed.
    /// 5. After training: tonight's bed-by window, else the next session.
    /// 6. Otherwise a rest day, and from `bedByLead` before it the bed-by window.
    ///
    /// - Parameter alsoDoneAt: a workout end the plan may not know about yet
    ///   (one that just ended on the Watch).
    public static func state(of plan: Plan?, at now: Date, alsoDoneAt: Date? = nil, calendar: Calendar = .current) -> State {
        guard let plan, let age = age(of: plan, at: now, calendar: calendar) else { return .stale }
        let today = calendar.startOfDay(for: now)
        let done = doneDays(plan, alsoDoneAt: alsoDoneAt, calendar: calendar)
        func isDone(_ slot: Slot) -> Bool { done.contains(calendar.startOfDay(for: slot.start)) }
        func isRested(_ slot: Slot) -> Bool { Self.isRested(slot, plan: plan, age: age, calendar: calendar) }
        let sorted = plan.slots.sorted { $0.start < $1.start }
        // A session before today that wasn't done (and wasn't a rest day): the
        // week's queue may have moved it to today, and only the app knows.
        if sorted.contains(where: { $0.start < today && !isDone($0) && !isRested($0) }) { return .stale }

        if now >= plan.weekEnd {
            switch plan.nextWeek {
            case .unplanned: return .noPlan
            case .open: return .stale
            case .planned: break
            }
        } else if !plan.hasPlan {
            return .noPlan
        }

        let trainedToday = done.contains(today)
        let open = sorted.filter { !isRested($0) }
        let current = open.first { calendar.isDate($0.start, inSameDayAs: now) && !isDone($0) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let next = open.first { $0.start >= tomorrow }

        var bed: (start: Date, end: Date)?
        if let start = plan.bedByStart, let end = plan.bedByEnd, end > start,
           now < end.addingTimeInterval(bedByGrace), start.timeIntervalSince(now) < 86_400 {
            bed = (start, end)
        }
        let bedActive = bed.map { trainedToday || now >= $0.start.addingTimeInterval(-bedByLead) } ?? false

        if let current {
            let windowOpen = now < current.start.addingTimeInterval(sessionWindow)
            // After midnight, today's session comes after the sleep the window is for.
            let afterSleep = bed.map { current.start >= $0.end } ?? false
            if !(bedActive && (afterSleep || !windowOpen)) {
                return .session(current, timed: windowOpen)
            }
        }
        if bedActive, let bed {
            let following = open.first { $0.start >= bed.end && !isDone($0) }
            return .bedBy(start: bed.start, end: bed.end, next: following)
        }
        if trainedToday {
            if let next { return .next(next) }
            return .done
        }
        return .rest(next: next)
    }

    /// Days with a lift: the plan's latest one and one the Watch recorded
    /// since. A session planned on such a day counts as done.
    static func doneDays(_ plan: Plan, alsoDoneAt: Date?, calendar: Calendar) -> Set<Date> {
        Set([plan.doneAt, alsoDoneAt].compactMap { $0.map { calendar.startOfDay(for: $0) } })
    }

    /// A session the app wouldn't ask for: the day the plan was written was
    /// called a rest day (while that is still today), or rest mode covers
    /// the session's start.
    static func isRested(_ slot: Slot, plan: Plan, age: Int, calendar: Calendar) -> Bool {
        if let restUntil = plan.restUntil, slot.start < restUntil { return true }
        return age == 0 && plan.restToday && calendar.isDate(slot.start, inSameDayAs: plan.updated)
    }

    /// This week's sessions done against planned, or nil when it isn't known
    /// for `now`: the plan is stale, a new week has begun, or a workout has
    /// ended that the count doesn't include yet.
    public static func week(of plan: Plan?, at now: Date, alsoDoneAt: Date? = nil, calendar: Calendar = .current) -> Week? {
        guard let plan, plan.hasPlan, now < plan.weekEnd,
              let done = plan.weekDone, let planned = plan.weekPlanned, planned > 0 else { return nil }
        if let alsoDoneAt, alsoDoneAt > plan.updated { return nil }
        if case .stale = state(of: plan, at: now, alsoDoneAt: alsoDoneAt, calendar: calendar) { return nil }
        return Week(done: min(max(done, 0), planned), planned: planned)
    }

    /// Moments after `now` when the glance changes on its own, for timeline
    /// entries: each midnight, the end of each session's window, the bed-by
    /// window's lead and the end of its grace.
    public static func changeDates(of plan: Plan?, after now: Date, horizon: TimeInterval = timelineHorizon,
                                   calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var day = calendar.startOfDay(for: now)
        for _ in 0..<3 {
            guard let midnight = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            dates.append(midnight)
            day = midnight
        }
        if let plan {
            for slot in plan.slots {
                dates.append(slot.start.addingTimeInterval(sessionWindow))
            }
            if let start = plan.bedByStart, let end = plan.bedByEnd {
                dates.append(start.addingTimeInterval(-bedByLead))
                dates.append(end.addingTimeInterval(bedByGrace))
            }
            if let restUntil = plan.restUntil { dates.append(restUntil) }
        }
        let limit = now.addingTimeInterval(horizon)
        return Array(Set(dates.filter { $0 > now && $0 <= limit })).sorted()
    }

    /// When the Smart Stack should offer the plan: the hour before each
    /// session still to do, and from an hour before tonight's bed-by window to
    /// its end when the glance then shows that window. Only while the plan can
    /// be trusted (`carryDays`), and nothing while it reads "--".
    public static func relevantWindows(of plan: Plan?, after now: Date, alsoDoneAt: Date? = nil,
                                       calendar: Calendar = .current) -> [Window] {
        guard let plan, let age = age(of: plan, at: now, calendar: calendar) else { return [] }
        if case .stale = state(of: plan, at: now, alsoDoneAt: alsoDoneAt, calendar: calendar) { return [] }
        let written = calendar.startOfDay(for: plan.updated)
        let trustedUntil = calendar.date(byAdding: .day, value: carryDays + 1, to: written) ?? written.addingTimeInterval(2 * 86_400)
        let done = doneDays(plan, alsoDoneAt: alsoDoneAt, calendar: calendar)
        var windows: [Window] = []
        for slot in plan.slots where slot.start > now && slot.start < trustedUntil {
            if done.contains(calendar.startOfDay(for: slot.start)) { continue }
            if isRested(slot, plan: plan, age: age, calendar: calendar) { continue }
            // Past the week's end only when the next week's sessions are known.
            if slot.start >= plan.weekEnd, plan.nextWeek != .planned { continue }
            windows.append(Window(interval: DateInterval(start: slot.start.addingTimeInterval(-sessionRelevanceLead), end: slot.start),
                                  reason: .session))
        }
        if let start = plan.bedByStart, let end = plan.bedByEnd, end > start, end > now, start < trustedUntil {
            let windowStart = start.addingTimeInterval(-bedRelevanceLead)
            // Only when the glance itself reads "In bed by" then (as the window opens, or by bedtime),
            // never over "No plan yet".
            let showsBedBy = [max(now, windowStart), max(now, start)].contains { moment in
                if case .bedBy = state(of: plan, at: moment, alsoDoneAt: alsoDoneAt, calendar: calendar) { return true }
                return false
            }
            if showsBedBy {
                windows.append(Window(interval: DateInterval(start: windowStart, end: end), reason: .bedtime))
            }
        }
        return Array(windows.sorted { $0.interval.start < $1.interval.start }.prefix(maximumRelevantIntervals))
    }

    // MARK: Wording

    /// The words for one state, for every size of widget.
    nonisolated public struct Lines: Sendable, Equatable {
        /// SF Symbol.
        public var symbol: String
        /// Small label above the title: "Today", "In bed by", "Next session".
        public var eyebrow: String
        /// The one thing to read: "Push Day", "22:00–22:30", "Rest day", "--".
        public var title: String
        /// A second line: "6:00 PM · 60 min", "Next: Tue Pull".
        public var detail: String?
        /// Under the symbol in a circular slot: "6 PM", "Rest", "Tue", "--".
        public var short: String
        /// A few words for a watch face corner: "Push 6 PM", "Bed by 10 PM", "Tue Pull".
        public var brief: String
        /// One line: "Push · 6:00 PM".
        public var inline: String
        /// The sentence VoiceOver reads.
        public var spoken: String
    }

    /// The words for `state`.
    /// - Parameter onWatch: the Watch can't refresh the plan itself, so its
    ///   "--" points at the iPhone.
    public static func lines(for state: State, at now: Date, onWatch: Bool = false, calendar: Calendar = .current) -> Lines {
        switch state {
        case .session(let slot, let timed):
            let length = slot.minutes.map { "\($0) min" }
            let spokenLength = slot.minutes.map { ", \($0) minutes" } ?? ""
            if timed {
                return Lines(
                    symbol: slot.symbol ?? "dumbbell.fill", eyebrow: "Today", title: slot.title,
                    detail: [clock(slot.start), length].compactMap { $0 }.joined(separator: " · "),
                    short: compactTime(slot.start, calendar: calendar),
                    brief: "\(slot.shortTitle) \(compactTime(slot.start, calendar: calendar))",
                    inline: "\(slot.shortTitle) · \(clock(slot.start))",
                    spoken: "Today's session: \(slot.title) at \(clock(slot.start))\(spokenLength)."
                )
            }
            return Lines(
                symbol: slot.symbol ?? "dumbbell.fill", eyebrow: "Today", title: slot.title,
                detail: length, short: "Today", brief: "\(slot.shortTitle) today", inline: "\(slot.shortTitle) · today",
                spoken: "Today's session: \(slot.title)\(spokenLength)."
            )
        case .bedBy(let start, let end, let next):
            let window = "\(clock(start))–\(clock(end))"
            var spoken = "Tonight: in bed between \(clock(start)) and \(clock(end))."
            if let next { spoken += " " + spokenNext(next, now: now, calendar: calendar) }
            return Lines(
                symbol: "bed.double.fill", eyebrow: "In bed by", title: window,
                detail: next.map { nextLine($0, now: now, calendar: calendar) },
                short: compactTime(start, calendar: calendar), brief: "Bed by \(compactTime(start, calendar: calendar))",
                inline: "In bed by \(window)", spoken: spoken
            )
        case .rest(let next):
            var spoken = "Rest day."
            if let next { spoken += " " + spokenNext(next, now: now, calendar: calendar) }
            return Lines(
                symbol: "moon.zzz.fill", eyebrow: "Today", title: "Rest day",
                detail: next.map { nextLine($0, now: now, calendar: calendar) },
                short: "Rest", brief: "Rest day",
                inline: next.map { "Rest day · next \(weekday($0.start)) \($0.shortTitle)" } ?? "Rest day",
                spoken: spoken
            )
        case .next(let slot):
            return Lines(
                symbol: slot.symbol ?? "dumbbell.fill", eyebrow: "Next session", title: slot.title,
                detail: "\(dayWord(slot.start, now: now, calendar: calendar)) \(clock(slot.start))",
                short: weekday(slot.start), brief: "\(weekday(slot.start)) \(slot.shortTitle)",
                inline: "Next: \(weekday(slot.start)) \(slot.shortTitle) · \(clock(slot.start))",
                spoken: "Today's session is done. " + spokenNext(slot, now: now, calendar: calendar)
            )
        case .done:
            return Lines(
                symbol: "checkmark.circle.fill", eyebrow: "Today", title: "Done for today", detail: nil,
                short: "Done", brief: "Done today", inline: "Done for today", spoken: "Today's session is done."
            )
        case .noPlan:
            return Lines(
                symbol: "calendar", eyebrow: "This week", title: "No plan yet",
                detail: onWatch ? "Plan it on iPhone" : "Plan your week",
                short: "Plan", brief: "No plan", inline: "No plan this week",
                spoken: onWatch ? "No plan this week. Plan your week in Tensile on iPhone." : "No plan this week. Open Tensile to plan your week."
            )
        case .stale:
            return Lines(
                symbol: "calendar", eyebrow: "Plan", title: "--",
                detail: onWatch ? "Open Tensile on iPhone" : "Open Tensile to update",
                short: "--", brief: "Plan --", inline: "Plan --",
                spoken: onWatch ? "Plan not up to date. Open Tensile on iPhone." : "Plan not up to date. Open Tensile to update."
            )
        }
    }

    /// "Tomorrow: Pull", or "Next: Tue Pull".
    static func nextLine(_ slot: Slot, now: Date, calendar: Calendar) -> String {
        isTomorrow(slot.start, now: now, calendar: calendar)
            ? "Tomorrow: \(slot.shortTitle)"
            : "Next: \(weekday(slot.start)) \(slot.shortTitle)"
    }

    static func spokenNext(_ slot: Slot, now: Date, calendar: Calendar) -> String {
        let day = isTomorrow(slot.start, now: now, calendar: calendar) ? "tomorrow" : slot.start.formatted(.dateTime.weekday(.wide))
        return "Next session: \(day), \(slot.title) at \(clock(slot.start))."
    }

    /// "Tomorrow", or "Tue".
    static func dayWord(_ date: Date, now: Date, calendar: Calendar) -> String {
        isTomorrow(date, now: now, calendar: calendar) ? "Tomorrow" : weekday(date)
    }

    static func isTomorrow(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return false }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }

    /// "6:00 PM" (the user's locale).
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "6 PM", or "6:30 PM" when not on the hour.
    static func compactTime(_ date: Date, calendar: Calendar) -> String {
        calendar.component(.minute, from: date) == 0
            ? date.formatted(.dateTime.hour())
            : date.formatted(.dateTime.hour().minute())
    }

    /// "Tue".
    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// How old a score may be before a widget or complication stops showing it.
///
/// The phone works the scores out when the app is open and when Apple Health
/// wakes it (new sleep, resting heart rate or HRV, hourly at most, and only
/// while the phone is unlocked). Recovery and sleep are set once for the day,
/// so they hold until midnight. Strain only rises through the day, so an old
/// value reads low; after `strainMaxAge` it is shown as "--" instead.
/// App's choices, not research (see `PlanGlance` for why blank beats stale).
nonisolated public enum GlanceFreshness {
    /// Strain shows for this long after the phone last worked it out.
    public static let strainMaxAge: TimeInterval = 3 * 3600

    /// True when scores written at `updated` belong to the day of `now`
    /// (yesterday's recovery, sleep and strain mustn't read as today's).
    public static func isToday(_ updated: Date, at now: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(updated, inSameDayAs: now)
    }

    /// True while strain written at `updated` is still worth showing at `now`.
    public static func strainIsCurrent(updated: Date, at now: Date, calendar: Calendar = .current) -> Bool {
        isToday(updated, at: now, calendar: calendar) && now.timeIntervalSince(updated) < strainMaxAge
    }

    /// Moments after `now` when scores written at `updated` change on their
    /// own, for timeline entries: when strain goes blank, and the next midnight.
    public static func changeDates(updated: Date?, after now: Date, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        if let updated { dates.append(updated.addingTimeInterval(strainMaxAge)) }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.append(midnight)
        }
        return Array(Set(dates.filter { $0 > now })).sorted()
    }
}

/// The Watch's "Intervals" card: this week's hard cardio session
/// (`HardCardio`, `IntervalSession`) as the phone last sent it, and when the
/// Smart Stack should offer it (docs/research/next-features-2026-11.md W4).
///
/// Why a card: there is no health evidence for the card itself; the case is
/// usability, as for `PlanGlance`. It lets the session's day come up on the
/// wrist instead of a clock reminder: reminders helped people repeat a
/// behaviour but got in the way of it becoming automatic (Stawarz 2015, see
/// `PlanGlance`), and predictable gym-goers responded less to prompts
/// (Buyalskaya A, et al. PNAS 2023;120(17):e2216115120; as read for
/// docs/research/evidence-audit-2026-11.md). The session itself is the
/// evidence-backed part (Helgerud 2007, Wen 2019: see `IntervalSession`).
/// The windows below are the app's choices, not research.
///
/// Foundation only, like the rest of this file, so the Watch widget
/// extension compiles it on its own (project.yml).
nonisolated public enum IntervalGlance {
    // MARK: Rules (app's choices)

    /// On its planned day the card is offered from this hour, the hour the
    /// recovery card's morning window opens (`FaceProvider.morningHours`).
    public static let relevanceStartHour = 6

    // MARK: Data

    /// The week's hard session as the phone wrote it.
    nonisolated public struct Session: Codable, Sendable, Equatable {
        /// When the phone wrote it.
        public var updated: Date
        /// "4 × 4 min · Bike".
        public var title: String
        /// SF Symbol for the modality.
        public var symbol: String
        /// Whole minutes, warm-up and cool-down included.
        public var minutes: Int
        /// Start of its planned day; nil in a flexible week (any day).
        public var day: Date?
        /// End of the week it was written in (the next Monday 00:00).
        public var weekEnd: Date
        /// Apple Health has it this week (`HardCardio.weekDone`).
        public var done: Bool
        /// Start of a day the app said it waits (the day reads as easy, or legs
        /// moved next to it: `HardCardio.dayNote`); nil otherwise.
        public var waitsOn: Date?

        public init(updated: Date, title: String, symbol: String, minutes: Int, day: Date?, weekEnd: Date,
                    done: Bool = false, waitsOn: Date? = nil) {
            self.updated = updated
            self.title = title
            self.symbol = symbol
            self.minutes = minutes
            self.day = day
            self.weekEnd = weekEnd
            self.done = done
            self.waitsOn = waitsOn
        }
    }

    nonisolated public enum State: Sendable, Equatable {
        /// Its planned day is today.
        case today(Session)
        /// Today was its day (or any day would do), but the app said it waits.
        case waits(Session)
        /// Planned for a later day this week.
        case later(Session, day: Date)
        /// A flexible week: any day that suits.
        case anyDay(Session)
        /// Done this week.
        case done
        /// None this week, its day has passed, or the phone's data is too old.
        case none
    }

    // MARK: What to show

    /// What the card shows at `now`. Trusted on the day the phone wrote it and
    /// `PlanGlance.carryDays` after, and only inside the week it was written in.
    public static func state(of session: Session?, at now: Date, calendar: Calendar = .current) -> State {
        guard let session, isTrusted(session, at: now, calendar: calendar) else { return .none }
        if session.done { return .done }
        let today = calendar.startOfDay(for: now)
        let plannedDay = session.day.map { calendar.startOfDay(for: $0) }
        if let waitsOn = session.waitsOn, calendar.isDate(waitsOn, inSameDayAs: today), plannedDay == nil || plannedDay == today {
            return .waits(session)
        }
        guard let plannedDay else { return .anyDay(session) }
        if plannedDay == today { return .today(session) }
        return plannedDay > today ? .later(session, day: plannedDay) : .none
    }

    static func isTrusted(_ session: Session, at now: Date, calendar: Calendar) -> Bool {
        guard now < session.weekEnd else { return false }
        let written = calendar.startOfDay(for: session.updated)
        let today = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: written, to: today).day else { return false }
        return (0...PlanGlance.carryDays).contains(days)
    }

    /// When the Smart Stack should offer the card: its planned day, from
    /// `relevanceStartHour` to midnight, while it's still to do and the data
    /// can be trusted then. Nothing in a flexible week (no planned day), once
    /// done, or on a day it waits.
    public static func relevantWindows(of session: Session?, after now: Date, calendar: Calendar = .current) -> [DateInterval] {
        guard let session, !session.done, let planned = session.day else { return [] }
        let day = calendar.startOfDay(for: planned)
        if let waitsOn = session.waitsOn, calendar.isDate(waitsOn, inSameDayAs: day) { return [] }
        guard let start = calendar.date(bySettingHour: relevanceStartHour, minute: 0, second: 0, of: day),
              let midnight = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let end = min(midnight, session.weekEnd)
        guard end > now, end > start, isTrusted(session, at: max(now, start), calendar: calendar) else { return [] }
        return [DateInterval(start: start, end: end)]
    }

    /// Moments after `now` when the card changes on its own (within
    /// `PlanGlance.timelineHorizon`): the planned day's start and end, the
    /// week's end, and when the data stops being trusted.
    public static func changeDates(of session: Session?, after now: Date, calendar: Calendar = .current) -> [Date] {
        guard let session else { return [] }
        var dates = [session.weekEnd]
        if let planned = session.day {
            let day = calendar.startOfDay(for: planned)
            dates.append(day)
            if let next = calendar.date(byAdding: .day, value: 1, to: day) { dates.append(next) }
        }
        let written = calendar.startOfDay(for: session.updated)
        if let untrusted = calendar.date(byAdding: .day, value: PlanGlance.carryDays + 1, to: written) { dates.append(untrusted) }
        let limit = now.addingTimeInterval(PlanGlance.timelineHorizon)
        return Array(Set(dates.filter { $0 > now && $0 <= limit })).sorted()
    }

    // MARK: Wording

    nonisolated public struct Lines: Sendable, Equatable {
        public var symbol: String
        /// "Intervals today", "Intervals Thu".
        public var eyebrow: String
        /// "4 × 4 min · Bike", "Done this week", "--".
        public var title: String
        public var detail: String?
        /// One line: "Intervals today · 4 × 4 min · Bike".
        public var inline: String
        /// The sentence VoiceOver reads.
        public var spoken: String
    }

    /// The words for `state`.
    public static func lines(for state: State) -> Lines {
        switch state {
        case .today(let session):
            return Lines(symbol: session.symbol, eyebrow: "Intervals today", title: session.title,
                         detail: "\(session.minutes) min · start in Tensile",
                         inline: "Intervals today · \(session.title)",
                         spoken: "Intervals today: \(session.title), about \(session.minutes) minutes. Start them in Tensile.")
        case .waits(let session):
            return Lines(symbol: "figure.cooldown", eyebrow: "Intervals", title: "Not today",
                         detail: "They keep for another day",
                         inline: "Intervals: not today",
                         spoken: "No intervals today: \(session.title) keeps for another day. Tensile on iPhone says why.")
        case .later(let session, let day):
            let name = day.formatted(.dateTime.weekday(.abbreviated))
            let wide = day.formatted(.dateTime.weekday(.wide))
            return Lines(symbol: session.symbol, eyebrow: "Intervals \(name)", title: session.title,
                         detail: "\(session.minutes) min", inline: "Intervals \(name) · \(session.title)",
                         spoken: "Intervals on \(wide): \(session.title), about \(session.minutes) minutes.")
        case .anyDay(let session):
            return Lines(symbol: session.symbol, eyebrow: "Intervals this week", title: session.title,
                         detail: "Any day not before legs", inline: "Intervals this week · \(session.title)",
                         spoken: "Intervals this week, on any day that isn't before a leg session: \(session.title).")
        case .done:
            return Lines(symbol: "checkmark.circle.fill", eyebrow: "Intervals", title: "Done this week",
                         detail: nil, inline: "Intervals done this week", spoken: "This week's intervals are done.")
        case .none:
            return Lines(symbol: "bolt.heart", eyebrow: "Intervals", title: "--",
                         detail: "None planned this week", inline: "Intervals --",
                         spoken: "No interval session planned this week, or the plan isn't up to date. Open Tensile on iPhone.")
        }
    }
}
