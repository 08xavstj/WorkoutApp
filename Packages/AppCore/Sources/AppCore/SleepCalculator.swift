import Foundation

/// Scores one night of sleep 0-100 from Apple Health sleep stages.
///
/// Weights (the app's choice; no study sets them): 50% time asleep vs. sleep
/// need, 25% efficiency, 10% deep + REM share, 15% interruptions. With bed/wake
/// regularity known: 45 / 20 / 10 / 10, plus 15% regularity.
///
/// - Need: 8 h by default. Adults need 7 h or more (Watson et al., Sleep 2015,
///   AASM/SRS consensus); no study ties extra need to the previous day's
///   training load, so strain doesn't change it.
/// - Efficiency: 85% or more is good sleep quality (Ohayon et al., Sleep Health
///   2017, National Sleep Foundation), so it gets full marks from 85% and
///   none at 65%.
/// - Deep + REM: weighted lightly because wrist trackers detect sleep well but
///   stage it poorly (Chinoy et al., Sleep 2021; Schyvens et al., Sleep Adv 2025).
public struct SleepCalculator: Sendable {
    public var baseSleepNeedHours: Double = 8
    /// Extra sleep needed per strain point (%) above 48 the previous day.
    /// Off (0) by default: there's no research for a load-based sleep need.
    public var extraNeedPerStrainPoint: TimeInterval = 0
    /// Deep + REM share of total sleep that earns full marks.
    public var targetRestorativeShare: Double = 0.40
    /// Awake periods at least this long count as an interruption.
    public var minimumInterruption: TimeInterval = 5 * 60

    public init() {}

    public struct Result: Sendable, Equatable {
        public var score: Int
        public var asleep: TimeInterval
        public var inBed: TimeInterval
        public var need: TimeInterval
        public var deep: TimeInterval
        public var rem: TimeInterval
        public var core: TimeInterval
        public var awake: TimeInterval
        public var interruptions: Int
        public var bedtime: Date?
        public var wakeTime: Date?
        /// 0-100 how consistent bed and wake times were over the last week, if known.
        public var consistency: Int?

        public var efficiency: Double { inBed > 0 ? min(1, asleep / inBed) : 0 }
    }

    public func sleepNeed(previousDayStrain: Double?) -> TimeInterval {
        let base = baseSleepNeedHours * 3600
        guard let strain = previousDayStrain else { return base }
        return base + max(0, strain - 48) * extraNeedPerStrainPoint
    }

    /// Returns nil when there is no sleep in the samples.
    /// - Parameter consistency: from `SleepConsistency.score`. When given, it is
    ///   15% of the score (regular sleep predicted lower mortality more strongly
    ///   than duration in 61,000 UK Biobank adults: Windred et al., Sleep 2024).
    public func score(samples: [SleepSample], previousDayStrain: Double? = nil, consistency: Int? = nil) -> Result? {
        // Several sources (iPhone + Watch) often record the same night. When any
        // staged data exists, ignore the vaguer "unspecified" samples.
        let stagedTypes: Set<SleepStage> = [.core, .deep, .rem]
        let hasStages = samples.contains { stagedTypes.contains($0.stage) }
        let staged = samples.filter { !(hasStages && $0.stage == .unspecified) }

        // Score only the main sleep: naps and evening dozes are separate
        // sessions and would otherwise stretch the night and wreck efficiency.
        // In-bed and awake samples count when they fall around the main sleep.
        let asleepAll = staged.filter { $0.stage.isAsleep }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        guard let main = SleepSessions.main(asleepAll) else { return nil }
        let windowStart = main.start.addingTimeInterval(-3600)
        let windowEnd = main.end.addingTimeInterval(30 * 60)
        let usable = staged.filter { sample in
            sample.stage.isAsleep
                ? sample.start >= main.start && sample.end <= main.end
                : sample.end > windowStart && sample.start < windowEnd
        }.map { sample -> SleepSample in
            // Clip in-bed/awake samples to the window around the main sleep.
            guard !sample.stage.isAsleep else { return sample }
            return SleepSample(stage: sample.stage, start: max(sample.start, windowStart), end: min(sample.end, windowEnd))
        }

        let asleepIntervals = usable.filter { $0.stage.isAsleep }.map { ($0.start, $0.end) }
        let asleep = Self.unionDuration(asleepIntervals)
        guard asleep > 0 else { return nil }

        func total(_ stage: SleepStage) -> TimeInterval {
            Self.unionDuration(usable.filter { $0.stage == stage }.map { ($0.start, $0.end) })
        }
        let deep = total(.deep)
        let rem = total(.rem)
        let core = total(.core)
        let awake = total(.awake)

        let bedtime = usable.map(\.start).min()
        let wakeTime = usable.map(\.end).max()
        var window = asleep
        if let bedtime, let wakeTime {
            window = wakeTime.timeIntervalSince(bedtime)
        }
        let inBed = max(asleep, total(.inBed), window)

        let interruptions = usable.filter { $0.stage == .awake && $0.duration >= minimumInterruption }.count
        let need = sleepNeed(previousDayStrain: previousDayStrain)

        let durationScore = min(1, asleep / need)
        let rawEfficiency = inBed > 0 ? min(1, asleep / inBed) : 0
        let efficiency = min(1, max(0, (rawEfficiency - 0.65) / 0.20))
        let restorative = hasStages ? min(1, (deep + rem) / asleep / targetRestorativeShare) : 0.75
        let interruptionScore = max(0, 1 - Double(interruptions) / 8)

        let weighted: Double
        if let consistency {
            let regularity: Double = Double(consistency) / 100
            weighted = 0.45 * durationScore + 0.2 * efficiency + 0.1 * restorative + 0.1 * interruptionScore
                + 0.15 * regularity
        } else {
            weighted = 0.5 * durationScore + 0.25 * efficiency + 0.1 * restorative + 0.15 * interruptionScore
        }
        return Result(
            score: Int((weighted * 100).rounded()),
            asleep: asleep,
            inBed: inBed,
            need: need,
            deep: deep,
            rem: rem,
            core: core,
            awake: awake,
            interruptions: interruptions,
            bedtime: bedtime,
            wakeTime: wakeTime,
            consistency: consistency
        )
    }

