import Foundation

/// Sleep Regularity Index (SRI): how likely you are to be in the same state
/// (asleep or awake) at any moment as at the same moment 24 hours earlier
/// (Phillips et al., Sci Rep 2017). 100 = identical days; 0 = no better than
/// chance. In 60,977 UK Biobank adults, a higher SRI predicted lower mortality
/// more strongly than sleep duration (Windred et al., Sleep 2024).
///
/// Computed on 5-minute epochs over noon-to-noon days. Only pairs of
/// consecutive days that both have recorded sleep are compared, so a night the
/// watch wasn't worn doesn't count as "awake all night".
public enum SleepRegularity {
    public static let epoch: TimeInterval = 5 * 60
    /// Pairs of consecutive days needed (5 nights).
    public static let minimumPairs = 4

    /// - Parameters:
    ///   - asleep: asleep intervals over the period (any order, may overlap).
    ///   - start: the first day's start (e.g. noon before the first night).
    ///   - days: how many noon-to-noon days to look at.
    /// - Returns: SRI on Phillips' scale, -100...100 (real values are almost always 0...100).
    public static func index(asleep: [DateInterval], start: Date, days: Int) -> Double? {
        guard days >= 2 else { return nil }
        let merged = merge(asleep)
        let epochsPerDay = Int(86_400 / epoch)
        // Asleep flag per epoch, per day.
        var dayStates: [[Bool]] = []
        var hasSleep: [Bool] = []
        for day in 0..<days {
            let dayStart = start.addingTimeInterval(Double(day) * 86_400)
            var states = [Bool](repeating: false, count: epochsPerDay)
            var any = false
            for interval in merged where interval.end > dayStart && interval.start < dayStart.addingTimeInterval(86_400) {
                let first = max(0, Int((interval.start.timeIntervalSince(dayStart) / epoch).rounded(.down)))
                let last = min(epochsPerDay - 1, Int((interval.end.timeIntervalSince(dayStart) / epoch).rounded(.up)) - 1)
                guard first <= last else { continue }
                for index in first...last {
                    // Asleep if the epoch's midpoint is inside the interval.
                    let mid = dayStart.addingTimeInterval((Double(index) + 0.5) * epoch)
                    if mid >= interval.start && mid < interval.end { states[index] = true; any = true }
                }
            }
            dayStates.append(states)
            hasSleep.append(any)
        }
        var same = 0
        var total = 0
        var pairs = 0
        for day in 0..<(days - 1) where hasSleep[day] && hasSleep[day + 1] {
            pairs += 1
            for index in 0..<epochsPerDay {
                total += 1
                if dayStates[day][index] == dayStates[day + 1][index] { same += 1 }
            }
        }
        guard pairs >= minimumPairs, total > 0 else { return nil }
        let p = Double(same) / Double(total)
        return 200 * p - 100
    }

    /// The SRI as a 0-100 score (negative values, which mean worse than chance, count as 0).
    public static func score(asleep: [DateInterval], start: Date, days: Int) -> Int? {
        index(asleep: asleep, start: start, days: days).map { Int(min(100, max(0, $0)).rounded()) }
    }

    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

// MARK: - Weekday/weekend midpoint shift

/// How much later (or earlier) the middle of your sleep falls on weekend
/// nights than on weekday nights: "social jet lag". A shift of more than
/// about 1–2 hours is linked with cardiometabolic risk, and irregular
/// sleepers run a later body clock even at the same sleep length (Phillips
/// et al., Sci Rep 2017; health-metrics.md §5, evidence rated moderate). The
/// 1-hour target is the roadmap's, so the copy says "about an hour".
extension SleepRegularity {
    /// Shift to stay within, minutes (roadmap Phase 3 item 4: a 1-hour target).
    public static let midpointShiftTargetMinutes = 60
    /// Nights needed on each side.
    public static let minimumWeekdayNights = 3
    public static let minimumWeekendNights = 2

    public struct MidpointShift: Sendable, Equatable {
        /// Weekend midpoint minus weekday midpoint, minutes; positive = later at weekends.
        public var minutes: Int
        public var weekdayNights: Int
        public var weekendNights: Int

        public init(minutes: Int, weekdayNights: Int, weekendNights: Int) {
            self.minutes = minutes
            self.weekdayNights = weekdayNights
            self.weekendNights = weekendNights
        }

