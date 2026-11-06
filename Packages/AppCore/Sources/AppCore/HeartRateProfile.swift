import Foundation

/// The person-specific numbers needed to turn heart rate into effort.
public struct HeartRateProfile: Sendable, Equatable {
    public var age: Int
    public var sex: BiologicalSex
    public var restingHeartRate: Double
    /// Set this if the user knows their real max (from a test or a hard race).
    public var maxHeartRateOverride: Double?

    public init(
        age: Int,
        sex: BiologicalSex,
        restingHeartRate: Double,
        maxHeartRateOverride: Double? = nil
    ) {
        self.age = age
        self.sex = sex
        self.restingHeartRate = restingHeartRate
        self.maxHeartRateOverride = maxHeartRateOverride
    }

    /// Tanaka et al. (J Am Coll Cardiol 2001): 208 - 0.7 x age, the same for
    /// men and women. More accurate than 220 - age for adults; later equations
    /// agree within a few bpm (Gellish et al. 2007: 207 - 0.7 x age; Nes et al.
    /// 2013: 211 - 0.64 x age). Any formula is off by ~10 bpm (1 SD) for an
    /// individual, so a measured or learned max (`ObservedMaxHeartRate`) wins.
    public var maxHeartRate: Double {
        if let maxHeartRateOverride, maxHeartRateOverride > restingHeartRate + 20 {
            return maxHeartRateOverride
        }
        return 208 - 0.7 * Double(age)
    }

    /// Fraction of heart-rate reserve (Karvonen et al. 1957), clamped to 0...1.
    /// Reserve tracks oxygen-uptake reserve better than % of max does (Swain &
    /// Leutholtz 1997), which is why ACSM sets intensity in %HRR.
    public func reserveFraction(for bpm: Double) -> Double {
        let reserve = maxHeartRate - restingHeartRate
        guard reserve > 0 else { return 0 }
        return min(1, max(0, (bpm - restingHeartRate) / reserve))
    }

    /// Zone 1-5 by heart-rate reserve: 50-60, 60-70, 70-80, 80-90, 90-100 %.
    /// Returns nil below zone 1. Same bands as Edwards' (1993) five zones but on
    /// reserve, not % of max, to match the TRIMP. Display only: strain uses the
    /// continuous TRIMP weighting, not zone counts.
    public func zone(for bpm: Double) -> Int? {
        let fraction = reserveFraction(for: bpm)
        guard fraction >= 0.5 else { return nil }
        return min(5, Int((fraction - 0.5) / 0.1) + 1)
    }

    /// The light band below zone 1: 30-50% of reserve. 30% is where strain
    /// starts counting (`StrainCalculator.minimumReserveFraction`, the bottom
    /// of ACSM's "light" 30-39% HRR) and 50% is zone 1's floor; ACSM calls
    /// 40-59% "moderate" (ACSM's Guidelines for Exercise Testing and
    /// Prescription, 10th ed. 2018), so the upper half of this band is
    /// moderate effort. Lifting often sits here between sets.
    public static let lightBand = 0.3..<0.5

    /// True for heart rate in `lightBand`.
    public func isLight(_ bpm: Double) -> Bool {
        Self.lightBand.contains(reserveFraction(for: bpm))
    }

    /// Heart rate at a fraction of reserve (for band edges in bpm).
    public func heartRate(atReserve fraction: Double) -> Double {
        restingHeartRate + fraction * (maxHeartRate - restingHeartRate)
    }

    /// Minutes of light (30-50% HRR) heart rate in a series, counted the way
    /// `StrainCalculator` counts zone minutes: each reading stands for the
    /// time to the next, at most 2 minutes, and gaps over 10 minutes count
    /// for nothing.
    public func lightMinutes(_ heartRate: [HeartRateSample], maxSampleGap: TimeInterval = 10 * 60,
                             maxMinutesPerSample: Double = 2) -> Double {
        let samples = heartRate.sorted { $0.date < $1.date }
        var total = 0.0
        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= maxSampleGap, isLight(current.bpm) else { continue }
            total += min(gap / 60, maxMinutesPerSample)
        }
        return total
    }
}
