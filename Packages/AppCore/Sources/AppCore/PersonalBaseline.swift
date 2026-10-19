import Foundation

/// "Your normal" for any daily measurement: the mean ± 1 SD of the previous
/// 30-60 days, leaving out the last week so a recent change shows up against
/// it instead of dragging it along. Watching a 7-day rolling average against a
/// personal baseline band is how day-to-day noise is handled in HRV monitoring
/// (Plews et al., Eur J Appl Physiol 2012; Sports Med 2013); the same idea
/// works for resting heart rate, sleep, steps and the rest.
public enum PersonalBaseline {
    /// Points needed in the baseline window before a band is shown.
    public static let minimumPoints = 14

    public struct Band: Sendable, Equatable {
        public var mean: Double
        public var sd: Double
        public var count: Int
        public var low: Double { mean - sd }
        public var high: Double { mean + sd }

        public init(mean: Double, sd: Double, count: Int) {
            self.mean = mean
            self.sd = sd
            self.count = count
        }
    }

    public enum Position: String, Sendable {
        case below, within, above
    }

    /// The baseline window: days from `asOf - windowDays` up to (not including)
    /// the most recent `excludeRecentDays` days.
    static func window(_ points: [DayValue], asOf: Date, excludeRecentDays: Int, windowDays: Int, calendar: Calendar) -> [DayValue] {
        let today = calendar.startOfDay(for: asOf)
        guard let end = calendar.date(byAdding: .day, value: -(excludeRecentDays - 1), to: today),
              let start = calendar.date(byAdding: .day, value: -(windowDays + excludeRecentDays - 1), to: today) else { return [] }
        return points.filter { $0.date >= start && $0.date < end }
    }

    /// Your normal band, or nil until there are `minimumPoints` days of history.
    public static func band(
        _ points: [DayValue],
        asOf: Date = .now,
        excludeRecentDays: Int = 7,
        windowDays: Int = 60,
        calendar: Calendar = .current
    ) -> Band? {
        let values = window(points, asOf: asOf, excludeRecentDays: excludeRecentDays, windowDays: windowDays, calendar: calendar).map(\.value)
        guard values.count >= minimumPoints else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let squares = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        let sd = sqrt(squares / Double(values.count - 1))
        return Band(mean: mean, sd: sd, count: values.count)
    }

    /// Days until the band appears, assuming one reading a day from now on.
    /// Readings join the baseline once they're `excludeRecentDays` old.
    public static func daysUntilReady(
        _ points: [DayValue],
        asOf: Date = .now,
        excludeRecentDays: Int = 7,
        windowDays: Int = 60,
        calendar: Calendar = .current
    ) -> Int {
        let have = window(points, asOf: asOf, excludeRecentDays: excludeRecentDays, windowDays: windowDays, calendar: calendar).count
        let needed = minimumPoints - have
        guard needed > 0 else { return 0 }
        let today = calendar.startOfDay(for: asOf)
        // Recent readings (still inside the excluded week), oldest first, and
        // how many days until each one is old enough to count.
        let waits: [Int] = points
            .map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: today).day ?? 0 }
            .filter { $0 >= 0 && $0 < excludeRecentDays }
            .map { excludeRecentDays - $0 }
            .sorted()
        if waits.count >= needed { return waits[needed - 1] }
        return excludeRecentDays + (needed - waits.count)
    }

    /// Trailing average over the last `days` calendar days at each point.
    public static func rollingAverage(_ points: [DayValue], days: Int = 7, calendar: Calendar = .current) -> [DayValue] {
        let sorted = points.sorted { $0.date < $1.date }
        return sorted.map { point in
            let day = calendar.startOfDay(for: point.date)
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: day) ?? day
            let window = sorted.filter { $0.date >= start && $0.date <= point.date }.map(\.value)
            return DayValue(date: point.date, value: window.reduce(0, +) / Double(max(window.count, 1)))
        }
    }

    public static func position(_ value: Double, in band: Band) -> Position {
        value < band.low ? .below : (value > band.high ? .above : .within)
    }

    /// Percent difference from the band's mean, e.g. +6 = 6% above normal.
    public static func percentFromNormal(_ value: Double, band: Band) -> Double? {
        guard band.mean != 0 else { return nil }
        return (value / band.mean - 1) * 100
    }

    /// The last 7 days' average (optionally leaving out today, for daily totals
    /// still being counted), compared with the band.
    public static func recentAverage(
        _ points: [DayValue],
        days: Int = 7,
        excludingToday: Bool = false,
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        let today = calendar.startOfDay(for: asOf)
        let end = excludingToday ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? asOf)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return nil }
        let values = points.filter { $0.date >= start && $0.date < end }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
