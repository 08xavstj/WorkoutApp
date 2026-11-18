import Foundation

// Weekly cardio minutes for the last 12 weeks: minutes in each heart-rate
// zone, and moderate-equivalent minutes (moderate + 2 x vigorous) against the
// WHO band (competitor-features-2026-11.md, B8). Built from the app's own
// counting, so the numbers match everywhere else:
// - zone minutes: the zones of the scheme passed in (the Zones page passes
//   heart-rate reserve, as for day strain), counting only readings at 40%+
//   of reserve (`minimumReserveFraction`), so a day at the desk isn't zone 1;
// - moderate and vigorous minutes: `IntensityMinutes.count` (ACSM 40-59% and
//   60%+ of reserve), with lifting left out (`IntensityMinutes.outsideLifting`).
//
// Evidence: strong for weekly minutes. WHO 2020 recommends 150-300 minutes of
// moderate or 75-150 of vigorous activity a week, or a mix, with more giving
// more benefit (Bull FC, et al. Br J Sports Med 2020;54:1451-1462). Zones are
// labels: fixed percentages match individual thresholds poorly (Iannetta D,
// et al. Med Sci Sports Exerc 2020;52(2):466-473), so the chart shows the mix
// without a target ratio. Polarized training beat threshold training only in
// trained endurance athletes, in small trials (Rosenblat MA, et al. J Strength
// Cond Res 2019;33(12):3491-3500): weak-moderate, and not shown as a goal.

