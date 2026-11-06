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
/// - Efficiency: 85% or more is good sleep quality and under 74% is poor
///   (Ohayon et al., Sleep Health 2017, National Sleep Foundation), so it gets
///   full marks from 85% and none at 70%.
/// - Deep + REM: weighted lightly because wrist trackers detect sleep well but
///   stage it poorly (Chinoy et al., Sleep 2021; Schyvens et al., Sleep Adv 2025).
///   The target falls with age, as deep and REM sleep do (Ohayon et al., Sleep
///   2004 meta-analysis): 40% under 40, 35% at 40-59, 30% from 60.
/// - Interruptions: awakenings over 5 minutes; 0-1 is good and 4 or more is
///   poor (Ohayon et al., Sleep Health 2017), so 0-1 → full marks, 2-3 → half,
///   4+ → none. Awake periods from several trackers are merged first.
/// - Regularity: the Sleep Regularity Index, mapped so 85+ is full marks and
///   50 or less is none (`regularityScore`), because the UK Biobank median is
///   about 81 and the bottom fifth starts near 72 (Windred et al., Sleep 2024).
public struct SleepCalculator: Sendable {
    public var baseSleepNeedHours: Double = 8
    /// Extra sleep needed per strain point (%) above 48 the previous day.
    /// Off (0) by default: there's no research for a load-based sleep need.
    public var extraNeedPerStrainPoint: TimeInterval = 0
    /// Deep + REM share of total sleep that earns full marks when `age` is
    /// unknown (the under-40 target; see `restorativeShareTarget(age:)`).
    public var targetRestorativeShare: Double = 0.40
    /// Your age, which scales the deep + REM target. Nil uses `targetRestorativeShare`.
    public var age: Int?
    /// Awake periods at least this long count as an interruption.
    public var minimumInterruption: TimeInterval = 5 * 60

    public init() {}

    /// Deep + REM share that earns full marks at an age. Normal adult N3 is
    /// about 13-23% and REM 20-25%, both falling with age (AASM; Ohayon et
    /// al., Sleep 2004); the steps are the app's.
    public static func restorativeShareTarget(age: Int) -> Double {
        switch age {
        case ..<40: 0.40
        case 40..<60: 0.35
        default: 0.30
        }
    }

    /// Interruption marks: 0-1 awakenings over 5 min is good, 4+ is poor
    /// (Ohayon et al., Sleep Health 2017, NSF sleep quality indicators).
    public static func interruptionScore(_ interruptions: Int) -> Double {
        switch interruptions {
        case ..<2: 1.0
        case 2...3: 0.5
        default: 0
        }
    }

    /// Regularity marks from the Sleep Regularity Index: (SRI − 50) / 35,
    /// clamped 0-1, so 85+ is full marks, 67.5 is half and 50 or under is none.
    /// SRI/100 would score almost everyone high: the UK Biobank median is 81
    /// and the bottom quintile begins near 72 (Windred et al., Sleep 2024).
    public static func regularityScore(sri: Int) -> Double {
        min(1, max(0, (Double(sri) - 50) / 35))
    }

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
        /// When the main sleep began and ended (asleep samples only; `bedtime`
        /// and `wakeTime` also span in-bed and awake samples around it).
        public var asleepStart: Date? = nil
        public var asleepEnd: Date? = nil
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

        func total(_ stage: SleepStage, in samples: [SleepSample]) -> TimeInterval {
            Self.unionDuration(samples.filter { $0.stage == stage }.map { ($0.start, $0.end) })
        }
        // Stages from one source only: two trackers stage the same night
        // differently, and a union of both would inflate every stage. The
        // source with the most staged time wins (the app's choice).
        let stageSamples = Self.mostStagedSource(usable)
        let deep = total(.deep, in: stageSamples)
        let rem = total(.rem, in: stageSamples)
        let core = total(.core, in: stageSamples)
        let stagedAsleep = deep + rem + core
        // Awake time and interruptions from every source, merged first, so an
        // awakening two trackers both saw counts once.
        let awakeIntervals = Self.mergedIntervals(usable.filter { $0.stage == .awake }.map { ($0.start, $0.end) })
        let awake = awakeIntervals.map { $0.1.timeIntervalSince($0.0) }.reduce(0, +)

        let bedtime = usable.map(\.start).min()
        let wakeTime = usable.map(\.end).max()
        var window = asleep
        if let bedtime, let wakeTime {
            window = wakeTime.timeIntervalSince(bedtime)
        }
        let inBed = max(asleep, total(.inBed, in: usable), window)

        let interruptions = awakeIntervals.filter { $0.1.timeIntervalSince($0.0) >= minimumInterruption }.count
        let need = sleepNeed(previousDayStrain: previousDayStrain)

        let durationScore = min(1, asleep / need)
        let rawEfficiency = inBed > 0 ? min(1, asleep / inBed) : 0
        // Full marks from 85%, none at 70% (Ohayon et al., Sleep Health 2017: ≥ 85% good, < 74% poor).
        let efficiency = min(1, max(0, (rawEfficiency - 0.70) / 0.15))
        let restorativeTarget = age.map(Self.restorativeShareTarget(age:)) ?? targetRestorativeShare
        let restorative = hasStages && stagedAsleep > 0 ? min(1, (deep + rem) / stagedAsleep / restorativeTarget) : 0.75
        let interruptionScore = Self.interruptionScore(interruptions)

        let weighted: Double
        if let consistency {
            let regularity = Self.regularityScore(sri: consistency)
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
            asleepStart: main.start,
            asleepEnd: main.end,
            consistency: consistency
        )
    }

    /// Total time covered by a set of intervals, counting overlaps once.
    static func unionDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        mergedIntervals(intervals).map { $0.1.timeIntervalSince($0.0) }.reduce(0, +)
    }

    /// Overlapping or touching intervals joined into one, in time order.
    static func mergedIntervals(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for (start, end) in sorted {
            if let last = merged.last, start <= last.1 {
                merged[merged.count - 1].1 = max(last.1, end)
            } else {
                merged.append((start, end))
            }
        }
        return merged
    }

    /// The samples from the source with the most core + deep + REM time
    /// (all samples when sources aren't known or only one recorded stages).
    static func mostStagedSource(_ samples: [SleepSample]) -> [SleepSample] {
        let stagedTypes: Set<SleepStage> = [.core, .deep, .rem]
        var stagedBySource: [String: TimeInterval] = [:]
        for sample in samples where stagedTypes.contains(sample.stage) {
            stagedBySource[sample.source ?? "", default: 0] += sample.duration
        }
        guard stagedBySource.count > 1,
              let best = stagedBySource.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key
        else { return samples }
        return samples.filter { ($0.source ?? "") == best }
    }
}

/// How much bed and wake times vary (their spread, as a circular SD), shown
/// next to the Sleep Regularity Index (`SleepRegularity`), which is what the
/// sleep score uses. `score` maps the spread to 0-100 (20 min or less = 100,
/// 2 h or more = 0) for callers without minute-level sleep data.
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
