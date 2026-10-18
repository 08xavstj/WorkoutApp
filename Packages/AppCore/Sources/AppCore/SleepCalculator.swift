import Foundation

/// Scores one night of sleep 0-100 from Apple Health sleep stages.
///
/// Weights: 50% time asleep vs. sleep need, 20% efficiency (asleep / in bed),
/// 20% restorative sleep (deep + REM share), 10% interruptions.
public struct SleepCalculator: Sendable {
    public var baseSleepNeedHours: Double = 8
    /// Extra sleep needed per strain point (%) above 48 the previous day.
    public var extraNeedPerStrainPoint: TimeInterval = 38
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
        let usable = samples.filter { !(hasStages && $0.stage == .unspecified) }

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
        let efficiency = inBed > 0 ? min(1, asleep / inBed) : 0
        let restorative = hasStages ? min(1, (deep + rem) / asleep / targetRestorativeShare) : 0.75
        let interruptionScore = max(0, 1 - Double(interruptions) / 8)

        let weighted: Double
        if let consistency {
            weighted = 0.45 * durationScore + 0.15 * efficiency + 0.2 * restorative + 0.05 * interruptionScore
                + 0.15 * Double(consistency) / 100
        } else {
            weighted = 0.5 * durationScore + 0.2 * efficiency + 0.2 * restorative + 0.1 * interruptionScore
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
        guard nights.count >= 4 else { return nil }
        // Minutes from noon, so 11 pm and 1 am are close together.
        func minutesFromNoon(_ date: Date) -> Double {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            return (minutes - 720 + 1440).truncatingRemainder(dividingBy: 1440)
        }
        let bed = spread(nights.map { minutesFromNoon($0.bedtime) })
        let wake = spread(nights.map { minutesFromNoon($0.wake) })
        let average = (bed + wake) / 2
        let score = 100 * (1 - (average - 20) / 100)
        return Int(min(100, max(0, score)).rounded())
    }

    /// Typical bed/wake spread in minutes, for display.
    public static func spreadMinutes(_ nights: [Night], calendar: Calendar = .current) -> Double? {
        guard nights.count >= 4, let score = score(nights, calendar: calendar) else { return nil }
        return 20 + (100 - Double(score))
    }

    static func spread(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
