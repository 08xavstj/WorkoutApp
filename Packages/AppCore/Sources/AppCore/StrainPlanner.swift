import Foundation

/// Answers "how far am I from today's strain target, and what would close the gap?"
public struct StrainPlanner: Sendable {
    public var calculator = StrainCalculator()

    public init() {}

    public enum Status: Sendable, Equatable {
        case below(remaining: Double)
        case inRange
        case above
    }

    public func status(current: Double, target: ClosedRange<Double>) -> Status {
        if current < target.lowerBound { return .below(remaining: ((target.lowerBound - current) * 10).rounded() / 10) }
        if current > target.upperBound { return .above }
        return .inRange
    }

    /// Strain added by extra load, given today's strain so far (the curve flattens near 100).
    public func strainGain(current: Double, addedLoad: Double) -> Double {
        let base = calculator.load(forStrain: current)
        let gain = calculator.strain(forLoad: base + max(0, addedLoad)) - current
        return max(0, (gain * 10).rounded() / 10)
    }

    /// Expected load of a gym session.
    public func liftingLoad(minutes: Double, rpe: Double) -> Double {
        min(10, max(1, rpe)) * min(minutes, 180) * calculator.rpeToTrimp
    }

    /// Expected load of steady cardio at a fraction of heart-rate reserve (0.65 ≈ zone 2).
    public func cardioLoad(minutes: Double, reserveFraction: Double, profile: HeartRateProfile) -> Double {
        let bpm = profile.restingHeartRate + reserveFraction * (profile.maxHeartRate - profile.restingHeartRate)
        return calculator.trimp(minutes: minutes, bpm: bpm, profile: profile)
    }

    public struct Option: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable { case strength, cardio }
        public var id: String
        public var kind: Kind
        public var title: String
        public var detail: String
        public var minutes: Double
        public var load: Double
        /// Filled in by `rank`.
        public var gain: Double = 0
        public var landsAt: Double = 0

        public init(id: String, kind: Kind, title: String, detail: String, minutes: Double, load: Double) {
            self.id = id
            self.kind = kind
            self.title = title
            self.detail = detail
            self.minutes = minutes
            self.load = load
        }
    }

    /// Orders options by how well they land in the target range: options that end
    /// inside the range come first (shortest first), then ones that fall short
    /// (biggest gain first), then ones that overshoot.
    public func rank(_ options: [Option], current: Double, target: ClosedRange<Double>) -> [Option] {
        let scored = options.map { option -> Option in
            var option = option
            option.gain = strainGain(current: current, addedLoad: option.load)
            option.landsAt = ((current + option.gain) * 10).rounded() / 10
            return option
        }
        func group(_ option: Option) -> Int {
            if target.contains(option.landsAt) { return 0 }
            return option.landsAt < target.lowerBound ? 1 : 2
        }
        return scored.sorted { a, b in
            let (ga, gb) = (group(a), group(b))
            if ga != gb { return ga < gb }
            switch ga {
            case 0: return a.minutes < b.minutes
            case 1: return a.gain > b.gain
            default: return a.gain < b.gain
            }
        }
    }
}
