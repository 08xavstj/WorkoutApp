import Foundation

/// Daily strain as a percentage (0-100), built from two kinds of load:
///
/// 1. **Cardio load** - Banister TRIMP from heart rate (time x intensity,
///    weighted exponentially so hard minutes count much more than easy ones),
///    summed minute by minute.
/// 2. **Lifting load** - session RPE x minutes (Foster's sRPE). Heart rate badly
///    undercounts lifting (rest between sets; the pressor response isn't
///    metabolic work), so a gym session counts as whichever is higher: its
///    heart-rate load or its RPE load (Foster et al., J Strength Cond Res 2001).
///
/// Load maps onto 0-100% with a saturating curve, so going from 85% to 90% takes
/// much more work than going from 40% to 45%.
///
/// Calibration (30-year-old man, resting 60, max 187; figures recomputed
/// when the everyday taper and the 5.5 default rating came in):
/// - an hour's run at 75% of heart-rate reserve ≈ 62%;
/// - an hour of hard lifting (session RPE 8) ≈ 72%; 45 min at RPE 7 ≈ 56%;
///   an unrated hour (counted as session RPE 5.5) ≈ 58%;
/// - a brisk 60-minute walk at 35% of reserve ≈ 19% when it is a logged
///   workout or the watch counts its minutes as exercise, ≈ 10% when it is
///   only a raised heart rate (the taper below);
/// - five hours on your feet: 0% at 29% of reserve, ≈ 8% at 31%, ≈ 41% at
///   35%, ≈ 73% at 40% (it was 0% → 58% across the 30% line before the taper);
/// - a day of sitting, standing and light chores ≈ 0-10%.
///
/// See docs/research/strain-science.md for the evidence behind each choice.
public struct StrainCalculator: Sendable {
    /// Load at which strain reaches ~63% of the scale (≈ an hour at 75% of
    /// heart-rate reserve). The app's calibration choice; no study defines a
    /// 0-100 scale for TRIMP.
    public var saturationLoad: Double = 126
    /// Converts sRPE units (CR-10 x minutes) into Banister TRIMP units, so equal
    /// perceived effort counts the same whatever the mode. sRPE is meant to be
    /// comparable across exercise types (Foster et al. 2001; Haddad et al.,
    /// Front Neurosci 2017) and is valid for lifting (Day et al. 2004; Sweet et
    /// al. 2004, J Strength Cond Res). Banister TRIMP per sRPE unit in steady
    /// cardio is ≈ 0.28 at "moderate" (CR-10 3, ~50% of reserve), ≈ 0.34-0.40 at
    /// "hard" (CR-10 5-6, ~75%) and ≈ 0.42 at "very hard" (CR-10 7, ~87%), using
    /// ACSM's %HRR-to-RPE bands. 0.33 sits at the conservative end of "hard".
    /// (Was 0.25, which counted a lifting session as ~70% of a run that felt
    /// just as hard.)
    public var rpeToTrimp: Double = 0.33
    /// Session RPE assumed when a workout wasn't rated, shared by strain and
    /// calories (`EnergyCalculator.strengthKcal`) so one session isn't "6.5"
    /// in one place and "7" in the other. 5.5 is the app's choice inside what
    /// was measured: 30 minutes after a five-exercise session, men and women
    /// rated 15 reps at 50% of 1RM 3.3 ± 1.4, 10 reps at 70% 5.2 ± 1.5 and
    /// 4-5 reps at 90% 6.9 ± 1.4 on the CR-10 (Day, McGuigan, Brice & Foster,
    /// J Strength Cond Res 2004;18:353-358; n = 19, one set per exercise, so
    /// thin evidence for a multi-set session). (Was 6.5 here and 7 in energy.)
    public static let defaultSessionRPE = 5.5
    /// Session RPE assumed when the workout wasn't rated (`defaultSessionRPE`).
    public var defaultRPE: Double = StrainCalculator.defaultSessionRPE
    /// Gaps between heart-rate samples longer than this are not counted.
    public var maxSampleGap: TimeInterval = 10 * 60
    /// The most time one heart-rate reading stands for. Watches sample all-day
    /// heart rate every minute or two, so one high reading (e.g. standing up)
    /// shouldn't fill a long gap after it.
    public var maxMinutesPerSample: Double = 2
    /// Heart rate below this fraction of reserve doesn't add strain. 30% is
    /// the bottom of "light" intensity (30-39% HRR; ACSM's Guidelines for
    /// Exercise Testing and Prescription, 10th ed. 2018); below it is everyday living
    /// (sitting, standing, pottering), which Banister TRIMP wasn't designed
    /// to count and which would otherwise pile up over a whole day.
    public var minimumReserveFraction: Double = 0.3
    /// Outside logged workouts and Apple exercise minutes, a minute counts in
    /// full only from this fraction of reserve; between `minimumReserveFraction`
    /// and it, the minute's load is scaled in a straight line from 0 to 1
    /// (`everydayWeight`). Banister's TRIMP is defined for exercise bouts
    /// (Banister 1991), so where everyday heart rate stops being "exercise" is
    /// the app's choice, not a published cut-off; 40% is the bottom of ACSM's
    /// "moderate" band and the level already credited to an exercise minute
    /// (`movementReserveFraction`). The taper replaces a cliff: five hours on
    /// your feet read 0% at 93 bpm and 58% at 96 bpm for a 30-year-old with a
    /// resting rate of 55.
    public var fullCountReserveFraction: Double = 0.4
    /// Intensity credited to an Apple Watch exercise minute that heart rate
    /// didn't cover: 40% of reserve, the bottom of "moderate" (ACSM's
    /// Guidelines, 10th ed. 2018). Apple counts an exercise minute at about
    /// brisk-walk intensity; Abt et al. (JMIR Cardio 2018) tested it against
    /// 40% of VO₂ reserve. Outside workouts the watch saves heart rate only
    /// about every 5 minutes, so a short walk is mostly missed by the
    /// heart-rate sum. Exercise minutes are imprecise (roughly 20-30% error in
    /// validation studies), so this is a conservative floor, not a measurement.
    public var movementReserveFraction: Double = 0.4