        public var isWithinTarget: Bool { abs(minutes) <= SleepRegularity.midpointShiftTargetMinutes }

        /// "1h 20m later" / "20 min earlier" / "Same as weekdays", for use after
        /// a "weekend shift" label.
        public var text: String {
            let magnitude = abs(minutes)
            let span = magnitude >= 60 ? "\(magnitude / 60)h \(magnitude % 60)m" : "\(magnitude) min"
            if magnitude < 15 { return "Same as weekdays" }
            return "\(span) \(minutes > 0 ? "later" : "earlier")"
        }

        /// One line of meaning for the UI.
        public var note: String {
            isWithinTarget
                ? "Your weekend sleep sits within about an hour of weekdays, which keeps your body clock in one place (Phillips 2017)."
                : "Weekend sleep more than about an hour off weekdays shifts your body clock, like a small time-zone change twice a week (Phillips 2017). Keeping the wake time within an hour matters more than the bedtime."
        }
    }

    /// - Parameter nights: bed and wake times; a night is a weekend night when
    ///   its wake time falls on a weekend day (Saturday or Sunday morning).
    /// - Returns: nil with fewer than 3 weekday or 2 weekend nights.
    public static func midpointShift(nights: [SleepConsistency.Night], calendar: Calendar = .current) -> MidpointShift? {
        var weekday: [Double] = []
        var weekend: [Double] = []
        for night in nights where night.wake > night.bedtime {
            let mid = night.bedtime.addingTimeInterval(night.wake.timeIntervalSince(night.bedtime) / 2)
            let parts = calendar.dateComponents([.hour, .minute], from: mid)
            // Minutes after noon, so a 3 am midpoint (900) and a 1 am one (780) average sensibly.
            let fromNoon = Double(((parts.hour ?? 0) * 60 + (parts.minute ?? 0) - 12 * 60 + 1440) % 1440)
            if calendar.isDateInWeekend(night.wake) { weekend.append(fromNoon) } else { weekday.append(fromNoon) }
        }
        guard weekday.count >= minimumWeekdayNights, weekend.count >= minimumWeekendNights else { return nil }
        let weekdayMean = weekday.reduce(0, +) / Double(weekday.count)
        let weekendMean = weekend.reduce(0, +) / Double(weekend.count)
        return MidpointShift(minutes: Int((weekendMean - weekdayMean).rounded()), weekdayNights: weekday.count, weekendNights: weekend.count)
    }

    /// One line of meaning for the Sleep Regularity Index: the UK Biobank
    /// median is about 81 and the mortality benefit sat in the top quintiles,
    /// from roughly 85 up (Windred et al., Sleep 2024).
    public static let typicalIndex = 81
    public static let benefitIndex = 85

    /// "Above the 85 linked to better health (typical is 81)". No number up
    /// front: it sits beside the "92 / 100" it explains.
    public static func indexNote(_ sri: Int) -> String {
        if sri >= benefitIndex {
            let place = sri == benefitIndex ? "At" : "Above"
            return "\(place) the \(benefitIndex) linked to better health (typical is \(typicalIndex); Windred 2024)."
        }
        if sri >= typicalIndex - 5 {
            return "About typical (\(typicalIndex)); \(benefitIndex)+ is linked to better health (Windred 2024)."
        }
        return "Below typical (\(typicalIndex)); \(benefitIndex)+ is linked to better health (Windred 2024). A steady wake time moves it most."
    }
}

/// Sleep debt: how far behind your sleep need you are over the last 14 nights.
///
/// Two weeks of 6 h nights built up deficits as large as a night without
/// sleep, while people felt only slightly sleepy (Van Dongen et al., Sleep
/// 2003). Adults need 7 h or more (Watson et al., Sleep 2015). Extra sleep on
/// later nights partly makes up for short ones (Banks et al., Sleep 2010: one
/// longer recovery night restores part of the loss, more with more sleep;
/// Kitamura et al., Sci Rep 2016: debt is paid back over days), so longer
/// nights pay the debt down. (Sletten et al., Sleep Health 2023 is the NSF
/// consensus on sleep regularity, not on catch-up sleep.)
public enum SleepDebt {
    public static let nights = 14
    /// More than this is shown as "over 20 h": beyond it the number means little.
    public static let cap = 20.0

