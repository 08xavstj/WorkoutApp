import Foundation

/// The movement prep before the first lift, as a fixed, predictable list of
/// steps: one timed "raise", then rep-based drills chosen by the first two
/// movement patterns of the session, and (full tier only) a few explosive
/// reps. Separate from `WarmUp` (the ramp sets of the lift itself), which
/// follows it and is the part with the best evidence.
///
/// Evidence, honestly weighted (docs/research/workout-science.md):
/// - Ramp sets of the lift are what the data support (Ribeiro et al., Int J
///   Environ Res Public Health 2020, trial; Ribeiro, Neves et al.,
///   Motricidade 2021, systematic review). They are `WarmUp`, not this type.
/// - A general raise works mainly by muscle temperature, and the benefit
///   decays within minutes once you stop (McGowan, Pyne, Thompson & Rattray,
///   Sports Med 2015, narrative review), so the raise is short (90–180 s) and
///   the whole routine must not push the first working set out past ~10 min.
/// - Dynamic drills: +1.3% acute performance, range-of-motion gains fade
///   within ~30 min, no injury data (Behm, Blazevich, Kay & McHugh, Appl
///   Physiol Nutr Metab 2016, systematic review / CSEP position stand). So the
///   drills are a range-of-motion and rehearsal step, and the UI says the
///   benefit is small and mostly feel-based.
/// - Explosive reps before the first set: post-activation performance
///   enhancement, small effects (Seitz & Haff, Sports Med 2016, meta-analysis,
///   47 studies; mechanisms in Blazevich & Babault, Front Physiol 2019).
/// - The Raise → Activate/Mobilise → Potentiate order is RAMP (Jeffreys,
///   Professional Strength and Conditioning 2007): coaching practice, not a
///   tested lifting protocol. The drill choices are coaching practice too
///   (RAMP, NSCA dynamic warm-up); none is a tested optimum.
public enum WarmUpRoutine {
    /// How much warm-up the user wants before lifting (Settings › Training).
    /// Remembered per `WorkoutFocus` as well (`UserSettings.warmUpTierByFocus`).
    public enum Tier: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Nothing before the first set, not even ramp sets.
        case off
        /// Ramp sets of the first lift only: the default, and the best-evidenced
        /// option (Ribeiro 2020, 2021).
        case rampOnly
        /// 90 s raise + 2–3 drills for the first two lifts, then ramp sets. ~5 min.
        case short
        /// 180 s raise + activate and mobilise drills + explosive reps, then ramp
        /// sets. ~8–10 min. For cold gyms, first session of the day, strength goals.
        case full

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .off: "Off"
            case .rampOnly: "Ramp sets only"
            case .short: "Short"
            case .full: "Full"
            }
        }

        /// The time hint shown beside the label in pickers; empty when none.
        public var detail: String {
            switch self {
            case .off, .rampOnly: ""
            case .short: "5 min"
            case .full: "8–10 min"
            }
        }

        /// "Short · 5 min"
        public var menuLabel: String { detail.isEmpty ? label : "\(label) · \(detail)" }

        /// True for the tiers that add movement steps before the ramp sets.
        public var hasSteps: Bool { self == .short || self == .full }

        /// Minutes the movement steps take, for the planner's session length
        /// (`WorkoutPlanner.estimatedMinutes(_:style:warmUpMinutes:)`). Ramp
        /// sets are counted there separately. Short ≈ 4 min, full ≈ 8–10 min of
        /// planned steps (`make`; tested ≤ 5 and ≤ 10).
        public var plannedMinutes: Int {
            switch self {
            case .off, .rampOnly: 0
            case .short: 4
            case .full: 9
            }
        }
    }

    /// Legacy planner default for `warmUpMinutes` (the old 6-min routine), kept
    /// so `WorkoutPlanner`'s default arguments compile. Callers should pass
    /// `tier.plannedMinutes`: the default tier has no movement steps.
    public static let defaultMinutes = 6

    /// How much of a step to do. Only the raise is timed; drills are counted,
    /// so the UI never counts down over a rep-based movement.
    public enum Dose: Codable, Sendable, Equatable, Hashable {
        case reps(Int, perSide: Bool)
        case seconds(Int)

        /// "10 each side", "15" or "90 s".
        public var text: String {
            switch self {
            case let .reps(count, perSide): perSide ? "\(count) each side" : "\(count)"
            case let .seconds(seconds): "\(seconds) s"
            }
        }

        /// The countdown length for a timed step; nil for reps.
        public var seconds: Int? {
            if case let .seconds(value) = self { return value }
            return nil
        }

        /// For the routine's total time. Rep drills are planned at about 3 s a
        /// rep (both sides counted): a planning estimate, not a measurement.
        public var estimatedSeconds: Int {
            switch self {
            case let .reps(count, perSide): count * 3 * (perSide ? 2 : 1)
            case let .seconds(seconds): seconds
            }
        }
    }

    /// Where a step sits in RAMP (Jeffreys 2007).
    public enum Phase: String, Codable, Sendable, Hashable {
        /// Temperature: the only timed step.
        case raise
        /// Activate and mobilise drills: range of motion and rehearsal.
        case prep
        /// A few explosive reps before the first working set (full tier).
        case potentiate
    }

    /// One step of the routine: what, how much, one cue, one reason.
    public struct Step: Codable, Sendable, Equatable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var dose: Dose
        /// One line on how to do it.
        public var cue: String
        /// One line on what it is for, in plain words ("Opens the hips for squat depth").
        public var why: String
        /// Equipment it needs, if any (`GymProfile.has`).
        public var requires: EquipmentKind?
        public var phase: Phase

        public init(id: String, name: String, dose: Dose, cue: String, why: String,
                    requires: EquipmentKind? = nil, phase: Phase = .prep) {
            self.id = id
            self.name = name
            self.dose = dose
            self.cue = cue
            self.why = why
            self.requires = requires
            self.phase = phase
        }

        public var isTimed: Bool { dose.seconds != nil }
        public var estimatedSeconds: Int { dose.estimatedSeconds }
    }

    /// The whole routine for a session. Empty for the off and ramp-only tiers.
    public struct Routine: Codable, Sendable, Equatable {
        public var tier: Tier
        public var steps: [Step]
        /// The movement patterns the drills were chosen for (first lifts first).
        public var slots: [MovementSlot]

        public init(tier: Tier, steps: [Step], slots: [MovementSlot]) {
            self.tier = tier
            self.steps = steps
            self.slots = slots
        }

        public var isEmpty: Bool { steps.isEmpty }
        public var totalSeconds: Int { steps.reduce(0) { $0 + $1.estimatedSeconds } }
        /// Rounded up, so "4 min" never undersells the time.
        public var minutes: Int { (totalSeconds + 59) / 60 }
        /// "Warm-up · 4 min"
        public var title: String { "Warm-up · \(minutes) min" }
        /// Step names after the raise, for a one-line summary.
        public var drillNames: [String] { steps.filter { $0.phase != .raise }.map(\.name) }
    }

    // MARK: Raise

    /// 90 s raise for the short tier, 180 s for full. Muscle temperature is
    /// the main mechanism of a general warm-up and decays once you stop
    /// (McGowan et al. 2015; a 20-min bike raise improved leg-press 1RM in
    /// Abad et al., J Strength Cond Res 2011, but that is a 1RM test and far
    /// too long here). 90–180 s is coaching practice (RAMP), kept short so the
    /// first working set stays inside the decay window.
    public static let shortRaiseSeconds = 90
    public static let fullRaiseSeconds = 180

    /// `EquipmentKind` has no cardio machine, so the raise is on foot; the cue
    /// says to use a bike or rower if there is one.
    public static func raise(seconds: Int) -> Step {
        Step(
            id: "raise", name: "Raise your temperature", dose: .seconds(seconds),
            cue: "March or jog in place, or an easy bike or rower if there is one. Swing your arms.",
            why: "Warm muscle contracts faster and feels looser; the gain fades in minutes, so keep moving.",
            phase: .raise
        )
    }

    // MARK: Drills by movement pattern

    /// The patterns drills are keyed by. Isolation slots map to the nearest
    /// pattern; `core` has none.
    public enum Pattern: String, Sendable, Hashable, CaseIterable {
        case squat, hinge, lunge, horizontalPress, verticalPress, pull

        public init?(slot: MovementSlot) {
            switch slot {
            case .squat, .legExtension, .calves: self = .squat
            case .hinge, .legCurl, .hipThrust: self = .hinge
            case .singleLeg: self = .lunge
            case .horizontalPress, .inclinePress, .chestFly, .triceps: self = .horizontalPress
            case .verticalPress, .lateralRaise: self = .verticalPress
            case .verticalPull, .horizontalRow, .rearDelt, .biceps, .hammerCurl: self = .pull
            case .core: return nil
            }
        }

        var isLowerBody: Bool { self == .squat || self == .hinge || self == .lunge }
    }

    // All drills are coaching practice (RAMP, Jeffreys 2007; NSCA dynamic
    // warm-up; Fitbod-style libraries). Range-of-motion effects last under
    // ~30 min (Behm 2016). The "why" lines claim range of motion, rehearsal
    // or activation, never strength or injury prevention.

    static let ankleRocks = Step(
        id: "ankleRocks", name: "Half-kneeling ankle rocks", dose: .reps(8, perSide: true),
        cue: "Front knee over your toes, heel down, rock forward and back.",
        why: "Frees the ankle so you can squat to depth with your heels down."
    )
    static let bodyweightSquat = Step(
        id: "bodyweightSquat", name: "Bodyweight squat", dose: .reps(10, perSide: false),
        cue: "Slow down, quick up, full depth. Add a light dumbbell as a goblet if you like.",
        why: "Rehearses the squat groove. Light reps alone don't prime strength; the ramp sets do that."
    )
    static let gluteBridge = Step(
        id: "gluteBridge", name: "Glute bridge", dose: .reps(10, perSide: false),
        cue: "Ribs down, push through your heels, squeeze for a second at the top.",
        why: "Wakes up the glutes that drive hip extension in squats and hinges."
    )
    static let hipHinge = Step(
        id: "hipHinge", name: "Hip hinge", dose: .reps(10, perSide: false),
        cue: "Hands on hips or a dowel down your back. Push the hips back, flat back, until the hamstrings pull.",
        why: "Rehearses the hinge so the first deadlift or RDL finds the right shape."
    )
    static let ninetyNinety = Step(
        id: "ninetyNinety", name: "90/90 hip switch", dose: .reps(5, perSide: true),
        cue: "Sit with both knees bent at 90°, switch sides without using your hands.",
        why: "Opens the hips for squat depth."
    )
    static let lateralBandWalk = Step(
        id: "lateralBandWalk", name: "Lateral band walk", dose: .reps(10, perSide: true),
        cue: "Band above the knees, slight squat, step sideways and keep tension.",
        why: "Wakes up the hip muscles that keep your knees tracking in squats and lunges.",
        requires: .bands
    )
    static let hipFlexorRock = Step(
        id: "hipFlexorRock", name: "Half-kneeling hip-flexor rock", dose: .reps(8, perSide: true),
        cue: "Tall torso, drive the back knee forward, don't arch the lower back.",
        why: "Lengthens the front of the hip so the back leg can drop into a lunge."
    )
    static let lateralLunge = Step(
        id: "lateralLunge", name: "Lateral lunge", dose: .reps(5, perSide: true),
        cue: "Step wide, sit into one hip, other leg straight, chest up.",
        why: "Loosens the inner thigh and rehearses single-leg control."
    )
    static let bandPullApart = Step(
        id: "bandPullApart", name: "Band pull-aparts", dose: .reps(15, perSide: false),
        cue: "Arms straight at chest height, pull the band to your sternum, slow return.",
        why: "Switches on the upper back that keeps your shoulders stable under a bar.",
        requires: .bands
    )
    static let scapPushUp = Step(
        id: "scapPushUp", name: "Scapular push-ups", dose: .reps(10, perSide: false),
        cue: "Plank, elbows locked. Let the blades pinch, then push the floor away.",
        why: "Teaches the shoulder blades to move before you load them."
    )
    static let armCrossovers = Step(
        id: "armCrossovers", name: "Arm crossovers", dose: .reps(15, perSide: false),
        cue: "Swing both arms wide, then across your chest, a little bigger each time.",
        why: "Moves the shoulders and chest through their range before pressing."
    )
    static let shoulderCircles = Step(
        id: "shoulderCircles", name: "Shoulder circles", dose: .reps(5, perSide: true),
        cue: "One arm, slow full circle each way, ribs down, no shrug.",
        why: "Takes the shoulder through its full range before going overhead."
    )
    static let wallSlides = Step(
        id: "wallSlides", name: "Wall slides", dose: .reps(8, perSide: false),
        cue: "Back and forearms on the wall, slide the arms up without the ribs flaring.",
        why: "Gets the upper back and shoulders ready for a straight overhead line."
    )
    static let scapPullUp = Step(
        id: "scapPullUp", name: "Scap pull-ups", dose: .reps(8, perSide: false),
        cue: "Hang from the bar, pull your shoulder blades down without bending your elbows.",
        why: "Switches on the lats and lower traps that start every pull.",
        requires: .pullUpBar
    )
    static let bandRow = Step(
        id: "bandRow", name: "Band rows", dose: .reps(15, perSide: false),
        cue: "Band around a post, pull the elbows back and squeeze the blades together.",
        why: "Switches on the upper back before you row or pull.",
        requires: .bands
    )
    static let thoracicRotation = Step(
        id: "thoracicRotation", name: "Thoracic rotations", dose: .reps(6, perSide: true),
        cue: "All fours, hand behind your head, turn your chest to the ceiling.",
        why: "Loosens the upper back so you can stay tall in rows and hinges."
    )
    static let facePull = Step(
        id: "facePull", name: "Face pulls", dose: .reps(12, perSide: false),
        cue: "Rope at eye height, pull to your face, elbows high, pause.",
        why: "Wakes up the rear shoulders that steady a press or pull.",
        requires: .cable
    )

    /// Drills for a pattern, as ordered groups of alternatives: each group
    /// yields the first step the gym supports. `short` is used by both tiers,
    /// `fullExtra` only by the full tier (its activate/mobilise additions).
    static func drills(for pattern: Pattern) -> (short: [[Step]], fullExtra: [[Step]]) {
        switch pattern {
        case .squat:
            ([[ankleRocks], [bodyweightSquat]], [[gluteBridge], [ninetyNinety], [lateralBandWalk]])
        case .hinge:
            ([[hipHinge], [gluteBridge]], [[thoracicRotation], [lateralBandWalk]])
        case .lunge:
            ([[hipFlexorRock], [lateralLunge]], [[gluteBridge], [lateralBandWalk]])
        case .horizontalPress:
            ([[bandPullApart, armCrossovers], [scapPushUp]], [[facePull, thoracicRotation], [armCrossovers]])
        case .verticalPress:
            ([[shoulderCircles], [bandPullApart, wallSlides]], [[wallSlides], [thoracicRotation]])
        case .pull:
            ([[scapPullUp, bandRow, armCrossovers], [thoracicRotation]], [[bandPullApart, facePull], [hipHinge]])
        }
    }

    /// 2–3 explosive reps right before the first working set (after the ramp
    /// sets): PAPE, small effect (Seitz & Haff 2016, meta-analysis; Blazevich
    /// & Babault 2019). Jump squats for a lower-body first lift, plyo
    /// push-ups otherwise (plyo push-ups raised bench power at 70% 1RM,
    /// Krzysztofik et al., J Hum Kinet 2020).
    static func potentiate(lowerBody: Bool) -> Step {
        Step(
            id: "potentiate",
            name: lowerBody ? "Jump squats" : "Plyo push-ups",
            dose: .reps(3, perSide: false),
            cue: lowerBody
                ? "After your ramp sets: 3 fast jumps, land soft, full rest before set 1."
                : "After your ramp sets: 3 explosive push-ups (or a medicine-ball chest pass), then rest.",
            why: "A few fast reps prime the nervous system for the first heavy set. The effect is small.",
            phase: .potentiate
        )
    }

    /// Used when the session's exercises map to no pattern (a free-form
    /// session of custom exercises): a general lower + upper pair.
    static let fallbackSlots: [MovementSlot] = [.squat, .horizontalPress]

    // MARK: Make

    /// The movement slots of a plan's exercises, in order, for `make`.
    public static func slots(of plan: PlannedWorkout) -> [MovementSlot] {
        plan.exercises.compactMap { ExerciseCatalog.slot(for: $0.exerciseID) }
    }

    /// A routine for a planned session: its first lifts drive the drills.
    public static func make(tier: Tier, for plan: PlannedWorkout, gym: GymProfile) -> Routine {
        make(tier: tier, firstSlots: slots(of: plan), gym: gym)
    }

    /// Compatibility for the old builder call: the short routine for a plan.
    /// Prefer `make(tier:for:gym:)` with the user's tier.
    @available(*, deprecated, message: "Use make(tier:for:gym:) with UserSettings.warmUpTier(for:)")
    public static func make(for plan: PlannedWorkout, gym: GymProfile) -> Routine {
        make(tier: .short, for: plan, gym: gym)
    }

    /// The routine for a tier and the session's movement slots in order.
    /// Short: 90 s raise + 2–3 drills for the first two patterns. Full: 180 s
    /// raise + those drills + activate/mobilise additions + explosive reps.
    /// Off and ramp-only: no steps (the ramp sets are `WarmUp`).
    public static func make(tier: Tier, firstSlots: [MovementSlot], gym: GymProfile) -> Routine {
        guard tier.hasSteps else { return Routine(tier: tier, steps: [], slots: firstSlots) }
        let patterns = firstPatterns(in: firstSlots)
        let pick: ([Step]) -> Step? = { group in group.first { $0.requires.map { gym.has($0) } ?? true } }

        var steps = [raise(seconds: tier == .full ? fullRaiseSeconds : shortRaiseSeconds)]
        var used: Set<String> = [steps[0].id]
        func add(_ step: Step?) {
            guard let step, !used.contains(step.id) else { return }
            used.insert(step.id)
            steps.append(step)
        }

        let lists = patterns.map { drills(for: $0) }
        // Short: first drill of each pattern, then the first pattern's second
        // drill, so a single-pattern day gets 2 and a mixed day 3 (§4 table).
        for list in lists { add(list.short.first.flatMap(pick)) }
        if patterns.count == 1 {
            for group in lists[0].short.dropFirst() { add(pick(group)) }
        } else if let second = lists[0].short.dropFirst().first {
            add(pick(second))
        }
        if tier == .full {
            // Activate and mobilise additions, first pattern first.
            for list in lists {
                for group in list.fullExtra { add(pick(group)) }
            }
            // Second pattern's remaining short drill, if there is room.
            if lists.count > 1, let second = lists[1].short.dropFirst().first { add(pick(second)) }
            add(potentiate(lowerBody: patterns.first?.isLowerBody ?? true))
        }
        return Routine(tier: tier, steps: steps, slots: firstSlots)
    }

    /// The first two distinct patterns, compound lifts first; a general pair
    /// when nothing maps.
    static func firstPatterns(in slots: [MovementSlot]) -> [Pattern] {
        let ordered = slots.filter(\.isCompound) + slots.filter { !$0.isCompound }
        var result: [Pattern] = []
        for slot in ordered {
            guard let pattern = Pattern(slot: slot), !result.contains(pattern) else { continue }
            result.append(pattern)
            if result.count == 2 { break }
        }
        if result.isEmpty { result = fallbackSlots.compactMap(Pattern.init(slot:)) }
        return result
    }
}
