import Foundation

/// The week's planned sessions as calendar entries, and what has to change in
/// the calendar to match them. Pure: the app's EventKit layer reads the events
/// it owns, asks `changes`, and applies the result.
///
/// Why a calendar entry: writing down a date and a time raised follow-through
/// by 4.2 points against 1.5 for a date alone (Milkman KL et al., Proc Natl
/// Acad Sci USA 2011;108(26):10415-10420, flu-shot uptake), and if-then plans
/// for physical activity have d = 0.31 (Bélanger-Gravel et al. 2013, as cited
/// in `PlannedDay`). Both as read for docs/research/healthy-living-2026-11.md,
/// not re-verified here. The time is the active part, so only weeks with fixed
/// days are written: a flexible week plans no day or time to write down.
///
/// The research file's risk is stale events, so the entries follow the week
/// as it stands now (`AdaptiveWeek`): a session that moved has its entry on
/// its new day, a finished session is marked done at the time it happened,
/// days in rest mode have none, a busy week shows its own short sessions, and
/// a planned day that passed without a session simply has no entry (what to
/// do next, never what was missed).
public enum PlanCalendar {
    /// The calendar the app keeps its sessions in.
    public static let calendarTitle = "Tensile"
    /// Days the app keeps in step, from this week's Monday: this week and next.
    public static let windowDays = 14

    /// One event the calendar should have.
    public struct Entry: Sendable, Equatable, Identifiable {
        /// Stable for a session on a day: "lift|2026-11-17" or "done|2026-11-17".
        public var key: String
        public var title: String
        public var start: Date
        public var end: Date
        public var notes: String?

        public var id: String { key }

        public init(key: String, title: String, start: Date, end: Date, notes: String? = nil) {
            self.key = key
            self.title = title
            self.start = start
            self.end = end
            self.notes = notes
        }
    }

    /// One event the app's calendar has now.
    public struct Existing: Sendable, Equatable {
        /// EventKit's identifier, used only within one sync.
        public var id: String
        /// The entry key read back from the event's URL (`url(for:)`); nil for an event the app didn't tag.
        public var key: String?
        public var title: String
        public var start: Date
        public var end: Date
        public var notes: String?

        public init(id: String, key: String?, title: String, start: Date, end: Date, notes: String? = nil) {
            self.id = id
            self.key = key
            self.title = title
            self.start = start
            self.end = end
            self.notes = notes
        }
    }

    public struct Update: Sendable, Equatable {
        public var id: String
        public var entry: Entry
    }

    public struct Changes: Sendable, Equatable {
        public var create: [Entry] = []
        public var update: [Update] = []
        /// Event identifiers to remove.
        public var remove: [String] = []

        public var isEmpty: Bool { create.isEmpty && update.isEmpty && remove.isEmpty }
    }

    /// A finished gym session this week.
    public struct Finished: Sendable, Equatable {
        public var start: Date
        public var minutes: Int
        public var name: String

        public init(start: Date, minutes: Int, name: String) {
            self.start = start
            self.minutes = minutes
            self.name = name
        }
    }

    // MARK: Keys

    /// The link stored on each event so the app knows it again. Event
    /// identifiers can change when a calendar syncs, so the key travels with
    /// the event instead of being remembered beside it.
    public static func url(for key: String) -> URL? {
        var components = URLComponents()
        components.scheme = "workoutapp"
        components.host = "plan"
        components.queryItems = [URLQueryItem(name: "entry", value: key)]
        return components.url
    }

