import Foundation

/// Heart-rate recovery after exercise: how far heart rate falls in the first
/// one and two minutes after a workout ends.
///
/// A slow fall after a maximal exercise test predicted mortality in patients
/// referred for testing (Cole et al., NEJM 1999;341:1351-7: ≤12 bpm at one
/// minute after a symptom-limited test, 2,428 patients, mean age 57, adjusted
/// RR 2.0; abstract checked on PubMed November 2026); there's no validated
/// cut-off for everyday workouts. So the app grades nothing: it measures only
/// after a sustained hard effort (`isSustainedHardEffort`), never after
/// lifting, and compares the drop with your own earlier values (`usualRange`).
public enum HeartRateRecovery {
    public struct Result: Sendable, Equatable {
        public var peak: Double
        public var oneMinuteDrop: Double
        public var twoMinuteDrop: Double?

        public init(peak: Double, oneMinuteDrop: Double, twoMinuteDrop: Double?) {
            self.peak = peak
            self.oneMinuteDrop = oneMinuteDrop
            self.twoMinuteDrop = twoMinuteDrop
        }
    }

    /// - Parameters:
    ///   - samples: heart rate around the end of the workout (per-minute or raw).
    ///   - end: when the workout ended.
    public static func measure(_ samples: [HeartRateSample], workoutEnd end: Date) -> Result? {
        let lastMinutes = samples.filter { $0.date >= end.addingTimeInterval(-180) && $0.date <= end }
        guard let peak = lastMinutes.map(\.bpm).max() else { return nil }
        guard let one = value(near: end.addingTimeInterval(60), in: samples) else { return nil }
        let drop = peak - one
        guard drop >= 0 else { return nil }
        let two = value(near: end.addingTimeInterval(120), in: samples).map { peak - $0 }
        return Result(peak: peak, oneMinuteDrop: drop, twoMinuteDrop: two.flatMap { $0 >= 0 ? $0 : nil })
    }

    /// Average of the samples within 30 s of `time`.
    static func value(near time: Date, in samples: [HeartRateSample]) -> Double? {
        let close = samples.filter { abs($0.date.timeIntervalSince(time)) <= 30 }.map(\.bpm)
        guard !close.isEmpty else { return nil }
        return close.reduce(0, +) / Double(close.count)
    }

    // MARK: Which workouts count

    /// Share of heart-rate reserve a workout must hold (app's choice, from the
    /// evidence audit M3): 80% of reserve is the top of ACSM's vigorous band, so
    /// the "peak" is a real effort, as at the end of an exercise test, and not a
    /// rest between sets.
    public static let hardEffortReserve = 0.8
    /// Minutes at or above `hardEffortReserve` the workout must hold (app's
    /// choice: intervals or a hard run reach it, an easy session doesn't).
    public static let hardEffortMinutes = 3.0
    /// Shortest workout that is measured (as before).
    public static let minimumWorkoutMinutes = 10.0

    /// True when `samples` inside `workout` hold at least `hardEffortMinutes`
    /// at `hardEffortReserve` of heart-rate reserve or more. Readings are
    /// weighted by the gap to the next one, as for intensity minutes.
    public static func isSustainedHardEffort(_ samples: [HeartRateSample], during workout: DateInterval, profile: HeartRateProfile) -> Bool {
        let inside = samples.filter { workout.contains($0.date) }.sorted { $0.date < $1.date }
        var minutes = 0.0
        for (sample, weight) in zip(inside, HeartRateMinutes.weights(inside)) where profile.reserveFraction(for: sample.bpm) >= hardEffortReserve {
            minutes += weight
        }
        return minutes >= hardEffortMinutes
    }