    public init() {}

    public struct Result: Sendable, Equatable {
        public var strain: Double
        public var totalLoad: Double
        public var cardioLoad: Double
        public var liftingLoad: Double
        /// Minutes in zones 1-5 (index 0 = zone 1).
        public var zoneMinutes: [Double]
        /// Exercise minutes credited at `movementReserveFraction` because no
        /// heart-rate reading covered them (part of `cardioLoad`).
        public var movementMinutes: Double = 0

        public static let empty = Result(strain: 0, totalLoad: 0, cardioLoad: 0, liftingLoad: 0, zoneMinutes: [0, 0, 0, 0, 0])
    }

    /// - Parameters:
    ///   - movementMinutes: start times of Apple Watch exercise minutes. Each
    ///     one that no counted heart-rate reading covers, outside logged gym
    ///     sessions, adds one minute at `movementReserveFraction`.
    ///   - workouts: when other logged workouts ran (a run, a match: Apple
    ///     Health workouts that aren't one of `strengthSessions`). Heart rate
    ///     inside them, inside gym sessions and inside exercise minutes counts
    ///     from `minimumReserveFraction` as before; everywhere else it is
    ///     tapered up to `fullCountReserveFraction` (`everydayWeight`).
    public func dailyStrain(
        heartRate: [HeartRateSample],
        strengthSessions: [StrengthSessionSummary],
        profile: HeartRateProfile,
        movementMinutes: [Date] = [],
        workouts: [DateInterval] = []
    ) -> Result {
        let samples = heartRate.sorted { $0.date < $1.date }
        var cardioLoad = 0.0
        var sessionHeartRateLoad = Array(repeating: 0.0, count: strengthSessions.count)
        var zoneMinutes = [0.0, 0.0, 0.0, 0.0, 0.0]
        // Minutes (since 1970) already counted from heart rate.
        var covered = Set<Int>()
        let exerciseMinutes = Set(movementMinutes.map(Self.minuteIndex))

        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= maxSampleGap else { continue }
            let minutes = min(gap / 60, maxMinutesPerSample)
            var load = trimp(minutes: minutes, bpm: current.bpm, profile: profile)

            if let index = strengthSessions.firstIndex(where: { $0.contains(current.date) }) {
                sessionHeartRateLoad[index] += load
            } else {
                // Everyday heart rate (no workout, no exercise minute) is tapered in.
                let isExercise = workouts.contains { $0.contains(current.date) }
                    || exerciseMinutes.contains(Self.minuteIndex(current.date))
                if !isExercise {
                    load *= everydayWeight(reserveFraction: profile.reserveFraction(for: current.bpm))
                }
                cardioLoad += load
            }
            if load > 0 {
                let first = Self.minuteIndex(current.date)
                let last = Self.minuteIndex(current.date.addingTimeInterval(minutes * 60 - 1))
                covered.formUnion(first...max(first, last))
            }
            if let zone = profile.zone(for: current.bpm) {
                zoneMinutes[zone - 1] += minutes
            }
        }

