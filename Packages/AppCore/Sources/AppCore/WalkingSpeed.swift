import Foundation

/// Everyday walking speed from the iPhone (`HKQuantityType(.walkingSpeed)`),
/// shown as a tracked stat with a 90-day trend, and graded only from 60
/// (docs/research/next-features-2026-11.md, §4a row 7; §5 item 10).
///
/// Evidence and its limits:
/// - Faster walkers live longer: each 0.1 m/s faster went with HR 0.94 for
///   death, fastest vs slowest HR 0.57 (13 cohorts, 530,841 people; Liu et
///   al., J Sports Sci 2024). Self-reported slow vs brisk pace: HR about 2 in
///   men (UK Biobank; Yates et al., Eur Heart J 2017). Observational, so it
///   marks health more than it causes it.
/// - The association is strongest in older adults (Studenski et al., JAMA
///   2011, pooled cohorts aged 65+), and most people under 60 walk near the
///   top of the range (a ceiling effect), so a grade would say little. Under
///   `gradedFromAge` the stat is tracked, not graded.
/// - The grade bands are Studenski 2011's: under 0.8 m/s went with shorter
///   than median survival and 1.0 m/s or more with longer (from the record;
///   the abstract wasn't re-read this round). Those were 4-6 m gait tests at
///   usual pace; Apple's number is the iPhone's estimate during everyday
///   walking with the phone carried, not a clinic test, so the bands are a
///   guide, said so on screen.
/// - A change of about 0.05 m/s is small and 0.1 m/s substantial in older
///   adults (Perera et al., J Am Geriatr Soc 2006; from memory), used here
///   only to call the 90-day trend "steady" or not.
public enum WalkingSpeed {
    /// Graded from this age; tracked only before it.
    public static let gradedFromAge = 60
    /// Studenski 2011: under 0.8 m/s, below-median survival.
    public static let slowBelow = 0.8
    /// Studenski 2011: 1.0 m/s or more, above-median survival.
    public static let brisk = 1.0
    /// Perera 2006: about 0.05 m/s is the smallest meaningful change.
    public static let meaningfulChange = 0.05
    /// Days compared at each end of the 90-day window (app's choice: four
    /// weeks smooth out days carrying the phone differently).
    public static let trendWindowDays = 28
    /// Days with a reading needed in each window before a trend is shown (app's choice).
    public static let trendMinimumDays = 7

    public enum Grade: String, Sendable, Equatable {
        case slower = "Slower range"
        case typical = "Middle range"
        case brisk = "Brisk range"
    }

    /// Nil under `gradedFromAge`.
    public static func grade(metersPerSecond: Double, age: Int) -> Grade? {
        guard age >= gradedFromAge, metersPerSecond > 0 else { return nil }
        if metersPerSecond < slowBelow { return .slower }
        if metersPerSecond >= brisk { return .brisk }
        return .typical
    }

    /// The mean of the last `days` daily values (by date), or nil without any.
    public static func recentAverage(_ daily: [DayValue], days: Int = 7, now: Date = .now, calendar: Calendar = .current) -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else { return nil }
        let values = daily.filter { $0.date >= start && $0.value > 0 }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    public struct Trend: Sendable, Equatable {
        /// Last four weeks' mean minus the first four weeks' mean, m/s.
        public var change: Double
        public var isSteady: Bool { abs(change) < WalkingSpeed.meaningfulChange }
    }

    /// The 90-day trend: the latest `trendWindowDays` against the earliest,
    /// each needing `trendMinimumDays` readings. Nil with too little data.
    public static func trend(_ daily: [DayValue], now: Date = .now, calendar: Calendar = .current) -> Trend? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -89, to: today),
              let earlyEnd = calendar.date(byAdding: .day, value: trendWindowDays, to: windowStart),
              let lateStart = calendar.date(byAdding: .day, value: -(trendWindowDays - 1), to: today) else { return nil }
        let early = daily.filter { $0.date >= windowStart && $0.date < earlyEnd && $0.value > 0 }.map(\.value)
        let late = daily.filter { $0.date >= lateStart && $0.value > 0 }.map(\.value)
        guard early.count >= trendMinimumDays, late.count >= trendMinimumDays else { return nil }
        let change = late.reduce(0, +) / Double(late.count) - early.reduce(0, +) / Double(early.count)
        return Trend(change: change)
    }

    /// Metres per second → km/h or mph.
    public static func display(_ metersPerSecond: Double, miles: Bool) -> Double {
        metersPerSecond * 3.6 / (miles ? 1.609344 : 1)
    }

    /// The status line under the number.
    public static func status(average: Double?, trend: Trend?, age: Int, miles: Bool) -> String? {
        if let average, let grade = grade(metersPerSecond: average, age: age) { return grade.rawValue }
        guard let trend else { return average == nil ? nil : "Tracked, not graded under \(gradedFromAge)" }
        if trend.isSteady { return "Steady over 3 months" }
        let shown = display(abs(trend.change), miles: miles).formatted(.number.precision(.fractionLength(1)))
        return "\(trend.change > 0 ? "+" : "−")\(shown) \(miles ? "mph" : "km/h") over 3 months"
    }
}