    /// One measurement per qualifying workout: at least `minimumWorkoutMinutes`
    /// long, not overlapping a lifting window (a logged gym session or a watch
    /// strength workout), and a sustained hard effort. Workouts ending within 5
    /// minutes of one already measured are skipped (a logged session and the
    /// watch's own workout often end together).
    public static func measureHardEfforts(
        _ heartRate: [HeartRateSample],
        workouts: [DateInterval],
        lifting: [DateInterval],
        profile: HeartRateProfile
    ) -> [(date: Date, result: Result)] {
        var measured: [(date: Date, result: Result)] = []
        for workout in workouts.sorted(by: { $0.end < $1.end }) where workout.duration >= minimumWorkoutMinutes * 60 {
            if let last = measured.last, abs(last.date.timeIntervalSince(workout.end)) < 5 * 60 { continue }
            guard !lifting.contains(where: { $0.start < workout.end && workout.start < $0.end }) else { continue }
            guard isSustainedHardEffort(heartRate, during: workout, profile: profile) else { continue }
            let nearby = heartRate.filter { $0.date >= workout.end.addingTimeInterval(-180) && $0.date <= workout.end.addingTimeInterval(150) }
            if let result = measure(nearby, workoutEnd: workout.end) {
                measured.append((workout.end, result))
            }
        }
        return measured
    }

    // MARK: Your own range

    /// Earlier measurements needed before a usual range shows (app's choice).
    public static let minimumForUsualRange = 3

    /// Your usual one-minute drop: the middle half (25th-75th percentile) of
    /// the earlier values, rounded to whole bpm, or nil with fewer than
    /// `minimumForUsualRange`. The middle half is the app's choice; no study
    /// sets a personal band for this.
    public static func usualRange(_ earlier: [Double]) -> ClosedRange<Double>? {
        guard earlier.count >= minimumForUsualRange else { return nil }
        let sorted = earlier.sorted()
        func quantile(_ p: Double) -> Double {
            let position = p * Double(sorted.count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(sorted.count - 1, lower + 1)
            return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
        }
        return quantile(0.25).rounded()...quantile(0.75).rounded()
    }

    /// "Your usual 17-24", or how many more hard sessions until there is one.
    public static func usualText(_ earlier: [Double]) -> String {
        guard let range = usualRange(earlier) else {
            let more = minimumForUsualRange - earlier.count
            return "Your usual range shows after \(more) more hard session\(more == 1 ? "" : "s")"
        }
        let low = Int(range.lowerBound), high = Int(range.upperBound)
        return low == high ? "Your usual \(low)" : "Your usual \(low)-\(high)"
    }

    /// The footnote wherever the drop shows.
    public static let clinicalNote = "Clinical cut-offs come from maximal treadmill tests and don't apply to everyday workouts."
}

/// Moderate and vigorous minutes from heart rate (ACSM: 40-59 % and 60 %+ of
/// heart-rate reserve). Vigorous minutes count double toward the WHO goal of
/// 150 a week, as on Garmin watches.
public enum IntensityMinutes {
    /// Moderate minutes one vigorous minute counts as toward the 150-minute
    /// total. 2 is the WHO guideline's own exchange rate: 150-300 moderate or
    /// 75-150 vigorous minutes a week (Bull et al., Br J Sports Med 2020).
    /// Wrist-accelerometer data from 73,485 UK Biobank adults put it nearer 4
    /// for all-cause mortality (4.1), 7.8 for cardiovascular death and 9.4 for
    /// type 2 diabetes (Biswas et al., Nat Commun 2025;16:8315; abstract
    /// checked on PubMed, PMID 41168243), but that is one
    /// cohort, observational, with intensity classed by a wrist accelerometer
    /// rather than heart rate as here. So the constant stays at the
    /// guideline's 2, which can only undercount hard work, and vigorous
    /// minutes get a line of their own (`vigorousLine`, HealthFloors.swift).
    public static let vigorousWeight = 2

    public struct Result: Sendable, Equatable {
        public var moderate: Int
        public var vigorous: Int
        public var total: Int { moderate + IntensityMinutes.vigorousWeight * vigorous }