        var credited = Set<Int>()
        for minute in movementMinutes {
            let index = Self.minuteIndex(minute)
            guard !covered.contains(index), !credited.contains(index),
                  !strengthSessions.contains(where: { $0.contains(minute) }) else { continue }
            credited.insert(index)
        }
        let movementMinuteCount = Double(credited.count)
        cardioLoad += trimp(minutes: movementMinuteCount, reserveFraction: movementReserveFraction, sex: profile.sex)

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
            zoneMinutes: zoneMinutes,
            movementMinutes: movementMinuteCount
        )
    }

    private static func minuteIndex(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }

    /// Banister TRIMP for a stretch of time at one heart rate: minutes x ΔHR x
    /// a·e^(b·ΔHR), with ΔHR the fraction of heart-rate reserve and a, b fitted
    /// to the typical blood-lactate curve of men (0.64, 1.92) and women (0.86,
    /// 1.67) (Banister 1991; Morton, Fitz-Clarke & Banister, J Appl Physiol 1990).
    /// Summing short stretches, rather than using a session's average heart
    /// rate, keeps intervals from being undercounted by the exponential.
    public func trimp(minutes: Double, bpm: Double, profile: HeartRateProfile) -> Double {
        trimp(minutes: minutes, reserveFraction: profile.reserveFraction(for: bpm), sex: profile.sex)
    }

    /// Banister TRIMP for `minutes` at a fraction of heart-rate reserve.
    public func trimp(minutes: Double, reserveFraction fraction: Double, sex: BiologicalSex) -> Double {
        guard minutes > 0, fraction >= minimumReserveFraction else { return 0 }
        let (a, b) = sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        return minutes * fraction * a * exp(b * fraction)
    }

    /// The share of a minute's Banister load that counts when the heart rate
    /// is raised outside any workout or exercise minute: 0 at
    /// `minimumReserveFraction` (30% of reserve), rising in a straight line to
    /// 1 at `fullCountReserveFraction` (40%). The app's choice (see
    /// `fullCountReserveFraction`); no study sets it.
    public func everydayWeight(reserveFraction fraction: Double) -> Double {
        let span = fullCountReserveFraction - minimumReserveFraction
        guard span > 0 else { return fraction >= minimumReserveFraction ? 1 : 0 }
        // Rounded so 40% (0.4 − 0.3 = 0.10000000000000003 in floating point) is exactly 1.
        let weight = ((fraction - minimumReserveFraction) / span * 1e9).rounded() / 1e9
        return min(1, max(0, weight))
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
