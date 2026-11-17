import Foundation

/// What the Plan widget (iPhone Lock Screen, Home Screen, StandBy) and the
/// Watch's "Today's plan" complication say at a given moment, and when the
/// data behind a glance is too old to show.
///
/// Why a plan widget: there is no health evidence for widgets. The case is
/// usability. Most activity-tracker sessions are glances of about five
/// seconds (Gouveia R, Karapanos E, Hassenzahl M. How do we engage with
/// activity trackers? UbiComp 2015), and cues in the environment supported
/// habits where clock reminders did not (Stawarz K, Cox AL, Blandford A.
/// Beyond self-tracking and reminders. CHI 2015). Both are carried from
/// docs/research/healthy-living-2026-11.md (§3 item 5), where they were seen
/// in search summaries only: not re-verified.
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

        public init(updated: Date, hasPlan: Bool, slots: [Slot], weekEnd: Date, nextWeek: NextWeek = .unplanned,
                    doneAt: Date? = nil, restToday: Bool = false, bedByStart: Date? = nil, bedByEnd: Date? = nil,
                    weekDone: Int? = nil, weekPlanned: Int? = nil) {
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
        let done = [plan.doneAt, alsoDoneAt].compactMap { $0 }.max()
        func isDone(_ slot: Slot) -> Bool {
            done.map { calendar.isDate($0, inSameDayAs: slot.start) } ?? false
        }
        let sorted = plan.slots.sorted { $0.start < $1.start }
        if sorted.contains(where: { $0.start < today && !isDone($0) }) { return .stale }

        if now >= plan.weekEnd {
            switch plan.nextWeek {
            case .unplanned: return .noPlan
            case .open: return .stale
            case .planned: break
            }
        } else if !plan.hasPlan {
            return .noPlan
        }

        let trainedToday = done.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        let resting = age == 0 && plan.restToday
        let current = resting ? nil : sorted.first { calendar.isDate($0.start, inSameDayAs: now) && !isDone($0) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let next = sorted.first { $0.start >= tomorrow }

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
            let following = sorted.first { $0.start >= bed.end && !isDone($0) }
            return .bedBy(start: bed.start, end: bed.end, next: following)
        }
        if trainedToday {
            if let next { return .next(next) }
            return .done
        }
        return .rest(next: next)
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
    public static func changeDates(of plan: Plan?, after now: Date, horizon: TimeInterval = 48 * 3600,
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
        }
        let limit = now.addingTimeInterval(horizon)
        return Array(Set(dates.filter { $0 > now && $0 <= limit })).sorted()
    }

    /// When the Smart Stack should offer the plan: the hour before each
    /// session still to do, and from an hour before tonight's bed-by window to
    /// its end. Only while the plan can be trusted (`carryDays`).
    public static func relevantIntervals(of plan: Plan?, after now: Date, alsoDoneAt: Date? = nil,
                                         calendar: Calendar = .current) -> [DateInterval] {
        guard let plan, let age = age(of: plan, at: now, calendar: calendar) else { return [] }
        if case .stale = state(of: plan, at: now, alsoDoneAt: alsoDoneAt, calendar: calendar) { return [] }
        let written = calendar.startOfDay(for: plan.updated)
        let trustedUntil = calendar.date(byAdding: .day, value: carryDays + 1, to: written) ?? written.addingTimeInterval(2 * 86_400)
        let done = [plan.doneAt, alsoDoneAt].compactMap { $0 }.max()
        var intervals: [DateInterval] = []
        for slot in plan.slots where slot.start > now && slot.start < trustedUntil {
            if let done, calendar.isDate(done, inSameDayAs: slot.start) { continue }
            if age == 0, plan.restToday, calendar.isDate(slot.start, inSameDayAs: now) { continue }
            intervals.append(DateInterval(start: slot.start.addingTimeInterval(-sessionRelevanceLead), end: slot.start))
        }
        if let start = plan.bedByStart, let end = plan.bedByEnd, end > start, end > now, start < trustedUntil {
            intervals.append(DateInterval(start: start.addingTimeInterval(-bedRelevanceLead), end: end))
        }
        return Array(intervals.sorted { $0.start < $1.start }.prefix(maximumRelevantIntervals))
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