        public init(moderate: Int, vigorous: Int) {
            self.moderate = moderate
            self.vigorous = vigorous
        }
    }

    public static let weeklyGoal = 150

    /// Heart rate outside lifting: logged gym sessions and watch strength
    /// workouts are left out. WHO 2020 sets aerobic activity and
    /// muscle-strengthening as separate recommendations (Bull et al., Br J
    /// Sports Med 2020), and the mortality curves behind the 150-minute floor
    /// are for aerobic activity (Garcia 2023, Lee 2022), while strength has its
    /// own (Momma 2022). Heart rate between sets often passes 40% of reserve,
    /// so counting it would show the floor met with no cardio at all
    /// (evidence-audit-2026-11.md M1).
    public static func outsideLifting(_ samples: [HeartRateSample], lifting: [DateInterval]) -> [HeartRateSample] {
        guard !lifting.isEmpty else { return samples }
        return samples.filter { sample in !lifting.contains { $0.contains(sample.date) } }
    }

    /// The label wherever these minutes show, and the line that says why.
    public static let title = "Cardio minutes (outside lifting)"
    public static let liftingNote = "Heart rate during lifting isn't counted: the 150-minute guideline is for aerobic exercise, and lifting has its own guideline."

    /// - Parameter samples: heart rate, ideally one value per minute. Sparser
    /// data (a watch sampling every 1-2 minutes) is weighted by the gap to the
    /// next reading, up to 2 minutes, as in `StrainCalculator`.
    public static func count(_ samples: [HeartRateSample], profile: HeartRateProfile) -> Result {
        let sorted = samples.sorted { $0.date < $1.date }
        var moderate = 0.0
        var vigorous = 0.0
        for (sample, minutes) in zip(sorted, HeartRateMinutes.weights(sorted)) {
            let fraction = profile.reserveFraction(for: sample.bpm)
            if fraction >= 0.6 {
                vigorous += minutes
            } else if fraction >= 0.4 {
                moderate += minutes
            }
        }
        return Result(moderate: Int(moderate.rounded()), vigorous: Int(vigorous.rounded()))
    }
}

/// How many minutes each heart-rate reading stands for.
enum HeartRateMinutes {
    /// For readings sorted by time: the gap to the next reading in minutes,
    /// capped at `cap` (gaps longer than `maxGap` count only as one minute).
    /// Denser-than-minute data counts its share, so it isn't double counted.
    /// The last reading counts as one minute.
    static func weights(_ sorted: [HeartRateSample], cap: Double = 2, maxGap: TimeInterval = 10 * 60) -> [Double] {
        guard !sorted.isEmpty else { return [] }
        var result: [Double] = []
        result.reserveCapacity(sorted.count)
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            result.append(gap > maxGap ? 1 : min(cap, max(0, gap) / 60))
        }
        result.append(1)
        return result
    }
}

/// Heart rate while asleep.
public enum SleepingHeartRate {
    public struct Result: Sendable, Equatable {
        public var average: Double
        /// Lowest 5-minute average, which is less noisy than the single lowest reading.
        public var lowest: Double

        public init(average: Double, lowest: Double) {
            self.average = average
            self.lowest = lowest
        }
    }

    public static func measure(_ samples: [HeartRateSample], during sleep: [SleepSample]) -> Result? {
        let asleep = sleep.filter { $0.stage.isAsleep }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        let values = samples
            .filter { sample in asleep.contains { $0.contains(sample.date) } }
            .sorted { $0.date < $1.date }
            .map(\.bpm)
        guard values.count >= 10 else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        let window = min(5, values.count)
        var lowest = Double.infinity
        for start in 0...(values.count - window) {
            let slice = values[start..<(start + window)]
            lowest = min(lowest, slice.reduce(0, +) / Double(window))
        }
        return Result(average: average, lowest: lowest)
    }
}
