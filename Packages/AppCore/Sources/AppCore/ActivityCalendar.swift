import Foundation

// One calendar of every activity: logged gym sessions and the cardio and
// sports workouts Apple Health holds, grouped by day for a month grid
// (competitor-features-2026-11.md, B6).
//
// Evidence: seeing what you did is self-monitoring, which works best with
// feedback and goal review (Michie S, et al. Health Psychol 2009;28(6):690-701,
// meta-regression of 122 evaluations; Harkin B, et al. Psychol Bull
// 2016;142(2):198-229, d = 0.40 for progress monitoring). That is moderate
// evidence for the technique; no trial tests a calendar itself. The calendar
// shows days trained, never a streak: a broken streak lowers later engagement
// (Silverman J, Barasch A. J Consum Res 2023;49(6):1095-1117).

/// What kind of activity a workout was, for the calendar's dots and the year's totals.
public nonisolated enum ActivityKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case lifting, run, walk, ride, swim, otherCardio, sport, snow, other

    public var id: String { rawValue }

    /// "Runs", for totals and the legend.
    public var title: String {
        switch self {
        case .lifting: "Lifting"
        case .run: "Runs"
        case .walk: "Walks & hikes"
        case .ride: "Rides"
        case .swim: "Swims"
        case .otherCardio: "Other cardio"
        case .sport: "Sports"
        case .snow: "Snow sports"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .lifting: "dumbbell.fill"
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .ride: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .otherCardio: "figure.mixed.cardio"
        case .sport: "sportscourt"
        case .snow: "figure.skiing.downhill"
        case .other: "figure.flexibility"
        }
    }

    /// Distance means something for this kind (shown in totals).
    public var hasDistance: Bool {
        switch self {
        case .run, .walk, .ride, .swim, .snow: true
        default: false
        }
    }

    /// The kind of one of Tensile's own Watch cardio activities.
    public static func of(_ activity: CardioActivity) -> ActivityKind {
        switch activity {
        case .outdoorRun, .treadmill: .run
        case .outdoorWalk, .hiking: .walk
        case .outdoorCycle, .indoorCycle: .ride
        case .rower, .elliptical, .stairs, .hiit: .otherCardio
        case .squash, .badminton, .tennis, .pickleball, .tableTennis, .basketball, .volleyball,
             .indoorSoccer, .outdoorSoccer, .ultimateFrisbee, .hockey, .climbing: .sport
        case .crossCountrySkiing, .downhillSkiing, .snowboarding, .skating: .snow
        case .other: .other
        }
    }
}

public nonisolated enum ActivityCalendar {
    /// One logged session or Health workout.
    public nonisolated struct Activity: Sendable, Equatable, Identifiable {
        /// Unique across both sources (a session's ID or the Health workout's UUID).
        public var id: String
        public var kind: ActivityKind
        public var title: String
        public var start: Date
        public var end: Date
        public var distanceMeters: Double?
        /// For a logged session: the Health workouts that recorded it (a
        /// watch's strength workout), so they aren't listed twice.
        public var linkedWorkoutIDs: Set<String>

        public init(id: String, kind: ActivityKind, title: String, start: Date, end: Date,
                    distanceMeters: Double? = nil, linkedWorkoutIDs: Set<String> = []) {
            self.id = id
            self.kind = kind
            self.title = title
            self.start = start
            self.end = max(start, end)
            self.distanceMeters = distanceMeters
            self.linkedWorkoutIDs = linkedWorkoutIDs
        }

        public var seconds: TimeInterval { end.timeIntervalSince(start) }
    }

    /// The activities that started on one day.
    public nonisolated struct Day: Sendable, Equatable, Identifiable {
        /// Start of the day.
        public var date: Date
        /// In time order.
        public var activities: [Activity]
        public var id: Date { date }

        /// Each kind once, in the order it first appears: the day's dots.
        public var kinds: [ActivityKind] {
            var seen: [ActivityKind] = []
            for activity in activities where !seen.contains(activity.kind) { seen.append(activity.kind) }
            return seen
        }

        public var minutes: Double { activities.reduce(0) { $0 + $1.seconds } / 60 }
    }

    /// A watch's strength workout counts as the same session when it covers
    /// at least this share of the shorter of the two. The app's choice:
    /// WorkoutLinking pairs most of them by ID; this catches the rest.
    public static let sameSessionOverlap = 0.5

    /// Logged sessions plus Health workouts, without a Health workout that
    /// only recorded a logged session: one linked to it by ID, or a strength
    /// workout overlapping it by `sameSessionOverlap` or more.
    public static func merged(lifting: [Activity], health: [Activity]) -> [Activity] {
        let linked = Set(lifting.flatMap(\.linkedWorkoutIDs))
        let kept = health.filter { workout in
            if linked.contains(workout.id) { return false }
            guard workout.kind == .lifting else { return true }
            return !lifting.contains { overlapShare($0, workout) >= sameSessionOverlap }
        }
        return (lifting + kept).sorted { $0.start < $1.start }
    }

    /// Overlap as a share of the shorter activity (0 when either has no length).
    static func overlapShare(_ a: Activity, _ b: Activity) -> Double {
        let shorter = min(a.seconds, b.seconds)
        guard shorter > 0 else { return 0 }
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        return max(0, overlap) / shorter
    }

    /// Activities grouped by the day they started, keyed by start of day.
    public static func days(_ activities: [Activity], calendar: Calendar = .current) -> [Date: Day] {
        var result: [Date: Day] = [:]
        for activity in activities.sorted(by: { $0.start < $1.start }) {
            let day = calendar.startOfDay(for: activity.start)
            result[day, default: Day(date: day, activities: [])].activities.append(activity)
        }
        return result
    }

    /// The month containing `date` as grid cells, a week to a row starting on
    /// the calendar's first weekday: nil before the 1st and after the last day.
    public static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        guard let first = days.first else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Very short weekday names in grid order ("M", "T", ...).
    public static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Sessions of one kind.
    public nonisolated struct KindCount: Sendable, Equatable {
        public var kind: ActivityKind
        public var sessions: Int
    }

    /// A month's totals.
    public nonisolated struct MonthSummary: Sendable, Equatable {
        public var activeDays: Int
        public var sessions: Int
        public var minutes: Double
        /// Sessions per kind, most first.
        public var byKind: [KindCount]
    }

    /// Sessions per kind, most first (ties in `ActivityKind` order).
    public static func counts(_ activities: [Activity]) -> [KindCount] {
        var counts: [ActivityKind: Int] = [:]
        for activity in activities { counts[activity.kind, default: 0] += 1 }
        let order = ActivityKind.allCases
        return counts.map { KindCount(kind: $0.key, sessions: $0.value) }.sorted {
            $0.sessions != $1.sessions ? $0.sessions > $1.sessions
                : (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0)
        }
    }

    public static func summary(_ days: [Date: Day], month: Date, calendar: Calendar = .current) -> MonthSummary {
        let inMonth = days.values.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        let activities = inMonth.flatMap(\.activities)
        return MonthSummary(activeDays: inMonth.filter { !$0.activities.isEmpty }.count, sessions: activities.count,
                            minutes: activities.reduce(0) { $0 + $1.seconds } / 60, byKind: counts(activities))
    }
}