    public static func key(from url: URL?) -> String? {
        guard let url, url.scheme == "workoutapp", url.host == "plan" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "entry" }?.value
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func two(_ value: Int?) -> String { let v = value ?? 0; return v < 10 ? "0\(v)" : "\(v)" }
        return "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day))"
    }

    // MARK: What the calendar should hold

    /// The window the app keeps in step: this week's Monday to two weeks on.
    public static func window(now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = WeeklyPlan.weekStart(containing: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: windowDays, to: start) ?? start.addingTimeInterval(Double(windowDays) * 86_400)
        return DateInterval(start: start, end: end)
    }

    /// Days before the window the app also reads, only to clear its own
    /// planned sessions that passed without one (`isPassedSession`): once the
    /// week turns they are outside `window`, and nothing else would remove them.
    public static let lookbackDays = 7

    /// The `lookbackDays` before the window that starts at `windowStart`.
    public static func lookback(before windowStart: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: windowStart)
            ?? windowStart.addingTimeInterval(-Double(lookbackDays) * 86_400)
        return DateInterval(start: start, end: windowStart)
    }

    /// True for one of the app's planned-session events ("lift|…") dated
    /// before today: a planned day that passed without a session has no
    /// entry, in an earlier week as in this one. Finished sessions ("done|…")
    /// stay where they are.
    public static func isPassedSession(key: String?, start: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard let key, key.hasPrefix("lift|") else { return false }
        return start < calendar.startOfDay(for: now)
    }

    /// The entries for this week and next.
    /// - Parameters:
    ///   - plan: this week's plan; nil without one.
    ///   - week: this week's queue (`AdaptiveWeek.make`), when it has been
    ///     worked out; without it a fixed-day plan's remaining days are used.
    ///   - nextPlan: next week's plan, once it is saved.
    ///   - finished: this week's finished gym sessions.
    ///   - restUntil: rest mode's end, if it is on: no session before it.
    public static func entries(plan: WeeklyPlan?, week: AdaptiveWeek.Result?, nextPlan: WeeklyPlan? = nil,
                               finished: [Finished] = [], restUntil: Date? = nil, now: Date = .now,
                               calendar: Calendar = .current) -> [Entry] {
        var result: [Entry] = []
        let window = window(now: now, calendar: calendar)
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: window.start) ?? window.end
        func resting(_ start: Date) -> Bool { restUntil.map { start < $0 } ?? false }
        func session(_ day: PlannedDay, start: Date, note: String?, busy: Bool) -> Entry {
            var lines: [String] = []
            if busy { lines.append("Busy week: each main lift for one or two hard sets. " + BusyWeek.headline) }
            if let note, !note.isEmpty { lines.append(note) }
            if let ifThen = day.ifThen, !ifThen.isEmpty { lines.append(ifThen) }
            lines.append("\(day.minutes) min. From your Tensile plan.")
            return Entry(key: "lift|" + dayKey(start, calendar: calendar), title: day.focus.title,
                         start: start, end: start.addingTimeInterval(Double(max(5, day.minutes)) * 60),
                         notes: lines.joined(separator: "\n"))
        }
        func time(_ minutes: Int, on day: Date) -> Date? {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
        }

        // Finished sessions this week, at the time they happened.
        var doneDays: Set<Date> = []
        for item in finished.sorted(by: { $0.start < $1.start }) where item.start >= window.start && item.start < nextWeekStart {
            let day = calendar.startOfDay(for: item.start)
            guard !doneDays.contains(day) else { continue }
            doneDays.insert(day)
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(Entry(key: "done|" + dayKey(day, calendar: calendar), title: (name.isEmpty ? "Workout" : name) + " · done",
                                start: item.start, end: item.start.addingTimeInterval(Double(max(5, item.minutes)) * 60),
                                notes: "Logged in Tensile."))
        }

        // This week's sessions still to do, where the queue has them now.
        if let plan, !plan.isFlexible {
            let today = calendar.startOfDay(for: now)
            if let week {
                for slot in week.slots where slot.date >= today && !doneDays.contains(calendar.startOfDay(for: slot.date)) {
                    guard let start = time(slot.session.time, on: slot.date), !resting(start) else { continue }
                    result.append(session(slot.session, start: start, note: slot.note, busy: plan.isBusy))
                }
            } else {
                for day in plan.sortedDays {
                    guard let start = plan.start(of: day, calendar: calendar), start >= today,
                          !doneDays.contains(calendar.startOfDay(for: start)), !resting(start) else { continue }
                    result.append(session(day, start: start, note: nil, busy: plan.isBusy))
                }
            }
        }

        // Next week, once it is planned.
        if let nextPlan, !nextPlan.isFlexible, calendar.isDate(nextPlan.weekStart, inSameDayAs: nextWeekStart) {
            for day in nextPlan.sortedDays {
                guard let start = nextPlan.start(of: day, calendar: calendar), !resting(start) else { continue }
                result.append(session(day, start: start, note: nil, busy: nextPlan.isBusy))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: What to change

    /// What to create, update and remove so the app's calendar holds exactly
    /// `desired`. `existing` must be the app's own events inside `window`
    /// only: everything in it that isn't wanted is removed, so events outside
    /// the window (earlier weeks) and in other calendars are never touched.
    public static func changes(desired: [Entry], existing: [Existing]) -> Changes {
        var changes = Changes()
        var byKey: [String: Existing] = [:]
        for event in existing.sorted(by: { $0.start < $1.start }) {
            // An untagged event, or a second one for the same key, isn't wanted.
            guard let key = event.key, byKey[key] == nil else {
                changes.remove.append(event.id)
                continue
            }
            byKey[key] = event
        }
        var wanted: Set<String> = []
        for entry in desired where !wanted.contains(entry.key) {
            wanted.insert(entry.key)
            guard let event = byKey[entry.key] else {
                changes.create.append(entry)
                continue
            }
            let same = event.title == entry.title && abs(event.start.timeIntervalSince(entry.start)) < 1
                && abs(event.end.timeIntervalSince(entry.end)) < 1 && (event.notes ?? "") == (entry.notes ?? "")
            if !same { changes.update.append(Update(id: event.id, entry: entry)) }
        }
        for (key, event) in byKey where !wanted.contains(key) { changes.remove.append(event.id) }
        changes.remove.sort()
        return changes
    }
}
