import Foundation

/// A short movement-based warm-up before the first lift, matched to the
/// muscles the session trains. Separate from `WarmUp` (the ramp sets of the
/// lift itself), which follows it.
///
/// Why movement, not long stretches: static holds of 60 s or more per muscle
/// cut strength by about 5% and explosive performance by about 2% right after
/// (Simic, Sarabon & Markovic, Scand J Med Sci Sports 2013, meta-analysis of
/// 104 studies); holds under 60 s have little effect, under 30 s about -1%
/// (Kay & Blazevich, Med Sci Sports Exerc 2012, systematic review of 106
/// studies). Dynamic movement gives a small-to-moderate gain within minutes
/// (Behm et al., Appl Physiol Nutr Metab 2016, review). A general warm-up
/// that raises muscle temperature improved performance in 79% of measures
/// (Fradkin, Zazryn & Smoliga, J Strength Cond Res 2010, meta-analysis;
/// mechanisms in McGowan et al., Sports Med 2015). The order follows RAMP:
/// Raise, Activate and Mobilise, then Potentiate (Jeffreys, Professional
/// Strength and Conditioning 2007); the potentiate step is the lift's own
/// ramp sets. Injury evidence is weak: stretching doesn't lower injury rates
/// (Lauersen et al., Br J Sports Med 2014, meta-analysis, RR 0.96) and
/// dynamic warm-ups have no injury data (Behm 2016), so the UI claims only
/// a performance benefit. See docs/research/workout-science.md.
public enum WarmUpRoutine {
    /// One movement in the routine. Timed, with a rep hint for the cue.
    public struct Movement: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// How long to do it for.
        public var seconds: Int
        /// e.g. "10 each side"; nil for a timed step like marching.
        public var reps: String?
        /// One line on how to do it.
        public var cue: String
        /// The session muscles it prepares.
        public var preps: Set<MuscleGroup>
        /// A held stretch. False for every default; `make` never returns one.
        public var isStatic: Bool
        /// Equipment it needs, if any (`GymProfile.has`).
        public var requires: EquipmentKind?

