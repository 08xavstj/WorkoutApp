import Foundation

/// Daily strain on a 0-21 scale, built from two kinds of load:
///
/// 1. **Cardio load** - Banister TRIMP from heart rate (time x intensity,
///    weighted exponentially so hard minutes count much more than easy ones).
/// 2. **Lifting load** - session RPE x minutes (Foster's sRPE). Heart rate badly
///    undercounts lifting because you rest between sets, so a gym session counts
///    as whichever is higher: its heart-rate load or its RPE load.
///
/// Load maps onto 0-21 with a saturating curve, so going from 18 to 19 takes much
/// more work than going from 8 to 9.
public struct StrainCalculator: Sendable {
    /// Load at which strain reaches ~63% of the scale (about 13.3).
    public var saturationLoad: Double = 126
    /// Converts sRPE units into TRIMP-equivalent units. Calibrated so a hard
    /// hour of lifting (RPE 8) lands close to a moderate hour-long run.
    public var rpeToTrimp: Double = 0.25
    /// RPE assumed when a session has neither a session RPE nor set RPEs.
    public var defaultRPE: Double = 6.5
    /// Gaps between heart-rate samples longer than this are not counted.
    public var maxSampleGap: TimeInterval = 10 * 60
    /// Heart rate below this fraction of reserve is treated as resting.
    public var minimumReserveFraction: Double = 0.2

    public init() {}

    public struct Result: Sendable, Equatable {
        public var strain: Double
        public var totalLoad: Double
        public var cardioLoad: Double
        public var liftingLoad: Double
        /// Minutes in zones 1-5 (index 0 = zone 1).
        public var zoneMinutes: [Double]

        public static let empty = Result(strain: 0, totalLoad: 0, cardioLoad: 0, liftingLoad: 0, zoneMinutes: [0, 0, 0, 0, 0])
    }

    public func dailyStrain(
        heartRate: [HeartRateSample],
        strengthSessions: [StrengthSessionSummary],
        profile: HeartRateProfile
    ) -> Result {
        let samples = heartRate.sorted { $0.date < $1.date }
        var cardioLoad = 0.0
        var sessionHeartRateLoad = Array(repeating: 0.0, count: strengthSessions.count)
        var zoneMinutes = [0.0, 0.0, 0.0, 0.0, 0.0]

        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= maxSampleGap else { continue }
            let minutes = gap / 60
            let load = trimp(minutes: minutes, bpm: current.bpm, profile: profile)

            if let index = strengthSessions.firstIndex(where: { $0.contains(current.date) }) {
                sessionHeartRateLoad[index] += load
            } else {
                cardioLoad += load
            }
            if let zone = profile.zone(for: current.bpm) {
                zoneMinutes[zone - 1] += minutes
            }
        }

        var liftingLoad = 0.0
        for (index, session) in strengthSessions.enumerated() {
            liftingLoad += max(sessionHeartRateLoad[index], rpeLoad(for: session))
        }

        let total = cardioLoad + liftingLoad
        return Result(
            strain: strain(forLoad: total),
            totalLoad: total,
            cardioLoad: cardioLoad,
            liftingLoad: liftingLoad,
            zoneMinutes: zoneMinutes
        )
    }

    /// Banister TRIMP for a stretch of time at one heart rate.
    public func trimp(minutes: Double, bpm: Double, profile: HeartRateProfile) -> Double {
        let fraction = profile.reserveFraction(for: bpm)
        guard fraction >= minimumReserveFraction else { return 0 }
        let (a, b) = profile.sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        return minutes * fraction * a * exp(b * fraction)
    }

    /// Session-RPE load for a gym session, in TRIMP-equivalent units.
    public func rpeLoad(for session: StrengthSessionSummary) -> Double {
        let rpe: Double
        if let sessionRPE = session.sessionRPE {
            rpe = sessionRPE
        } else if !session.setRPEs.isEmpty {
            rpe = session.setRPEs.reduce(0, +) / Double(session.setRPEs.count)
        } else {
            rpe = defaultRPE
        }
        let minutes = min(session.duration / 60, 180)
        return min(10, max(1, rpe)) * minutes * rpeToTrimp
    }

    /// Strain is a percentage: 0 (no effort) to 100 (as hard as a day gets).
    public static let maximum = 100.0

    public func strain(forLoad load: Double) -> Double {
        guard load > 0 else { return 0 }
        let raw = Self.maximum * (1 - exp(-load / saturationLoad))
        return (raw * 10).rounded() / 10
    }

    /// Inverse of `strain(forLoad:)`: how much load reaches a given strain.
    public func load(forStrain strain: Double) -> Double {
        let clamped = min(Self.maximum - 0.5, max(0, strain))
        return -saturationLoad * log(1 - clamped / Self.maximum)
    }

    /// Suggested strain range for today, based on recovery (0-100).
    public static func targetStrain(forRecovery recovery: Int) -> ClosedRange<Double> {
        switch recovery {
        case ..<34: 20...45
        case 34..<67: 45...65
        default: 65...85
        }
    }
}
