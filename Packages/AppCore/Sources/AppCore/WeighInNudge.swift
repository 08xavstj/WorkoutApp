import Foundation

/// When to nudge for a weigh-in on a lose or gain goal.
///
/// Regular self-weighing goes with better weight outcomes and, in most
/// studies, no psychological harm (Zheng et al., Obesity 2015, review of 17
/// longitudinal studies); daily and weekly weighing did not differ in a
/// meta-analysis, where accountability mattered more (Madigan et al., IJBNPA
/// 2015). The trend line itself needs 4+ readings over 10 days
/// (`WeightTrend.weeklyChange`), so three or four a week is the practical
/// floor; three days without one is when the nudge shows (an app choice).
/// Maintain goals get no nudge (behaviour-change.md rec. 15: weekly is enough).
public enum WeighInNudge {
    /// Days without a weigh-in before the nudge shows.
    public static let daysWithoutWeighIn = 3

    /// A few mornings, not daily: daily and weekly weighing worked about the
    /// same in the meta-analysis (Madigan 2015, verified on PubMed November
    /// 2026), and frequent weighing goes with disordered-eating symptoms in
    /// cross-sectional studies (healthy-living-2026-11.md).
    public static let title = "Weigh in a few mornings a week"

    /// True for a lose/gain goal with no weigh-in for `daysWithoutWeighIn` days or more.
    public static func isDue(goals: Goals?, lastWeighIn: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let goals, goals.weight != .maintain else { return false }
        guard let lastWeighIn else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWeighIn), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= daysWithoutWeighIn
    }

    /// The line under the title: what the evidence says, in cautious words.
    public static func detail(lastWeighIn: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        var opening = "No weigh-in in Apple Health yet."
        if let lastWeighIn {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWeighIn), to: calendar.startOfDay(for: now)).day ?? 0
            opening = "Last weigh-in \(days) day\(days == 1 ? "" : "s") ago."
        }
        return opening + " Weighing regularly helps inside a plan like this one; daily and weekly weighing worked about the same (Madigan 2015). Three or four mornings a week keep the trend line honest; read the trend, not the number."
    }
}
