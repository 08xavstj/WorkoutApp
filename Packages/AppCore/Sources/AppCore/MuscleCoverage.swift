import Foundation

/// Picks the next session by what the week still owes each muscle, so that by
/// the week's end every tracked muscle has landed in the productive 10-20 hard
/// sets (the green zone of the Hard sets this week card and the muscle map).
///
/// - **The zone.** About 10-20 hard sets a muscle a week builds the most
///   muscle for most people (Schoenfeld, Ogborn & Krieger, J Sports Sci 2017,
///   dose-response meta-analysis); more keeps adding a little with diminishing
///   returns (Pelland et al., Sports Med 2026; helper muscles counted as half a
///   set, as there). Under 10 is where the app says "low", so 10 is the gap
///   this picker closes (`MuscleRecovery.State.volume`).
/// - **Any day will do.** For equal weekly volume, how the sets are spread
///   across the week makes little difference to muscle growth (Schoenfeld,
///   Grgic & Krieger, J Sports Sci 2019, volume-equated frequency
///   meta-analysis), so the week's total per muscle is the target and the
///   day's focus is free to move.
/// - **Not a tired muscle.** A muscle still recovering from a hard session
///   (`MuscleRecovery.State.status` below fresh) earns no credit, and a focus
///   whose main muscles are fatigued is skipped: the 48-72 h recovery window
///   behind `MuscleRecovery` (Bishop et al. 2008; Schoenfeld et al. 2016).
/// - **"Close the biggest gap" is the app's rule.** The research gives the
///   weekly target, not a way to choose the day's session. The greedy rule
///   here (score each focus by the lagging sets it would supply, take the
///   highest, and the usual rotation on a tie) is an app choice, not a tested
///   protocol, and the UI says "to catch up" rather than promising an outcome.
public enum MuscleCoverage {
    /// The green zone (`MuscleRecovery.State.volume == .productive`).
    public static let productiveRange: ClosedRange<Double> = 10...20

    /// Muscles the picker tracks: the ones on the Hard sets this week card,
    /// without abs (core work is in several sessions already and its set
    /// counts are the noisiest in the library).
    public static let tracked: [Muscle] = [
        .chest, .shoulders, .triceps, .lats, .middleBack, .biceps,
        .quadriceps, .hamstrings, .glutes, .calves,
    ]

    /// Hard sets one session is taken to hold, for sharing out across its
    /// muscles: about six exercises of three sets (`WorkoutPlanner.baseSets`).
    static let sessionSets = 18.0

    public struct Result: Sendable, Equatable {
        /// The session that closes the most of this week's gap.
        public var focus: WorkoutFocus
        /// Tracked muscles under 10 sets this week, biggest gap first.
        public var lagging: [Muscle]
        /// Movements to give a place in the session for the lagging muscles
        /// it trains (`WorkoutPlanner.plan(prioritySlots:)`). On the week's
        /// last session this can include a movement from outside the focus.
        public var prioritySlots: [MovementSlot]
        /// Why this focus, for the plan's rationale ("to catch hamstrings and
        /// biceps up to this week's 10-20 sets"). Nil when nothing lags.
        public var reason: String?
    }

    // MARK: Sets this week

    /// Hard sets per muscle since `weekStart` (helper muscles count half, easy
    /// sets under RPE 7 count 0.6, as in `MuscleRecovery.evaluate`; a drop,
    /// rest-pause or myo-rep set counts its `volumeCredit`, 1.5), so the
    /// gap is this calendar week's, not a rolling seven days'.
    public static func setsThisWeek(_ sets: [MuscleRecovery.WorkSet], weekStart: Date, now: Date = .now) -> [Muscle: Double] {
        var weekly: [Muscle: Double] = [:]
        for set in sets where set.date >= weekStart && set.date <= now {
            let effort = ((set.rpe ?? 8) >= 7 ? 1.0 : 0.6) * set.volumeCredit
            for name in set.primary {
                if let muscle = Muscle(rawValue: name.lowercased()) { weekly[muscle, default: 0] += effort }
            }
            for name in set.secondary {
                if let muscle = Muscle(rawValue: name.lowercased()) { weekly[muscle, default: 0] += effort * 0.5 }
            }
        }
        return weekly
    }

    // MARK: What a movement trains

    /// The muscle a movement loads most, then its helpers (half credit), in
    /// `Muscle` terms (`ExerciseCatalog.muscles(for:)` has the plain words).
    public static func muscles(for slot: MovementSlot) -> (primary: Muscle, secondary: [Muscle]) {
        switch slot {
        case .horizontalPress, .inclinePress: (.chest, [.shoulders, .triceps])
        case .chestFly: (.chest, [])
        case .verticalPress: (.shoulders, [.triceps])
        case .lateralRaise: (.shoulders, [])
        case .rearDelt: (.shoulders, [.middleBack])
        case .triceps: (.triceps, [])
        case .verticalPull: (.lats, [.biceps, .middleBack])
        // Rows are upper-back work first (mid traps, rhomboids, rear delts), with the lats
        // helping: the same split the exercise library logs them with, so a planned row
        // set and a logged one count for the same muscle. (They used to plan as lats and
        // log as upper back, so the lat target could never be met and pull days were
        // capped as if rows and pulldowns were one muscle.)
        case .horizontalRow: (.middleBack, [.lats, .biceps])
        case .biceps: (.biceps, [])
        case .hammerCurl: (.biceps, [.forearms])
        case .squat, .singleLeg: (.quadriceps, [.glutes])
        case .legExtension: (.quadriceps, [])
        case .hinge: (.hamstrings, [.glutes, .lowerBack])
        case .legCurl: (.hamstrings, [])
        case .calves: (.calves, [])
        case .core: (.abdominals, [])
        case .hipThrust: (.glutes, [.hamstrings])
        }
    }

