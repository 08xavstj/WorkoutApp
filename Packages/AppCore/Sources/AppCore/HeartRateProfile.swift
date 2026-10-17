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

    /// Tanaka et al. (2001): 208 - 0.7 x age. More accurate than 220 - age for adults.
    public var maxHeartRate: Double {
        if let maxHeartRateOverride, maxHeartRateOverride > restingHeartRate + 20 {
            return maxHeartRateOverride
        }
        return 208 - 0.7 * Double(age)
    }

    /// Fraction of heart-rate reserve (Karvonen), clamped to 0...1.
    public func reserveFraction(for bpm: Double) -> Double {
        let reserve = maxHeartRate - restingHeartRate
        guard reserve > 0 else { return 0 }
        return min(1, max(0, (bpm - restingHeartRate) / reserve))
    }

    /// Zone 1-5 by heart-rate reserve: 50-60, 60-70, 70-80, 80-90, 90-100 %.
    /// Returns nil below zone 1.
    public func zone(for bpm: Double) -> Int? {
        let fraction = reserveFraction(for: bpm)
        guard fraction >= 0.5 else { return nil }
        return min(5, Int((fraction - 0.5) / 0.1) + 1)
    }
}