        public init(id: String, name: String, seconds: Int, reps: String? = nil, cue: String,
                    preps: Set<MuscleGroup>, isStatic: Bool = false, requires: EquipmentKind? = nil) {
            self.id = id
            self.name = name
            self.seconds = seconds
            self.reps = reps
            self.cue = cue
            self.preps = preps
            self.isStatic = isStatic
            self.requires = requires
        }
    }

    public struct Routine: Codable, Sendable, Equatable {
        /// The raise step first, then mobilise/activate movements, large muscles first.
        public var movements: [Movement]
        /// The muscle groups the routine was built for.
        public var groups: Set<MuscleGroup>

        public init(movements: [Movement], groups: Set<MuscleGroup>) {
            self.movements = movements
            self.groups = groups
        }

        public var totalSeconds: Int { movements.reduce(0) { $0 + $1.seconds } }
        /// Rounded up, so "6 min" never undersells the time.
        public var minutes: Int { (totalSeconds + 59) / 60 }
        /// "Warm-up · 6 min"
        public var title: String { "Warm-up · \(minutes) min" }
    }

    /// The default length offered in the builder.
    public static let defaultMinutes = 6
    public static let minutesRange = 5...8
    /// Two minutes of easy whole-body movement to raise muscle temperature
    /// (RAMP "Raise", Jeffreys 2007; temperature effects in McGowan 2015).
    public static let raiseSeconds = 120

    /// Groups large to small, so the biggest muscles are warm first.
    static let groupOrder: [MuscleGroup] = [.legs, .pull, .push, .core]

    /// The raise step. No gym has a bike in `EquipmentKind`, so it's always on foot.
    public static let raise = Movement(
        id: "raise", name: "March or jog in place", seconds: raiseSeconds,
        cue: "Easy pace, swing your arms. You should be a little warmer, not out of breath.",
        preps: [.legs, .pull, .push, .core]
    )

    /// Every movement the routine can pick from, best first within a group.
    /// All dynamic (`isStatic == false`).
    public static let catalog: [Movement] = [
        // Legs
        Movement(id: "legSwings", name: "Leg swings", seconds: 40, reps: "10 each leg",
                 cue: "Hold something, swing one leg forward and back, then side to side.", preps: [.legs]),
        Movement(id: "bodyweightSquats", name: "Bodyweight squats", seconds: 40, reps: "10",
                 cue: "Slow down, quick up. Sit as deep as you comfortably can.", preps: [.legs]),
        Movement(id: "hipHinges", name: "Hip hinges", seconds: 30, reps: "10",
                 cue: "Hands on hips, push them back with a flat back until you feel the hamstrings.", preps: [.legs]),
        Movement(id: "walkingLunges", name: "Walking lunges", seconds: 40, reps: "5 each side",
                 cue: "Long step, back knee near the floor, stand tall between steps.", preps: [.legs, .core]),
        Movement(id: "ankleRocks", name: "Ankle rocks", seconds: 30, reps: "10 each side",
                 cue: "Half kneeling, rock the front knee over your toes, heel down.", preps: [.legs]),
        // Pull
        Movement(id: "scapPullUps", name: "Scap pull-ups", seconds: 30, reps: "8",
                 cue: "Hang from the bar, pull your shoulder blades down without bending your arms.",
                 preps: [.pull], requires: .pullUpBar),
        Movement(id: "bandRows", name: "Band rows", seconds: 40, reps: "15",
                 cue: "Band around a post, pull elbows back and squeeze the blades together.",
                 preps: [.pull], requires: .bands),
        Movement(id: "thoracicRotations", name: "Thoracic rotations", seconds: 40, reps: "8 each side",
                 cue: "On all fours, hand behind your head, turn your chest to the ceiling.", preps: [.pull, .push, .core]),
        Movement(id: "armCrossovers", name: "Arm crossovers", seconds: 30, reps: "15",
                 cue: "Swing both arms wide, then across your chest, a little higher each time.", preps: [.pull, .push]),
        // Push
        Movement(id: "armCircles", name: "Arm circles", seconds: 30, reps: "10 each way",
                 cue: "Small circles growing to big ones, forward then backward.", preps: [.push]),
        Movement(id: "bandPullAparts", name: "Band pull-aparts", seconds: 40, reps: "15",
                 cue: "Arms straight at chest height, pull the band to your chest, control the return.",
                 preps: [.push, .pull], requires: .bands),
        Movement(id: "scapPushUps", name: "Scapular push-ups", seconds: 40, reps: "10",
                 cue: "Plank, arms straight. Let the blades pinch, then push the floor away.", preps: [.push, .core]),
        Movement(id: "catCow", name: "Cat-cow", seconds: 40, reps: "8",
                 cue: "On all fours, round your back on the breath out, arch it on the breath in.", preps: [.push, .core]),
        // Core
        Movement(id: "deadBug", name: "Dead bug", seconds: 30, reps: "6 each side",
                 cue: "On your back, lower one arm and the other leg, ribs down.", preps: [.core]),
    ]

    /// A routine for a planned session, from its focus and chosen exercises.
    public static func make(for plan: PlannedWorkout, minutes: Int = defaultMinutes, gym: GymProfile) -> Routine {
        make(focus: plan.focus, exerciseIDs: plan.exercises.map(\.exerciseID), minutes: minutes, gym: gym)
    }

    /// A routine for a focus plus the exercises (catalog IDs) it ended up with.
    public static func make(focus: WorkoutFocus?, exerciseIDs: [String], minutes: Int = defaultMinutes, gym: GymProfile) -> Routine {
        var groups = Set(exerciseIDs.compactMap { ExerciseCatalog.slot(for: $0)?.muscleGroup })
        if let focus { groups.formUnion(focus.slots.map(\.muscleGroup)) }
        if groups.isEmpty { groups = [.legs, .pull, .push, .core] }
        return make(groups: groups, minutes: minutes, gym: gym)
    }

    /// Two minutes of raise, then movements that prep `groups`, one per group
    /// in turn (large first) so a short routine still covers every muscle,
    /// until the time is used. Never longer than `minutes`; never a static hold.
    public static func make(groups: Set<MuscleGroup>, minutes: Int = defaultMinutes, gym: GymProfile) -> Routine {
        let clamped = min(max(minutes, minutesRange.lowerBound), minutesRange.upperBound)
        var budget = clamped * 60 - raiseSeconds
        let usable = catalog.filter { movement in
            !movement.isStatic
                && !movement.preps.isDisjoint(with: groups)
                && (movement.requires.map { gym.has($0) } ?? true)
        }
        // Round robin across the session's groups, largest first.
        let order = groupOrder.filter { groups.contains($0) }
        var remaining: [MuscleGroup: [Movement]] = [:]
        for group in order {
            remaining[group] = usable.filter { $0.preps.contains(group) }
        }
        var chosen: [Movement] = []
        var progressed = true
        while progressed, budget > 0 {
            progressed = false
            for group in order {
                guard var list = remaining[group], !list.isEmpty else { continue }
                let next = list.removeFirst()
                remaining[group] = list
                // A movement that preps two groups is picked once.
                for other in order where other != group {
                    remaining[other]?.removeAll { $0.id == next.id }
                }
                guard next.seconds <= budget else { continue }
                chosen.append(next)
                budget -= next.seconds
                progressed = true
            }
        }
        // Stable: keeps the pick order inside a group, groups large to small.
        let rank: (Movement) -> Int = { movement in
            order.firstIndex { movement.preps.contains($0) } ?? order.count
        }
        let ordered = chosen.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
        return Routine(movements: [raise] + ordered, groups: groups)
    }
}