    /// How much of a session each muscle gets, as weights (primary 1, helper
    /// 0.5) summed over the focus's movements.
    static func coverage(of focus: WorkoutFocus) -> [Muscle: Double] {
        var weights: [Muscle: Double] = [:]
        for slot in focus.slots {
            let trained = muscles(for: slot)
            weights[trained.primary, default: 0] += 1
            for helper in trained.secondary { weights[helper, default: 0] += 0.5 }
        }
        return weights
    }

    // MARK: The pick

    /// The focus that closes the most of this week's gap, or nil when no
    /// tracked, recovered muscle is under 10 sets (then the usual rotation is
    /// the right call and there is nothing to say).
    ///
    /// - Parameters:
    ///   - setsThisWeek: hard sets per muscle since Monday (`setsThisWeek`).
    ///   - states: recovery per muscle (`MuscleRecovery.evaluate`); a muscle
    ///     that isn't fresh earns no credit, a fatigued main muscle rules a
    ///     focus out.
    ///   - sessionsLeft: sessions still to come this week, today's included.
    ///     With one left, a lagging muscle outside the focus gets a priority
    ///     movement so the week still reaches it.
    ///   - preferred: the rotation's suggestion, which wins ties.
    ///   - candidates: focuses the plan can use (default all six).
    public static func suggest(
        setsThisWeek: [Muscle: Double],
        states: [Muscle: MuscleRecovery.State] = [:],
        sessionsLeft: Int,
        preferred: WorkoutFocus? = nil,
        candidates: [WorkoutFocus] = WorkoutFocus.allCases
    ) -> Result? {
        guard sessionsLeft > 0 else { return nil }
        // Sets still owed by each tracked muscle that is ready to train.
        var gaps: [Muscle: Double] = [:]
        for muscle in tracked {
            let gap = productiveRange.lowerBound - (setsThisWeek[muscle] ?? 0)
            let ready = states[muscle].map { $0.status == .fresh } ?? true
            if gap > 0, ready { gaps[muscle] = gap }
        }
        guard !gaps.isEmpty else { return nil }

        let order = ([preferred].compactMap { $0 } + candidates)
        var best: (focus: WorkoutFocus, score: Double)?
        for focus in order where candidates.contains(focus) {
            let weights = coverage(of: focus)
            // A focus built around a fatigued muscle is out.
            let fatigued = weights.contains { muscle, weight in
                weight >= 1 && states[muscle]?.status == .fatigued
            }
            if fatigued { continue }
            // Shares are over tracked muscles only: core, forearm and lower-back
            // work isn't held against a focus, so a fresh week ties and the
            // rotation decides.
            let total = tracked.reduce(0.0) { $0 + (weights[$1] ?? 0) }
            guard total > 0 else { continue }
            // Each muscle's share of the session's sets, counted only up to its gap.
            let score = gaps.reduce(0.0) { sum, entry in
                sum + min(entry.value, sessionSets * (weights[entry.key] ?? 0) / total)
            }
            if score > (best?.score ?? 0) + 0.001 { best = (focus, score) }
        }
        guard let best else { return nil }

        let lagging = gaps.keys.sorted { a, b in
            let (gapA, gapB) = (gaps[a] ?? 0, gaps[b] ?? 0)
            if gapA != gapB { return gapA > gapB }
            return (tracked.firstIndex(of: a) ?? 0) < (tracked.firstIndex(of: b) ?? 0)
        }
        let covered = coverage(of: best.focus)
        let laggingInFocus = lagging.filter { (covered[$0] ?? 0) > 0 }
        var slots: [MovementSlot] = []
        for muscle in laggingInFocus where slots.count < 2 {
            if let found = slot(for: muscle, in: best.focus), !slots.contains(found) { slots.append(found) }
        }
        // The last session of the week reaches one lagging muscle the focus doesn't.
        if sessionsLeft == 1, let outside = lagging.first(where: { (covered[$0] ?? 0) == 0 }),
           let extra = slot(for: outside, in: nil) {
            slots.append(extra)
        }
        let named = (laggingInFocus.isEmpty ? Array(lagging.prefix(2)) : Array(laggingInFocus.prefix(2))).map { $0.name.lowercased() }
        let reason = "to catch \(named.joined(separator: " and ")) up to this week's 10-20 hard sets"
        return Result(focus: best.focus, lagging: lagging, prioritySlots: slots, reason: reason)
    }

    /// The movement to add for a muscle: a single-joint one inside the focus
    /// first (the compound lifts are already at the front of the session),
    /// then any movement in the focus, then, with `focus` nil, the best
    /// single-joint movement anywhere.
    static func slot(for muscle: Muscle, in focus: WorkoutFocus?) -> MovementSlot? {
        let pool = focus.map { $0.slots + $0.extraSlots(variant: 0) } ?? MovementSlot.allCases
        let matching = pool.filter { muscles(for: $0).primary == muscle }
        return matching.first { !$0.isCompound } ?? matching.first
    }
}
