import Foundation

/// "First session back": when a session follows a planned session that
/// didn't happen, or seven or more days off, the note after it says so in one
/// sentence (`CoachCheckIns.postWorkout`), and never what came before.
///
/// Evidence (moderate): of 54 four-week programmes tested on 61,293 gym
/// members, the best one gave a small reward for coming back after a missed
/// workout, and only 8% of the programmes had any measurable effect after the
/// four weeks (Milkman KL et al. Megastudies improve the impact of applied
/// behavioural science. Nature 2021;600(7889):478-483; as read for
/// docs/research/healthy-living-2026-11.md, not re-verified here). The moment
/// after a miss is the one to mark; the app gives the fact, not a reward,
/// and expects little to last.
public enum FirstSessionBack {
    /// Days off that count as coming back: the same line as the restart week.
    public static let daysOff = RestartPlan.daysOffThreshold

    /// How the note's first sentence opens.
    public static let lead = "First session back: "

    /// True when the session on `sessionDay` is the first one back.
    /// - Parameters:
    ///   - sessionDay: any time on the day of the session just finished.
    ///   - earlierTrainingDays: days with a session before that day.
    ///   - plans: saved weekly plans (this week's and last week's are used).
    ///
    /// Seven or more days since the last session counts, unless this week or
    /// last was a planned busy week (`BusyWeek`): that gap was the plan. A
    /// planned session counts as not having happened when a fixed-day plan
    /// had a day between the last session and this one, and fewer sessions
    /// were done than were planned by then (so a session done a day early
    /// doesn't make the next one "back"). A flexible week plans no days, so
    /// only the seven-day rule applies to it.
    public static func applies(sessionDay: Date, earlierTrainingDays: [Date], plans: [WeeklyPlan],
                               calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: sessionDay)
        let earlier = Set(earlierTrainingDays.map { calendar.startOfDay(for: $0) }).filter { $0 < today }
        // The very first session is a start, not a return.
        guard let last = earlier.max() else { return false }
        let thisWeek = WeeklyPlan.weekStart(containing: today, calendar: calendar)
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        let recent = plans.filter { calendar.isDate($0.weekStart, inSameDayAs: thisWeek) || calendar.isDate($0.weekStart, inSameDayAs: lastWeek) }
        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        if gap >= daysOff, !recent.contains(where: \.isBusy) { return true }

        // Planned days (fixed-day weeks) from the Monday of the last session's week up to
        // yesterday, so an extra session in an earlier week doesn't hide this week's gap.
        let from = max(lastWeek, WeeklyPlan.weekStart(containing: last, calendar: calendar))
        var planned: [Date] = []
        for plan in recent where !plan.isFlexible {
            for day in plan.plannedDays {
                guard let date = calendar.date(byAdding: .day, value: WeeklyPlan.order(day.weekday), to: calendar.startOfDay(for: plan.weekStart)),
                      date >= from, date < today else { continue }
                planned.append(calendar.startOfDay(for: date))
            }
        }
        guard planned.contains(where: { $0 > last }) else { return false }
        let done = earlier.filter { $0 >= from }.count
        return done < planned.count
    }
}
