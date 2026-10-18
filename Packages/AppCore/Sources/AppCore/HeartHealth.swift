import Foundation

/// Heart-rate recovery after exercise: how far heart rate falls in the first
/// one and two minutes after a workout ends. A bigger drop is better; under
/// 12 bpm at one minute is linked with poorer fitness (Cole et al., NEJM 1999).
public enum HeartRateRecovery {
    public struct Result: Sendable, Equatable {
        public var peak: Double
        public var oneMinuteDrop: Double
        public var twoMinuteDrop: Double?
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

    public static func label(oneMinuteDrop drop: Double) -> String {
        switch drop {
        case ..<12: "Low"
        case 12..<20: "Fair"
        case 20..<30: "Good"
        default: "Excellent"
        }
    }
}

/// A stress estimate from heart rate alone, 0-100. It averages how far heart
/// rate sits above resting during waking hours, leaving out workouts.
/// Garmin's own stress score uses HRV, which Garmin doesn't share with Apple
/// Health, so this is an approximation and is labelled as one.
public enum StressEstimate {
    public struct Result: Sendable, Equatable {
        public var score: Int
        public var minutes: Int
        /// Share of measured minutes in each band: rest, low, medium, high.
        public var bands: [Double]
    }

    /// Fraction of heart-rate reserve that counts as maximum stress when not exercising.
    static let fullScale = 0.35

    public static func estimate(
        _ samples: [HeartRateSample],
        profile: HeartRateProfile,
        excluding windows: [DateInterval] = [],
        wakingHours: Range<Int> = 7..<22,
        calendar: Calendar = .current
    ) -> Result? {
        var scores: [Double] = []
        for sample in samples {
            let hour = calendar.component(.hour, from: sample.date)
            guard wakingHours.contains(hour), !windows.contains(where: { $0.contains(sample.date) }) else { continue }
            let elevation = profile.reserveFraction(for: sample.bpm)
            // Above zone 1 you're moving, not stressed.
            guard elevation < 0.5 else { continue }
            scores.append(min(1, elevation / fullScale) * 100)
        }
        guard scores.count >= 30 else { return nil }
        var bands = [0.0, 0, 0, 0]
        for score in scores {
            bands[band(for: score)] += 1
        }
        let total = Double(scores.count)
        let mean = scores.reduce(0, +) / total
        return Result(score: Int(mean.rounded()), minutes: scores.count, bands: bands.map { $0 / total })
    }

    /// 0-25 rest, 26-50 low, 51-75 medium, 76-100 high (the bands Garmin uses).
    static func band(for score: Double) -> Int {
        switch score {
        case ..<26: 0
        case ..<51: 1
        case ..<76: 2
        default: 3
        }
    }

    public static func label(for score: Int) -> String {
        ["Resting", "Low", "Medium", "High"][band(for: Double(score))]
    }
}

/// Moderate and vigorous minutes from heart rate (ACSM: 40-59 % and 60 %+ of
/// heart-rate reserve). Vigorous minutes count double toward the WHO goal of
/// 150 a week, as on Garmin watches.
public enum IntensityMinutes {
    public struct Result: Sendable, Equatable {
        public var moderate: Int
        public var vigorous: Int
        public var total: Int { moderate + 2 * vigorous }
    }

    public static let weeklyGoal = 150

    /// - Parameter samples: one heart-rate value per minute.
    public static func count(_ samples: [HeartRateSample], profile: HeartRateProfile) -> Result {
        var minutes = Set<Int>()
        var moderate = 0
        var vigorous = 0
        for sample in samples {
            // Count each clock minute once even if samples are denser.
            let minute = Int(sample.date.timeIntervalSince1970 / 60)
            guard minutes.insert(minute).inserted else { continue }
            let fraction = profile.reserveFraction(for: sample.bpm)
            if fraction >= 0.6 {
                vigorous += 1
            } else if fraction >= 0.4 {
                moderate += 1
            }
        }
        return Result(moderate: moderate, vigorous: vigorous)
    }
}

/// Heart rate while asleep.
public enum SleepingHeartRate {
    public struct Result: Sendable, Equatable {
        public var average: Double
        /// Lowest 5-minute average, which is less noisy than the single lowest reading.
        public var lowest: Double
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
