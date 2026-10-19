import Foundation
import AppCore

extension VitalsModel {
    /// Days with a logged strength session in the last 7, for Biology.
    static func strengthDaysStat(sessions: [StrengthSessionSummary], now: Date = .now) -> Stat {
        let calendar = Calendar.current
        let dates = sessions.map(\.start)
        let count = StrengthDays.lastSevenDays(dates, now: now)
        let met = count >= StrengthDays.weeklyTarget
        let trainedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        let series: [DatedValue] = (0..<14).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return DatedValue(date: day, value: trainedDays.contains(day) ? 1 : 0)
        }
        var stat = Stat(
            id: "strengthDays", category: .activity, title: "Strength days", icon: "dumbbell.fill",
            value: "\(count)", unit: "this week",
            status: met ? "Goal reached" : "\(StrengthDays.weeklyTarget - count) more to reach 2",
            tone: met ? .good : .neutral,
            gauge: min(1, Double(count) / Double(StrengthDays.weeklyTarget)),
            series: series
        )
        stat.chart = .bars
        stat.historyUnit = "session"
        stat.goal = nil
        stat.defaultDays = 7
        stat.about = "Days you logged a strength workout. Health guidelines recommend strength training on 2 or more days a week (WHO 2020); it's linked with 10-17% lower risk of early death (Momma et al., Br J Sports Med 2022)."
        return stat
    }
}