public nonisolated enum WeeklyIntensity {
    /// Weeks on the chart (the doc's B8: 12 weeks, about one quarter).
    public static let weeksShown = 12
    /// WHO 2020's band of moderate-equivalent minutes a week (Bull 2020).
    public static let guidelineLow = IntensityMinutes.weeklyGoal
    public static let guidelineHigh = 300
    /// Zone minutes count only readings at or above 40% of heart-rate reserve,
    /// ACSM's lower limit of moderate intensity (Garber CE, et al. ACSM
    /// position stand. Med Sci Sports Exerc 2011;43(7):1334-1359). The chart
    /// is built from all-day heart rate, and a scheme whose zone 1 has no
    /// floor (Apple Health's) would otherwise count every reading, some 2,500
    /// minutes a week, and squash the WHO lines.
    public static let minimumReserveFraction = 0.4
    /// Raise when the counting changes, so cached weeks are counted again
    /// (`signature`). 2: the 40% floor above.
    public static let countingVersion = 2

    public nonisolated struct Week: Codable, Sendable, Equatable, Identifiable {
        /// Start of the week (the calendar's first weekday).
        public var start: Date
        /// Minutes in zones 1-5, index 0 = zone 1.
        public var zoneMinutes: [Double]
        public var moderate: Int
        public var vigorous: Int
        /// False when no heart rate was recorded that week.
        public var hasHeartRate: Bool

        public init(start: Date, zoneMinutes: [Double], moderate: Int, vigorous: Int, hasHeartRate: Bool) {
            self.start = start
            self.zoneMinutes = zoneMinutes
            self.moderate = moderate
            self.vigorous = vigorous
            self.hasHeartRate = hasHeartRate
        }

        public var id: Date { start }
        /// Moderate + 2 x vigorous, as WHO counts them (`IntensityMinutes.vigorousWeight`).
        public var moderateEquivalent: Int { IntensityMinutes.Result(moderate: moderate, vigorous: vigorous).total }
        public var standing: Standing { WeeklyIntensity.standing(moderateEquivalent) }
    }

    public nonisolated enum Standing: Sendable, Equatable {
        case below, within, above

        public var title: String {
            switch self {
            case .below: "Under 150"
            case .within: "150–300"
            case .above: "Over 300"
            }
        }
    }

    public static func standing(_ minutes: Int) -> Standing {
        if minutes < guidelineLow { return .below }
        return minutes <= guidelineHigh ? .within : .above
    }

    /// The starts of the `count` weeks ending with the one containing `date`, oldest first.
    public static func weekStarts(endingWith date: Date, count: Int = weeksShown, calendar: Calendar = .current) -> [Date] {
        guard count > 0, let current = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        // Each start is the start of its own week: where midnight is skipped
        // for daylight saving, a week can start at 01:00 and the others at
        // 00:00, so the current week's time of day can't be carried back.
        return (0..<count).reversed().compactMap { weeks in
            calendar.date(byAdding: .weekOfYear, value: -weeks, to: current)
                .map { calendar.dateInterval(of: .weekOfYear, for: $0)?.start ?? calendar.startOfDay(for: $0) }
        }
    }

    /// One week's minutes from heart rate in `[start, end)`.
    public static func week(start: Date, end: Date, heartRate: [HeartRateSample], lifting: [DateInterval],
                            profile: HeartRateProfile, scheme: HeartRateZoneScheme) -> Week {
        let inWeek = heartRate.filter { $0.date >= start && $0.date < end && $0.bpm.isFinite && $0.bpm > 0 }
        let outside = IntensityMinutes.outsideLifting(inWeek, lifting: lifting).sorted { $0.date < $1.date }
        let minutes = IntensityMinutes.count(outside, profile: profile)
        let zones = zoneMinutes(outside, profile: profile, scheme: scheme)
        return Week(start: start, zoneMinutes: zones, moderate: minutes.moderate, vigorous: minutes.vigorous,
                    hasHeartRate: !inWeek.isEmpty)
    }

    /// Minutes in zones 1-5 (always five), weighted as
    /// `HeartRateZoneScheme.zoneMinutes` (each reading stands for the time to
    /// the next, up to its limits), from readings at 40%+ of reserve only.
    /// Readings below still end the one before them, so a short burst isn't
    /// stretched over the rest it was followed by.
    public static func zoneMinutes(_ samples: [HeartRateSample], profile: HeartRateProfile,
                                   scheme: HeartRateZoneScheme) -> [Double] {
        let sorted = samples.sorted { $0.date < $1.date }
        var minutes = Array(repeating: 0.0, count: 5)
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= HeartRateZoneScheme.maxSampleGap,
                  profile.reserveFraction(for: current.bpm) >= minimumReserveFraction - 1e-9,
                  let zone = scheme.zone(for: current.bpm), (1...5).contains(zone) else { continue }
            minutes[zone - 1] += min(gap / 60, HeartRateZoneScheme.maxMinutesPerSample)
        }
        return minutes
    }

    /// A key per week for the lifting that was left out of it: every
    /// interval overlapping the week, as whole-second start and end times in
    /// order ("" for none), so an edited, added or deleted session changes
    /// its week's key. Deterministic across launches, unlike `Hasher`.
    public static func liftingFingerprints(_ lifting: [DateInterval], weekStarts starts: [Date],
                                           calendar: Calendar = .current) -> [Date: String] {
        let sorted = lifting.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [Date: String] = [:]
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1]
                : (calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400))
            result[start] = sorted
                .filter { $0.start < end && $0.end >= start }
                .map { "\(Int($0.start.timeIntervalSince1970.rounded(.down)))-\(Int($0.end.timeIntervalSince1970.rounded(.down)))" }
                .joined(separator: ",")
        }
        return result
    }

    /// Weeks from heart rate covering them all, one per start in `starts`
    /// (each runs to the next start, the last to a week later).
    public static func weeks(starts: [Date], heartRate: [HeartRateSample], lifting: [DateInterval],
                             profile: HeartRateProfile, scheme: HeartRateZoneScheme, calendar: Calendar = .current) -> [Week] {
        starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1]
                : (calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400))
            return week(start: start, end: end, heartRate: heartRate, lifting: lifting, profile: profile, scheme: scheme)
        }
    }

    /// Weeks in the band, out of weeks with heart rate (for the summary line).
    /// Pass finished weeks only: the current one is still filling up.
    public static func weeksMet(_ weeks: [Week]) -> (met: Int, of: Int) {
        let measured = weeks.filter(\.hasHeartRate)
        return (measured.filter { $0.moderateEquivalent >= guidelineLow }.count, measured.count)
    }

    /// A short key for the zones and profile a week was counted with, so a
    /// cached week is counted again when either changes.
    public static func signature(profile: HeartRateProfile, scheme: HeartRateZoneScheme) -> String {
        let edges = ([scheme.floor ?? 0] + scheme.boundaries).map { "\(Int($0.rounded()))" }.joined(separator: ",")
        return "v\(countingVersion)|\(scheme.kind.rawValue)|\(edges)|\(Int(profile.restingHeartRate.rounded()))|\(Int(profile.maxHeartRate.rounded()))"
    }

    /// What the chart can and can't say.
    public static let evidenceNote = "Evidence: strong for weekly minutes. WHO recommends 150–300 minutes of moderate activity a week, or half as much vigorous; a vigorous minute counts as two (Bull 2020). Heart rate during lifting isn't counted, and zone minutes start at 40% of your heart-rate reserve (moderate, ACSM). Zones are labels: their edges match your own thresholds only roughly (Iannetta 2020), so there's no target mix."
}