    /// Total time covered by a set of intervals, counting overlaps once.
    static func unionDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?
        for (start, end) in sorted {
            if let runningEnd = currentEnd, start <= runningEnd {
                currentEnd = max(runningEnd, end)
            } else {
                if let s = currentStart, let e = currentEnd { total += e.timeIntervalSince(s) }
                currentStart = start
                currentEnd = end
            }
        }
        if let s = currentStart, let e = currentEnd { total += e.timeIntervalSince(s) }
        return total
    }
}

/// How regular bed and wake times are, 0-100. A simplified version of the
/// Sleep Regularity Index: the spread (SD) of bedtimes and wake times over the
/// last week. 20 minutes or less scores 100; 2 hours or more scores 0.
public enum SleepConsistency {
    public struct Night: Sendable, Equatable {
        public var bedtime: Date
        public var wake: Date
        public init(bedtime: Date, wake: Date) {
            self.bedtime = bedtime
            self.wake = wake
        }
    }

    /// Needs at least 4 nights.
    public static func score(_ nights: [Night], calendar: Calendar = .current) -> Int? {
        guard let average = spreadMinutes(nights, calendar: calendar) else { return nil }
        let score = 100 * (1 - (average - 20) / 100)
        return Int(min(100, max(0, score)).rounded())
    }

    /// Typical spread of bed and wake times in minutes (the average of the two).
    /// Times of day are on a 24-hour circle, so 11:50 and 12:10, or 11 pm and
    /// 1 am, count as 20 minutes and 2 hours apart, wherever they fall.
    public static func spreadMinutes(_ nights: [Night], calendar: Calendar = .current) -> Double? {
        guard nights.count >= 4 else { return nil }
        func minuteOfDay(_ date: Date) -> Double {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        let bed = circularSpread(nights.map { minuteOfDay($0.bedtime) })
        let wake = circularSpread(nights.map { minuteOfDay($0.wake) })
        return (bed + wake) / 2
    }

    /// Circular standard deviation, in minutes, of times of day (minutes after midnight).
    static func circularSpread(_ minutes: [Double]) -> Double {
        guard !minutes.isEmpty else { return 0 }
        let angles = minutes.map { $0 / 1440 * 2 * Double.pi }
        let x = angles.map(cos).reduce(0, +) / Double(angles.count)
        let y = angles.map(sin).reduce(0, +) / Double(angles.count)
        let length = min(1, max(1e-12, (x * x + y * y).squareRoot()))
        return (-2 * log(length)).squareRoot() * 1440 / (2 * Double.pi)
    }
}
