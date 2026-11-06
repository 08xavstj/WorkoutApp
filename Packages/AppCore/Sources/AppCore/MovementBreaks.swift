import Foundation

/// Movement breaks and the post-meal walk, from the hourly step timeline and
/// the times meals were logged.
///
/// Breaking up prolonged sitting with standing or light walking lowers
/// post-meal glucose and insulin (Buffey et al., Sports Med 2022, meta-
/// analysis; the walking bouts in the pooled trials were 2-5 min, within
/// 60-90 min of eating). Regular activity breaks from sitting lowered
/// post-meal glucose and insulin in overweight adults (Dunstan et al.,
/// Diabetes Care 2012). See docs/research/competitors.md item 9.
public enum MovementBreaks {
    /// One hour of the step timeline.
    public struct HourSteps: Sendable, Equatable {
        public var start: Date
        public var steps: Double

        public init(start: Date, steps: Double) {
            self.start = start
            self.steps = steps
        }
    }

    public enum Nudge: Sendable, Equatable, Identifiable {
        /// A meal was logged recently and little walking has followed.
        case postMealWalk(meal: Date)
        /// This many consecutive waking hours under the step floor.
        case sedentary(hours: Int)

        public var id: String {
            switch self {
            case .postMealWalk(let meal): "meal-\(Int(meal.timeIntervalSince1970 / 60))"
            case .sedentary(let hours): "sedentary-\(hours)"
            }
        }
    }

    /// An hour with fewer steps than this counts as still. App choice: the
    /// 250-steps-an-hour floor is the usual consumer "inactivity" definition
    /// (Apple's and Fitbit's hourly reminders); the trials used sitting time,
    /// not steps (Buffey 2022; Dunstan 2012).
    public static let sedentaryStepsPerHour = 250.0
    /// Hours of sitting before a break is suggested (the pooled trials
    /// interrupted sitting every 20-30 min; two full hours is a conservative
    /// trigger that won't nag).
    public static let sedentaryHours = 2
    /// The walk is worth taking within this long after a meal (Buffey 2022:
    /// light walking within 60-90 min of eating).
    public static let postMealWindow: TimeInterval = 75 * 60
    /// Steps since the meal below which the walk hasn't happened yet.
    public static let postMealStepFloor = 250.0
    /// Nudges stop this late (minutes after midnight) so nobody is told to
    /// walk at bedtime.
    public static let quietFromMinutes = 22 * 60
    /// Step data older than this (or none since waking) means the timeline
    /// has stopped, not that you have: no nudge. App choice.
    public static let staleDataLimit: TimeInterval = 90 * 60
    /// Without a wake time, waking hours start here.
    public static let defaultWakeMinutes = 7 * 60

    public static let postMealTitle = "Walk after that meal"
    public static let postMealDetail = "A 5-minute walk in the next hour helps blood sugar after that meal (light walking within 60-90 min of eating lowered glucose and insulin in a meta-analysis, Buffey 2022)."
    public static let sedentaryTitle = "Time for a movement break"
    public static func sedentaryDetail(hours: Int) -> String {
        "Under 250 steps an hour for \(hours) hours. A 2-5 minute walk breaks it up; regular breaks from sitting lower post-meal glucose and insulin (Dunstan 2012; Buffey 2022)."
    }

    /// Sedentary breaks are on by default for fat-loss, health and stamina
    /// goals; for muscle- and strength-only goals they're off (extra walking
    /// competes with recovery only marginally, so it's a choice, not a rule;
    /// competitors.md item 9). The post-meal walk applies to everyone.
    public static func sedentaryBreaksOn(goals: Goals?) -> Bool {
        guard let goals else { return true }
        if goals.weight == .lose { return true }
        return goals.focuses.contains(.health) || goals.focuses.contains(.endurance) || goals.focuses.isEmpty
    }

    /// At most one nudge: the post-meal walk first, otherwise a sedentary
    /// break. Nil outside waking hours, after the quiet time, or when nothing applies.
    ///
    /// - Parameters:
    ///   - hourlySteps: today's step timeline, one entry per clock hour (hours
    ///     with no data may be missing and count as zero, up to the newest
    ///     hour with steps).
    ///   - mealTimes: times meals were logged today (timed dietary samples).
    ///   - wake: when the user got up today, if known.
    public static func assess(
        hourlySteps: [HourSteps],
        mealTimes: [Date],
        now: Date = .now,
        wake: Date? = nil,
        goals: Goals? = nil,
        calendar: Calendar = .current
    ) -> Nudge? {
        let dayStart = calendar.startOfDay(for: now)
        let minutesNow = Int(now.timeIntervalSince(dayStart) / 60)
        guard minutesNow < quietFromMinutes else { return nil }
        let wakeTime = wake ?? dayStart.addingTimeInterval(TimeInterval(defaultWakeMinutes * 60))
        guard now >= wakeTime else { return nil }

        let steps = hourlySteps.filter { calendar.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        // Missing hours only mean "still" while the steps keep syncing: with no
        // step sample since waking, or the newest over 90 min old (watch off,
        // phone left behind, sync stalled), say nothing rather than nag.
        guard let newest = steps.last(where: { $0.steps > 0 && $0.start.addingTimeInterval(3600) > wakeTime }),
              now.timeIntervalSince(min(now, newest.start.addingTimeInterval(3600))) <= staleDataLimit
        else { return nil }

        // Post-meal walk: the latest meal inside the window, with little walking since.
        if let meal = mealTimes.filter({ $0 <= now && now.timeIntervalSince($0) <= postMealWindow }).max() {
            let since = steps.filter { $0.start.addingTimeInterval(3600) > meal }.map(\.steps).reduce(0, +)
            if since < postMealStepFloor {
                return .postMealWalk(meal: meal)
            }
        }

        guard sedentaryBreaksOn(goals: goals) else { return nil }
        // Sedentary: the run of complete waking hours under the floor ending now.
        // Start of the current clock hour (components, not `date(bySetting:)`, which can move forward).
        // Hours after the newest sample aren't known yet, so the run stops there.
        let currentHour = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: now)) ?? now
        var hour = min(currentHour, newest.start.addingTimeInterval(3600))
        var run = 0
        while true {
            guard let previous = calendar.date(byAdding: .hour, value: -1, to: hour), previous >= wakeTime else { break }
            let count = steps.first { calendar.isDate($0.start, equalTo: previous, toGranularity: .hour) }?.steps ?? 0
            guard count < sedentaryStepsPerHour else { break }
            run += 1
            hour = previous
        }
        return run >= sedentaryHours ? .sedentary(hours: run) : nil
    }
}
