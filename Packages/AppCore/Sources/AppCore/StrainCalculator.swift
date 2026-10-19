import Foundation

/// Daily strain as a percentage (0-100), built from two kinds of load:
///
/// 1. **Cardio load** - Banister TRIMP from heart rate (time x intensity,
///    weighted exponentially so hard minutes count much more than easy ones).
/// 2. **Lifting load** - session RPE x minutes (Foster's sRPE). Heart rate badly
///    undercounts lifting because you rest between sets, so a gym session counts
///    as whichever is higher: its heart-rate load or its RPE load.
///
/// Load maps onto 0-100% with a saturating curve, so going from 85% to 90% takes
/// much more work than going from 40% to 45%.
///
/// Calibration (30-year-old man, resting 60, max 187):
/// - an hour's run at 75% of heart-rate reserve ≈ 62%;
/// - an hour of hard lifting (session RPE 8) ≈ 61%; 45 min at RPE 7 ≈ 46%;
/// - a brisk 60-minute walk (35% of reserve) ≈ 20%;
/// - a day of sitting, standing and light chores ≈ 0-10%.
public struct StrainCalculator: Sendable {
    /// Load at which strain reaches ~63% of the scale. This and `rpeToTrimp`
    /// are the app's calibration choices; no study defines them.
    public var saturationLoad: Double = 126
    /// Converts sRPE units into TRIMP-equivalent units. Calibrated so a hard
    /// hour of lifting (RPE 8) lands close to a moderate hour-long run.
    public var rpeToTrimp: Double = 0.25
    /// Session RPE assumed when the workout wasn't rated.
    public var defaultRPE: Double = 6.5
    /// Gaps between heart-rate samples longer than this are not counted.
    public var maxSampleGap: TimeInterval = 10 * 60
    /// The most time one heart-rate reading stands for. Watches sample all-day
    /// heart rate every minute or two, so one high reading (e.g. standing up)
    /// shouldn't fill a long gap after it.
    public var maxMinutesPerSample: Double = 2
    /// Heart rate below this fraction of reserve doesn't add strain. 30% is
    /// the bottom of "light" intensity (ACSM); below it is everyday living
    /// (sitting, standing, pottering), which Banister TRIMP wasn't designed
    /// to count and which would otherwise pile up over a whole day.
    public var minimumReserveFraction: Double = 0.3

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
            let minutes = min(gap / 60, maxMinutesPerSample)
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
        // Session RPE (Foster's CR-10 rating of the whole workout) only. Set RPEs
        // are a different scale (reps in reserve), so they don't stand in for it.
        let rpe = session.sessionRPE ?? defaultRPE
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

    /// Suggested strain range for a regular trainee, based on recovery (0-100).
    /// See `targetStrain(forRecovery:usualTrainingStrain:)` for the personal version.
    public static func targetStrain(forRecovery recovery: Int) -> ClosedRange<Double> {
        targetStrain(forRecovery: recovery, usualTrainingStrain: nil)
    }
}
