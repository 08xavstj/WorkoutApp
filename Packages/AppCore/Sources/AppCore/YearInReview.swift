import Foundation

// A year's activity in a few numbers: sessions, time and distance per
// activity type, records set, and the busiest month
// (competitor-features-2026-11.md, B12).
//
// Evidence: weak. Reviewing progress supports goal attainment (Harkin B, et
// al. Psychol Bull 2016;142(2):198-229), but no trial tests a yearly recap,
// so the page stays small and makes no claims; the UI says the evidence is weak.

public nonisolated enum YearInReview {
    public nonisolated struct KindTotal: Sendable, Equatable, Identifiable {
        public var kind: ActivityKind
        public var sessions: Int
        public var seconds: TimeInterval
        /// Nil when no activity of this kind had a distance.
        public var meters: Double?
        public var id: ActivityKind { kind }
    }

    public nonisolated struct Summary: Sendable, Equatable {
        public var year: Int
        public var sessions: Int
        public var activeDays: Int
        public var seconds: TimeInterval
        public var meters: Double
        /// Most sessions first.
        public var byKind: [KindTotal]
        /// Sessions in each month, January first (12 values).
        public var sessionsPerMonth: [Int]
        /// The month (1-12) with the most sessions; the earlier one on a tie;
        /// nil for an empty year.
        public var busiestMonth: Int?
        public var records: Int
    }

    /// The year's totals from activities started in it (others are ignored).
    public static func summary(year: Int, activities: [ActivityCalendar.Activity], records: Int,
                               calendar: Calendar = .current) -> Summary {
        let inYear = activities.filter { calendar.component(.year, from: $0.start) == year }
        var perMonth = Array(repeating: 0, count: 12)
        for activity in inYear {
            let month = calendar.component(.month, from: activity.start)
            if (1...12).contains(month) { perMonth[month - 1] += 1 }
        }
        let peak = perMonth.max() ?? 0
        let busiest = peak > 0 ? (perMonth.firstIndex(of: peak).map { $0 + 1 }) : nil
        let byKind = ActivityCalendar.counts(inYear).map { count in
            let ofKind = inYear.filter { $0.kind == count.kind }
            let distances = ofKind.compactMap(\.distanceMeters).filter { $0 > 0 }
            return KindTotal(kind: count.kind, sessions: count.sessions,
                             seconds: ofKind.reduce(0) { $0 + $1.seconds },
                             meters: distances.isEmpty ? nil : distances.reduce(0, +))
        }
        let days = Set(inYear.map { calendar.startOfDay(for: $0.start) })
        return Summary(year: year, sessions: inYear.count, activeDays: days.count,
                       seconds: inYear.reduce(0) { $0 + $1.seconds },
                       meters: inYear.compactMap(\.distanceMeters).filter { $0 > 0 }.reduce(0, +),
                       byKind: byKind, sessionsPerMonth: perMonth, busiestMonth: busiest, records: records)
    }

    /// Years with at least one activity, newest first.
    public static func years(_ activities: [ActivityCalendar.Activity], calendar: Calendar = .current) -> [Int] {
        Set(activities.map { calendar.component(.year, from: $0.start) }).sorted(by: >)
    }

    public static let evidenceNote = "Evidence: weak. Looking back at what you did can help you keep going (Harkin 2016), but no study has tested a yearly recap. Records count lift records and new cardio bests; times include every logged session and Health workout."
}