    public enum Level: String, Sendable {
        case none = "None"
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
    }

    public struct Result: Sendable, Equatable {
        /// Hours behind, 0 when caught up.
        public var hours: Double
        public var nightsCounted: Int
        public var level: Level
        /// Extra minutes a night and for how many nights, to pay it back.
        public var extraMinutesPerNight: Int?
        public var paybackNights: Int?

        public var plan: String? {
            guard let extra = extraMinutesPerNight, let nights = paybackNights else { return nil }
            return "Sleep about \(extra) min more for \(nights) night\(nights == 1 ? "" : "s"): go to bed earlier rather than sleeping in, so your wake time stays regular."
        }
    }

    /// - Parameters:
    ///   - nightlyHours: hours asleep per night, oldest first (nights without data left out).
    ///   - needHours: your sleep need.
    /// - Returns: nil with fewer than 5 nights.
    public static func compute(nightlyHours: [Double], needHours: Double) -> Result? {
        let recent = Array(nightlyHours.suffix(nights))
        guard recent.count >= 5, needHours > 0 else { return nil }
        // Running balance: short nights add debt, long nights pay it back (never below 0).
        var debt = 0.0
        for hours in recent {
            debt = max(0, debt + needHours - hours)
        }
        debt = min(cap, debt)
        let level: Level = debt < 1 ? .none : (debt < 3 ? .low : (debt < 6 ? .moderate : .high))
        var extra: Int?
        var payback: Int?
        if debt >= 1 {
            // 30-60 extra minutes a night is realistic; spread over at most two weeks.
            let minutes = min(60, max(30, debt * 60 / 7))
            let rounded = Int((minutes / 15).rounded(.up) * 15)
            extra = rounded
            payback = min(14, Int((debt * 60 / Double(rounded)).rounded(.up)))
        }
        return Result(hours: (debt * 10).rounded() / 10, nightsCounted: recent.count, level: level,
                      extraMinutesPerNight: extra, paybackNights: payback)
    }
}

/// HRV (RMSSD) from beat-to-beat timings, so Apple Watch data can be compared
/// with Garmin's and the camera's RMSSD instead of Apple's SDNN. RMSSD is the
/// metric used in HRV-guided training (Plews et al., Eur J Appl Physiol 2012)
/// and is valid from short recordings (Munoz et al., PLoS One 2015).
public enum BeatToBeat {
    public struct Beat: Sendable, Equatable {
        /// Seconds since the start of the recording.
        public var time: Double
        /// True when the sensor lost contact just before this beat.
        public var precededByGap: Bool

        public init(time: Double, precededByGap: Bool) {
            self.time = time
            self.precededByGap = precededByGap
        }
    }

    /// RR intervals (seconds) between consecutive beats, dropping any that span a
    /// gap, are implausible (outside 0.3-2.0 s) or jump more than 20% from the
    /// previous interval (ectopic beats and artefacts). Each entry keeps whether
    /// it directly follows the previous kept interval.
    static func cleanIntervals(_ beats: [Beat]) -> [(rr: Double, follows: Bool)] {
        var result: [(rr: Double, follows: Bool)] = []
        var previousRR: Double?
        for (index, beat) in beats.enumerated().dropFirst() {
            let rr = beat.time - beats[index - 1].time
            guard !beat.precededByGap, rr >= 0.3, rr <= 2.0 else {
                previousRR = nil
                continue
            }
            if let previous = previousRR, abs(rr - previous) / previous > 0.2 {
                previousRR = nil
                continue
            }
            result.append((rr: rr, follows: previousRR != nil))
            previousRR = rr
        }
        return result
    }

    /// RMSSD in milliseconds, or nil with under `minimumSeconds` of clean beats.
    public static func rmssd(_ beats: [Beat], minimumSeconds: Double = 180) -> Double? {
        let intervals = cleanIntervals(beats)
        let covered = intervals.map(\.rr).reduce(0, +)
        guard covered >= minimumSeconds else { return nil }
        var squares = 0.0
        var count = 0
        for index in intervals.indices.dropFirst() where intervals[index].follows {
            let difference = (intervals[index].rr - intervals[index - 1].rr) * 1000
            squares += difference * difference
            count += 1
        }
        guard count >= 30 else { return nil }
        return (squares / Double(count)).squareRoot()
    }
}
