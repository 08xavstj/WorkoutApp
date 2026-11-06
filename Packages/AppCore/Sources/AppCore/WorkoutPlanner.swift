import Foundation

/// Movement patterns the planner builds sessions from. Each has a list of
/// exercises (IDs from the bundled exercise library), best first; the planner
/// picks the first one your gym can do.
public enum MovementSlot: String, Codable, Sendable, CaseIterable {
    case horizontalPress, inclinePress, verticalPress, chestFly, lateralRaise, triceps
    case verticalPull, horizontalRow, rearDelt, biceps, hammerCurl
    case squat, hinge, singleLeg, legCurl, legExtension, calves, core

    public var isCompound: Bool {
        switch self {
        case .horizontalPress, .inclinePress, .verticalPress, .verticalPull, .horizontalRow, .squat, .hinge, .singleLeg: true
        default: false
        }
    }

    public var muscleGroup: MuscleGroup {
        switch self {
        case .horizontalPress, .inclinePress, .verticalPress, .chestFly, .lateralRaise, .triceps: .push
        case .verticalPull, .horizontalRow, .rearDelt, .biceps, .hammerCurl: .pull
        case .squat, .hinge, .singleLeg, .legCurl, .legExtension, .calves: .legs
        case .core: .core
        }
    }
}

public enum MuscleGroup: String, Codable, Sendable { case push, pull, legs, core }

public enum WorkoutFocus: String, Codable, Sendable, CaseIterable, Identifiable {
    case push, pull, legs, upper, lower, fullBody

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .push: "Push Day"
        case .pull: "Pull Day"
        case .legs: "Leg Day"
        case .upper: "Upper Body"
        case .lower: "Lower Body"
        case .fullBody: "Full Body"
        }
    }

    public var shortTitle: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .upper: "Upper"
        case .lower: "Lower"
        case .fullBody: "Full body"
        }
    }

    public var muscles: String {
        switch self {
        case .push: "Chest, shoulders, triceps"
        case .pull: "Back, rear delts, biceps"
        case .legs: "Quads, hamstrings, glutes, calves"
        case .upper: "Chest, back, shoulders, arms"
        case .lower: "Legs, glutes, core"
        case .fullBody: "Every major muscle group"
        }
    }

    /// Slots in priority order; shorter sessions use the first few. Multi-joint
    /// lifts come first: lifts done early in a session gain more strength,
    /// while muscle growth doesn't depend on order (Nunes et al., Eur J Sport
    /// Sci 2021; ACSM position stand, Med Sci Sports Exerc 2009).
    public var slots: [MovementSlot] {
        switch self {
        case .push: [.horizontalPress, .verticalPress, .inclinePress, .lateralRaise, .triceps, .chestFly]
        case .pull: [.verticalPull, .horizontalRow, .rearDelt, .biceps, .hammerCurl, .core]
        case .legs: [.squat, .hinge, .singleLeg, .legCurl, .legExtension, .calves]
        case .upper: [.horizontalPress, .horizontalRow, .verticalPress, .verticalPull, .biceps, .triceps]
        case .lower: [.squat, .hinge, .singleLeg, .legCurl, .calves, .core]
        case .fullBody: [.squat, .horizontalPress, .horizontalRow, .hinge, .verticalPress, .core]
        }
    }

    /// The seventh movement for a long session (`WorkoutPlanner.longSessionMinutes`):
    /// a pattern the focus hasn't covered, else a second exercise for its
    /// biggest muscle (the planner then picks a different exercise for it).
    public var extraSlot: MovementSlot {
        switch self {
        case .push: .horizontalPress   // second chest exercise
        case .pull: .horizontalRow     // second back exercise
        case .legs: .squat             // second quad/glute exercise
        case .upper: .lateralRaise     // side delts aren't in the six
        case .lower: .legExtension
        case .fullBody: .verticalPull
        }
    }

    var groups: Set<MuscleGroup> {
        Set(slots.map(\.muscleGroup)).subtracting([.core])
    }
}

public struct CatalogExercise: Sendable, Equatable {
    public var id: String
    public var name: String
    /// What the weight is loaded on (nil = bodyweight).
    public var load: EquipmentKind?
    /// Everything required to do it.
    public var requires: Set<EquipmentKind>
}

public enum ExerciseCatalog {
    static func ex(_ id: String, _ name: String, _ load: EquipmentKind?, _ requires: EquipmentKind...) -> CatalogExercise {
        CatalogExercise(id: id, name: name, load: load, requires: Set(requires).union(load.map { [$0] } ?? []))
    }

    public static let options: [MovementSlot: [CatalogExercise]] = [
        .horizontalPress: [
            ex("Barbell_Bench_Press_-_Medium_Grip", "Bench Press", .barbell, .bench),
            ex("Dumbbell_Bench_Press", "Dumbbell Bench Press", .dumbbell, .bench),
            ex("Leverage_Chest_Press", "Machine Chest Press", .machine),
            ex("Smith_Machine_Bench_Press", "Smith Machine Bench Press", .smithMachine, .bench),
            ex("Pushups", "Push-Ups", nil)
        ],
        .inclinePress: [
            ex("Incline_Dumbbell_Press", "Incline Dumbbell Press", .dumbbell, .bench),
            ex("Barbell_Incline_Bench_Press_-_Medium_Grip", "Incline Bench Press", .barbell, .bench),
            ex("Push-Ups_With_Feet_Elevated", "Feet-Elevated Push-Ups", nil)
        ],
        .verticalPress: [
            ex("Dumbbell_Shoulder_Press", "Dumbbell Shoulder Press", .dumbbell),
            ex("Standing_Military_Press", "Overhead Press", .barbell),
            ex("Machine_Shoulder_Military_Press", "Machine Shoulder Press", .machine),
            ex("Two-Arm_Kettlebell_Military_Press", "Kettlebell Press", .kettlebell)
        ],
        .chestFly: [
            ex("Cable_Crossover", "Cable Fly", .cable),
            ex("Butterfly", "Pec Deck", .machine),
            ex("Dumbbell_Flyes", "Dumbbell Fly", .dumbbell, .bench)
        ],
        .lateralRaise: [
            ex("Side_Lateral_Raise", "Lateral Raise", .dumbbell),
            ex("Cable_Seated_Lateral_Raise", "Cable Lateral Raise", .cable),
            ex("Lateral_Raise_-_With_Bands", "Band Lateral Raise", nil, .bands)
        ],
        // Overhead first: elbow extensions with the arm overhead (long head
        // stretched) grew the triceps about 1.4-1.5x more than the same work
        // with the arm at the side (Maeo et al., Eur J Sport Sci 2023).
        .triceps: [
            ex("Cable_Rope_Overhead_Triceps_Extension", "Overhead Cable Triceps Extension", .cable),
            ex("Dumbbell_One-Arm_Triceps_Extension", "Overhead Triceps Extension", .dumbbell),
            ex("Triceps_Pushdown_-_Rope_Attachment", "Rope Pushdown", .cable),
            ex("EZ-Bar_Skullcrusher", "EZ-Bar Skullcrusher", .ezBar, .bench),
            ex("Dips_-_Triceps_Version", "Dips", nil, .dipStation),
            ex("Bench_Dips", "Bench Dips", nil, .bench)
        ],
        .verticalPull: [
            ex("Wide-Grip_Lat_Pulldown", "Lat Pulldown", .cable),
            ex("Pullups", "Pull-Ups", nil, .pullUpBar),
            ex("Chin-Up", "Chin-Ups", nil, .pullUpBar)
        ],
        .horizontalRow: [
            ex("Bent_Over_Barbell_Row", "Barbell Row", .barbell),
            ex("Seated_Cable_Rows", "Seated Cable Row", .cable),
            ex("One-Arm_Dumbbell_Row", "One-Arm Dumbbell Row", .dumbbell, .bench),
            ex("Leverage_Iso_Row", "Machine Row", .machine)
        ],
        .rearDelt: [
            ex("Face_Pull", "Face Pull", .cable),
            ex("Reverse_Flyes", "Reverse Fly", .dumbbell),
            ex("Band_Pull_Apart", "Band Pull-Apart", nil, .bands)
        ],
        .biceps: [
            ex("Barbell_Curl", "Barbell Curl", .barbell),
            ex("Dumbbell_Bicep_Curl", "Dumbbell Curl", .dumbbell),
            ex("EZ-Bar_Curl", "EZ-Bar Curl", .ezBar),
            ex("Machine_Bicep_Curl", "Machine Curl", .machine)
        ],
        .hammerCurl: [
            ex("Hammer_Curls", "Hammer Curl", .dumbbell),
            ex("Cable_Hammer_Curls_-_Rope_Attachment", "Cable Hammer Curl", .cable)
        ],
        .squat: [
            ex("Barbell_Squat", "Back Squat", .barbell, .squatRack),
            ex("Leg_Press", "Leg Press", .machine),
            ex("Goblet_Squat", "Goblet Squat", .kettlebell),
            ex("Dumbbell_Squat", "Dumbbell Squat", .dumbbell),
            ex("Bodyweight_Squat", "Bodyweight Squat", nil)
        ],
        .hinge: [
            ex("Romanian_Deadlift", "Romanian Deadlift", .barbell),
            ex("Stiff-Legged_Dumbbell_Deadlift", "Dumbbell Romanian Deadlift", .dumbbell),
            ex("One-Arm_Kettlebell_Swings", "Kettlebell Swing", .kettlebell)
        ],
        .singleLeg: [
            ex("Split_Squat_with_Dumbbells", "Dumbbell Split Squat", .dumbbell),
            ex("Barbell_Lunge", "Barbell Lunge", .barbell, .squatRack),
            ex("Bodyweight_Walking_Lunge", "Walking Lunge", nil)
        ],
        // Seated first: with the hip bent the hamstrings work at longer
        // lengths, and seated curls grew them more than lying curls (Maeo et
        // al., Med Sci Sports Exerc 2021).
        .legCurl: [
            ex("Seated_Leg_Curl", "Seated Leg Curl", .machine),
            ex("Lying_Leg_Curls", "Lying Leg Curl", .machine)
        ],
        .legExtension: [
            ex("Leg_Extensions", "Leg Extension", .machine)
        ],
        // Standing (knee straight) grew the gastrocnemius far more than seated
        // calf raises (Kinoshita et al., Front Physiol 2023).
        .calves: [
            ex("Standing_Calf_Raises", "Standing Calf Raise", .machine),
            ex("Calf_Raise_On_A_Dumbbell", "Dumbbell Calf Raise", .dumbbell)
        ],
        .core: [
            ex("Hanging_Leg_Raise", "Hanging Leg Raise", nil, .pullUpBar),
            ex("Cable_Crunch", "Cable Crunch", .cable),
            ex("Plank", "Plank", nil)
        ]
    ]

    /// Muscles a movement pattern trains, primary first, in plain words for
    /// the plan. The app's exercise library (free-exercise-db) has the
    /// per-exercise list and overlays this where it knows the exercise.
    public static func muscles(for slot: MovementSlot) -> [String] {
        switch slot {
        case .horizontalPress: ["Chest", "Shoulders", "Triceps"]
        case .inclinePress: ["Upper chest", "Shoulders", "Triceps"]
        case .verticalPress: ["Shoulders", "Triceps", "Upper chest"]
        case .chestFly: ["Chest"]
        case .lateralRaise: ["Side delts"]
        case .triceps: ["Triceps"]
        case .verticalPull: ["Lats", "Biceps", "Upper back"]
        case .horizontalRow: ["Lats", "Upper back", "Biceps"]
        case .rearDelt: ["Rear delts", "Upper back"]
        case .biceps: ["Biceps"]
        case .hammerCurl: ["Biceps", "Forearms"]
        case .squat: ["Quads", "Glutes", "Core"]
        case .hinge: ["Hamstrings", "Glutes", "Lower back"]
        case .singleLeg: ["Quads", "Glutes"]
        case .legCurl: ["Hamstrings"]
        case .legExtension: ["Quads"]
        case .calves: ["Calves"]
        case .core: ["Core"]
        }
    }

    /// Muscles for a catalog exercise (primary first); empty for an unknown one.
    public static func muscles(forExerciseID exerciseID: String) -> [String] {
        slot(for: exerciseID).map(muscles(for:)) ?? []
    }

    /// The slot an exercise belongs to, if it's in the catalog.
    public static func slot(for exerciseID: String) -> MovementSlot? {
        for (slot, list) in options where list.contains(where: { $0.id == exerciseID }) {
            return slot
        }
        // Pain regressions that aren't regular options (box squat, floor press...).
        return PainGuard.regressionSlot(for: exerciseID)
    }

    public static func exercise(id: String) -> CatalogExercise? {
        options.values.lazy.flatMap { $0 }.first { $0.id == id } ?? PainGuard.regressionExercise(id: id)
    }
}

/// What you did on an exercise recently, in the gym's unit.
public struct ExerciseHistory: Sendable, Equatable {
    public var bestEstimatedOneRepMax: Double
    public var lastWeight: Double
    public var lastReps: Int
    public var lastRPE: Double?
    public var lastDate: Date
    /// Top working weight of each of the last few sessions (at most
    /// `recentSessions`), oldest first, the last one included. Rep and set
    /// progression hold the heaviest of these, so one easier day (low
    /// recovery, deload, a pain cap) doesn't lower the weight for good.
    /// Empty = only `lastWeight` is known.
    public var recentWeights: [Double] = []
    /// Working sets logged last session (drop stages and mini-sets not
    /// counted); nil when unknown. Set progression adds to this.
    public var lastSets: Int? = nil

    /// Sessions `recentWeights` keeps.
    public static let recentSessions = 3

    public init(bestEstimatedOneRepMax: Double, lastWeight: Double, lastReps: Int, lastRPE: Double?, lastDate: Date,
                recentWeights: [Double] = [], lastSets: Int? = nil) {
        self.bestEstimatedOneRepMax = bestEstimatedOneRepMax
        self.lastWeight = lastWeight
        self.lastReps = lastReps
        self.lastRPE = lastRPE
        self.lastDate = lastDate
        self.recentWeights = Array(recentWeights.suffix(Self.recentSessions))
        self.lastSets = lastSets
    }

    /// The heaviest top working weight of the last few sessions (`recentWeights`, `lastWeight`).
    public var recentHeaviestWeight: Double {
        max(lastWeight, recentWeights.max() ?? 0)
    }

    /// True when the last session's top set was lighter than the recent
    /// heaviest: an easier day, not a new level.
    public var lastWasLighter: Bool { lastWeight < recentHeaviestWeight - 0.001 }

    /// `recentWeights` with this session's top weight added, kept to the last few.
    public static func appending(_ weight: Double, to weights: [Double]) -> [Double] {
        Array((weights + [weight]).suffix(recentSessions))
    }
}

public struct PlannedExercise: Codable, Sendable, Equatable, Identifiable {
    public var id: String { exerciseID }
    public var exerciseID: String
    public var name: String
    public var sets: Int
    public var reps: ClosedRange<Int>
    public var rpe: Double
    /// Suggested load in the gym's unit (per hand for dumbbells). Nil for bodyweight or no history.
    public var load: Double?
    public var loadKind: EquipmentKind?
    /// e.g. "45 + 25 per side", or "first time: pick a weight you can do for 8 at RPE 7".
    public var note: String?
    /// Exercises with the same group are a superset: one set of each, then
    /// rest (`Supersets`). Nil for a straight set.
    public var supersetGroup: Int? = nil
    /// Ramp sets before the working sets (`WarmUp`), in the gym's unit. Nil or
    /// empty when the lift gets none.
    public var warmUpSets: [WarmUp.RampSet]? = nil
    /// How the load moved since last time ("+5 lb from last time: you hit 8
    /// reps at RPE 7"), so the gradual increase is visible. Nil without history.
    public var progressionNote: String? = nil
    /// A time-saving style for the last (here: only) working set (`TimeSaver`):
    /// drop set, rest-pause or myo-reps, followed by `stages`. Nil for straight sets.
    /// Optional, so plans saved before set types still decode.
    public var lastSetKind: SetKind? = nil
    /// The drop stages or mini-sets after that set, in order.
    public var stages: [Stage]? = nil
    /// The most the working sets may weigh today, in kg: set by the pain
    /// guard (`ExerciseFilter.capLoad`) so live autoregulation can't add the
    /// weight back. Nil when there's no cap. Optional, so older plans decode.
    public var maxLoadKg: Double? = nil
}

extension PlannedExercise {
    /// One drop stage or mini-set (`SetKind.isStage`).
    public struct Stage: Codable, Sendable, Equatable {
        /// In the gym's unit; nil = the same weight as the set before (rest-pause,
        /// myo-reps) or not known yet (a drop with no planned load).
        public var load: Double?
        /// A starting point for the reps (`TimeSaver.stageReps`); log what you do.
        public var reps: Int

        public init(load: Double?, reps: Int) {
            self.load = load
            self.reps = reps
        }
    }
}

extension PlannedExercise {
    /// Muscles this exercise trains, primary first (`ExerciseCatalog.muscles`);
    /// empty for an exercise outside the catalog.
    public var muscles: [String] { ExerciseCatalog.muscles(forExerciseID: exerciseID) }

    /// "2-3 reps in reserve": how many more reps you could do at the end of each set.
    public var repsInReserve: String {
        let reserve = max(0, 10 - rpe)
        let low = Int(reserve.rounded(.down))
        let high = Int(reserve.rounded(.up))
        if high == 0 { return "to failure" }
        let range = low == high ? "\(low)" : "\(low)-\(high)"
        return "\(range) rep\(high == 1 ? "" : "s") in reserve"
    }
}

public struct PlannedWorkout: Codable, Sendable, Equatable {
    public var focus: WorkoutFocus
    public var title: String
    public var minutes: Int
    public var targetRPE: Double
    public var exercises: [PlannedExercise]
    public var unit: LoadUnit
    /// The training-block week this session was planned in, if any.
    public var blockWeek: TrainingBlock.WeekState? = nil
    /// Why this session today, in one or two short sentences (`WorkoutPlanner.rationale`).
    public var rationale: String = ""
    /// The start of `rationale` that names the focus, its muscles and the block
    /// week (`WorkoutPlanner.rationaleLead`). Optional so saved plans still decode.
    public var rationaleLead: String? = nil
    /// How long the session should take (`WorkoutPlanner.estimatedMinutes`,
    /// with the planner's rest style and warm-up). Nil for plans made
    /// without the planner.
    public var estimatedMinutes: Int? = nil

    /// True when at least one superset was made to fit the time.
    public var hasSupersets: Bool { exercises.contains { $0.supersetGroup != nil } }

    /// Every muscle the session trains, in the order it first appears, no repeats.
    public var musclesCovered: [String] {
        var seen: [String] = []
        for muscle in exercises.flatMap(\.muscles) where !seen.contains(muscle) {
            seen.append(muscle)
        }
        return seen
    }

    /// Working sets across the session.
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    /// `rationale` without its lead, for a screen that already shows the
    /// title, the muscles and the block week (the workout builder).
    public var rationaleDetail: String {
        guard let lead = rationaleLead, !lead.isEmpty, rationale.hasPrefix(lead) else { return rationale }
        return rationale.dropFirst(lead.count).trimmingCharacters(in: .whitespaces)
    }
}

public struct WorkoutPlanner: Sendable {
    public var gym: GymProfile
    /// Rep ranges and effort, from the user's goals.
    public var style: TrainingStyle
    /// "Never again" exercises and current pain (`ExerciseFilter`, `PainGuard`):
    /// applied to every choice and swap through `alternatives(for:)`.
    public var exerciseFilter: ExerciseFilter? = nil
    /// Your own choice of how each lift progresses (`ProgressionMode`), by
    /// exercise ID; lifts not listed use `ProgressionMode.suggested`.
    public var progressionModes: [String: ProgressionMode] = [:]

    public init(gym: GymProfile, style: TrainingStyle = .balanced) {
        self.gym = gym
        self.style = style
    }

    /// The focus that's been rested longest, rotating push → pull → legs.
    /// - Parameter recentExerciseIDs: exercises done in the last few days, newest first.
    public static func suggestedFocus(recentExerciseIDs: [String]) -> WorkoutFocus {
        let groups = recentExerciseIDs.compactMap { ExerciseCatalog.slot(for: $0)?.muscleGroup }
        guard let last = groups.first(where: { $0 != .core }) else { return .push }
        let trained = Set(groups.prefix(12))
        for candidate in [WorkoutFocus.push, .pull, .legs] where !trained.contains(candidate.groups.first!) {
            return candidate
        }
        switch last {
        case .push: return .pull
        case .pull: return .legs
        default: return .push
        }
    }

    /// The focus that closes the most of this week's gap to 10-20 hard sets
    /// per muscle (`MuscleCoverage.suggest`), falling back to the rotation
    /// above when nothing lags or every lagging muscle is still recovering.
    /// The rotation's pick wins ties, so a fresh week starts where it would
    /// have anyway and the coverage rule only steers once muscles fall behind.
    /// - Parameters:
    ///   - setsThisWeek: hard sets per muscle since Monday (`MuscleCoverage.setsThisWeek`).
    ///   - states: muscle recovery (`MuscleRecovery.evaluate`).
    ///   - sessionsLeft: sessions still to come this week, today's included.
    public static func suggestedFocus(
        recentExerciseIDs: [String],
        setsThisWeek: [Muscle: Double],
        states: [Muscle: MuscleRecovery.State],
        sessionsLeft: Int
    ) -> (focus: WorkoutFocus, coverage: MuscleCoverage.Result?) {
        let rotation = suggestedFocus(recentExerciseIDs: recentExerciseIDs)
        let coverage = MuscleCoverage.suggest(setsThisWeek: setsThisWeek, states: states,
                                              sessionsLeft: sessionsLeft, preferred: rotation)
        return (coverage?.focus ?? rotation, coverage)
    }

    /// Target RPE from recovery: train hard when recovered, back off when not.
    ///
    /// Adjusting effort to the day is autoregulation, which works for strength
    /// (Larsen et al., PeerJ 2021). Steering by HRV-based readiness has small,
    /// uncertain benefits in endurance training (Granero-Gallegos et al., IJERPH
    /// 2020; Manresa-Rocamora et al., IJERPH 2021) and hasn't beaten fixed plans
    /// for lifting, so the swing is kept small: 2-3.5 reps in reserve, never
    /// skipping the session. Stopping 1-3 reps short of failure builds about as
    /// much muscle as failure (Refalo et al., J Sports Sci 2024; ACSM position
    /// stand, Med Sci Sports Exerc 2026).
    public static func targetRPE(recovery: Int?) -> Double {
        guard let recovery else { return 7.5 }
        switch recovery {
        case ..<34: return 6.5
        case 34..<67: return 7.5
        default: return 8
        }
    }

    /// Inside a training block the week sets the effort (RIR 3 → 2 → 1, deload
    /// 3; `TrainingBlock`), and the recovery rule above still backs off a
    /// low-recovery day by the same amount it would outside a block (0.5 for
    /// moderate, 1.5 for low recovery). Kept between RPE 6 and 9: no block
    /// week asks for failure (Refalo et al. 2024; Robinson et al. 2024).
    public static func targetRPE(recovery: Int?, block: TrainingBlock.WeekState?) -> Double {
        let daily = targetRPE(recovery: recovery)
        guard let block else { return daily }
        let backOff = 8 - daily
        return max(6, min(9, block.targetRPE - backOff))
    }

    /// The first option for a slot: the gym supports it, it isn't on the
    /// never-again list, it doesn't load a 6+/10 painful area, and a
    /// regression comes first for a 3-5/10 one (`ExerciseFilter.apply`).
    public func choose(_ slot: MovementSlot) -> CatalogExercise? {
        alternatives(for: slot).first
    }

    /// Every catalog exercise for a slot that this gym supports, best first.
    public func alternatives(for slot: MovementSlot) -> [CatalogExercise] {
        let supported = (ExerciseCatalog.options[slot] ?? []).filter { exercise in
            exercise.requires.allSatisfy { gym.has($0) } &&
            (exercise.load.map { !gym.achievableLoads(for: $0).isEmpty } ?? true)
        }
        return exerciseFilter?.apply(to: supported, slot: slot, gym: gym) ?? supported
    }

    /// Sets, reps, effort and load for one exercise in a session. With
    /// history the load follows double progression (`suggestedLoad`) and the
    /// change is written out (`progressionNote`); without it a starting
    /// weight is estimated from your other lifts or body weight
    /// (`LoadEstimator`), else the note says to find one.
    public func prescribe(
        _ choice: CatalogExercise,
        slot: MovementSlot,
        minutes: Int,
        sessionRPE rpe: Double,
        history: [String: ExerciseHistory],
        lifter: LoadEstimator.Lifter = .unknown
    ) -> PlannedExercise {
        let compound = slot.isCompound
        let sets = Self.baseSets(compound: compound, minutes: minutes)
        // Effort: big lifts stop 2-3 reps short of failure; small lifts go
        // closer, since muscle growth benefits from proximity to failure while
        // strength barely does and failure adds fatigue (Robinson et al., Sports Med 2024).
        let reps: ClosedRange<Int>
        let setRPE: Double
        switch style {
        case .balanced:
            reps = compound ? 6...8 : (slot == .core ? 10...15 : 10...12)
            setRPE = compound ? rpe : min(9.5, rpe + 1)
        case .strength:
            reps = compound ? 3...6 : (slot == .core ? 8...12 : 8...10)
            setRPE = compound ? min(rpe, 8) : min(9, rpe + 0.5)
        case .muscle:
            reps = compound ? 6...10 : (slot == .core ? 10...15 : 10...15)
            setRPE = compound ? min(8.5, rpe + 0.5) : min(9.5, rpe + 1.5)
        case .endurance:
            reps = compound ? 10...15 : 12...20
            setRPE = compound ? min(rpe, 7.5) : min(8.5, rpe + 0.5)
        }
        var planned = PlannedExercise(
            exerciseID: choice.id, name: choice.name, sets: sets, reps: reps,
            rpe: setRPE, load: nil, loadKind: choice.load, note: nil
        )
        if let kind = choice.load {
            if let past = history[choice.id] {
                let mode = progressionMode(for: choice.id, kind: kind, compound: compound, at: past.lastWeight)
                planned.load = suggestedLoad(history: past, reps: reps, rpe: setRPE, kind: kind, mode: mode)
                if let load = planned.load {
                    planned.note = notes(load: load, history: past, reps: reps, rpe: setRPE, kind: kind, mode: mode)
                    planned.progressionNote = progressionNote(load: load, history: past, reps: reps, mode: mode, rpe: setRPE)
                    // Rep progression: today's target goes one past last time (the
                    // live session pre-fills the top of the range).
                    if mode == .reps, let target = repTarget(load: load, history: past, reps: reps, rpe: setRPE) {
                        planned.reps = reps.lowerBound...target
                    }
                    // Set progression: one more set than last time, before the
                    // block, the week's targets and the time fit (`plan`).
                    if mode == .sets, let more = progressedSets(load: load, history: past, reps: reps, rpe: setRPE) {
                        planned.sets = max(planned.sets, more)
                    }
                }
            } else if let estimate = LoadEstimator.estimate(exerciseID: choice.id, reps: reps, rpe: setRPE,
                                                            history: history, lifter: lifter, gym: gym) {
                planned.load = estimate.load
                planned.note = [estimate.note, loadNote(load: estimate.load, kind: kind)].compactMap { $0 }.joined(separator: ". ")
            } else {
                planned.note = "First time: pick a weight you can lift \(reps.upperBound) times with \(Int(10 - setRPE)) left in the tank."
            }
        }
        return planned
    }

    /// "+5 lb from last time: you hit 8 reps at RPE 7", "Same weight as last
    /// time: get 8 reps to move up", or "−10 lb from last time for today's
    /// effort". Makes the double progression visible. With rep or set
    /// progression (`ProgressionMode`) the held weight says what to add
    /// instead. `rpe` is today's target (nil: as last time).
    func progressionNote(load: Double, history: ExerciseHistory, reps: ClosedRange<Int>, mode: ProgressionMode = .load,
                         rpe: Double? = nil) -> String {
        let unit = gym.unit.rawValue
        func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
        let delta = load - history.lastWeight
        let effort = history.lastRPE.map { " at RPE \($0.formatted())" } ?? ""
        // Back up after one easier session (low recovery, deload, a pain cap):
        // not a new step, so don't credit last time's reps for it.
        if delta > 0.001, history.lastWasLighter, load <= history.recentHeaviestWeight + 0.001 {
            return "Back to \(fmt(load)) \(unit) after an easier session"
        }
        if delta > 0.001 {
            return "+\(fmt(delta)) \(unit) from last time: you hit \(history.lastReps) reps\(effort)"
        }
        if delta < -0.001 {
            return "−\(fmt(-delta)) \(unit) from last time for today's effort"
        }
        let goal = reps.upperBound + Self.bigJumpExtraReps
        let today = rpe ?? history.lastRPE ?? 8
        switch mode {
        case .load:
            return "Same weight as last time: get \(reps.upperBound) reps to move up"
        case .reps:
            let target = repTarget(load: load, history: history, reps: reps, rpe: today) ?? reps.upperBound
            return "Same weight as last time: aim for \(target) reps; it moves up at \(goal)"
        case .sets:
            let most = TrainingBlock.setRange.upperBound
            if progressedSets(load: load, history: history, reps: reps, rpe: today) != nil {
                return "Same weight, one more set: you hit \(reps.upperBound) reps; it moves up at \(most) sets"
            }
            return "Same weight: hit \(reps.upperBound) reps to add a set; it moves up at \(most) sets"
        }
    }

    /// True when last session was at or under today's effort target, at the
    /// recent heaviest weight, and `load` is that same weight: the case where
    /// rep and set progression add reps or sets.
    func isHeldAtLastWeight(load: Double, history: ExerciseHistory, rpe: Double) -> Bool {
        abs(load - history.lastWeight) < 0.001 && !history.lastWasLighter && (history.lastRPE ?? rpe) <= rpe + 0.001
    }

    /// Rep progression's target for today: one rep more than last time, at
    /// most `bigJumpExtraReps` past the top of the range (where the load
    /// moves up instead). Nil when the top of the range is the target anyway,
    /// or the weight changed.
    func repTarget(load: Double, history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double) -> Int? {
        guard isHeldAtLastWeight(load: load, history: history, rpe: rpe) else { return nil }
        let target = min(history.lastReps + 1, reps.upperBound + Self.bigJumpExtraReps)
        return target > reps.upperBound ? target : nil
    }

    /// Set progression's sets for today: one more than last time (at most
    /// `TrainingBlock.setRange`'s 5) when last time reached the top of the
    /// range at the effort target at the same weight. Nil otherwise, or when
    /// last session's set count isn't known.
    func progressedSets(load: Double, history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double) -> Int? {
        guard isHeldAtLastWeight(load: load, history: history, rpe: rpe), let last = history.lastSets,
              history.lastReps >= reps.upperBound else { return nil }
        return min(TrainingBlock.setRange.upperBound, last + 1)
    }

    /// Rep and set progression move the weight up one step when last time
    /// beat the top of the range by `bigJumpExtraReps`; set progression also
    /// once it reached the top of the range on the most sets (5).
    func earnedLoadStep(_ history: ExerciseHistory, reps: ClosedRange<Int>, mode: ProgressionMode) -> Bool {
        let pastRange = history.lastReps >= reps.upperBound + Self.bigJumpExtraReps
        switch mode {
        case .load: return false
        case .reps: return pastRange
        case .sets:
            let atMostSets = (history.lastSets ?? 0) >= TrainingBlock.setRange.upperBound
            return pastRange || (atMostSets && history.lastReps >= reps.upperBound)
        }
    }

    /// How this lift progresses: your choice (`progressionModes`), else the
    /// suggestion for its equipment (`ProgressionMode.suggested`), where a
    /// "big jump" is the next weight up from `load` being over 10% heavier.
    public func progressionMode(for exerciseID: String, kind: EquipmentKind?, compound: Bool, at load: Double) -> ProgressionMode {
        if let own = progressionModes[exerciseID] { return own }
        var bigJump = false
        if let kind, let next = gym.nextLoad(above: load, on: kind) {
            bigJump = isBigJump(from: load, to: next)
        }
        return ProgressionMode.suggested(kind: kind, compound: compound, bigJump: bigJump)
    }

    /// Builds a session. With a `block` week the sets scale by the week's
    /// multiplier (`TrainingBlock.scaledSets`) and the effort comes from its
    /// RIR target, still lowered on a low-recovery day. Compound lifts get
    /// warm-up ramp sets (`WarmUp`), then sessions that overrun the time are
    /// trimmed, paired into supersets, then shortened (`fit`), and sessions
    /// that come in well under it get sets or an extra exercise (`fill`), so
    /// the estimate lands within `fillFraction`-100% of the time you picked.
    /// Long sessions (`longSessionMinutes`) add the focus's `extraSlot` and a
    /// fourth set on isolation work. `focusReason` ("because of the soreness
    /// you reported") goes into the plan's `rationale`. Body weight, sex and
    /// training status feed starting weights for lifts without history
    /// (`LoadEstimator`); `warmUpMinutes` is the movement warm-up
    /// (`WarmUpRoutine`) the session starts with: 0 (the default) for the
    /// off and ramp-only tiers, the routine's minutes for short and full.
    /// `prioritySlots` (from `MuscleCoverage`) are movements for muscles
    /// behind on the week's sets: they go straight after the compound lifts,
    /// so a short session drops a default isolation movement instead of them.
    public func plan(
        focus: WorkoutFocus,
        minutes: Int,
        recovery: Int?,
        history: [String: ExerciseHistory],
        block: TrainingBlock.WeekState? = nil,
        focusReason: String? = nil,
        prioritySlots: [MovementSlot] = [],
        bodyMassKg: Double? = nil,
        sex: BiologicalSex = .male,
        trainingStatus: TrainingStatus = .novice,
        warmUpMinutes: Int = 0,
        exerciseFilter: ExerciseFilter? = nil,
        muscleSetGoals: [Muscle: Int] = [:]
    ) -> PlannedWorkout {
        // Never-again exercises and pain (`PainGuard`): plan with the filter
        // set, then cap the loads on lifts that load a 3-5/10 area.
        // Forward every other parameter here when adding one.
        if let exerciseFilter {
            var guarded = self
            guarded.exerciseFilter = exerciseFilter
            var workout = guarded.plan(focus: focus, minutes: minutes, recovery: recovery, history: history, block: block,
                                       focusReason: focusReason, prioritySlots: prioritySlots, bodyMassKg: bodyMassKg,
                                       sex: sex, trainingStatus: trainingStatus, warmUpMinutes: warmUpMinutes,
                                       muscleSetGoals: muscleSetGoals)
            exerciseFilter.capLoads(&workout, planner: guarded)
            return workout
        }
        let rpe = Self.targetRPE(recovery: recovery, block: block)
        let lifter = LoadEstimator.Lifter(bodyMassKg: bodyMassKg, sex: sex, status: trainingStatus)
        let exerciseCount = Self.exerciseCount(minutes: minutes)
        let slots = Self.orderedSlots(focus: focus, minutes: minutes, priority: prioritySlots)
        var exercises: [PlannedExercise] = []
        // Sets earned by set progression (`progressedSets`), by exercise.
        var earnedSets: [String: Int] = [:]
        for slot in slots {
            // A repeated slot (the long session's extra) gets a different exercise.
            let used = Set(exercises.map(\.exerciseID))
            guard exercises.count < exerciseCount,
                  let choice = alternatives(for: slot).first(where: { !used.contains($0.id) }) else { continue }
            var planned = prescribe(choice, slot: slot, minutes: minutes, sessionRPE: rpe, history: history, lifter: lifter)
            var base = Self.baseSets(compound: slot.isCompound, minutes: minutes)
            if let block {
                // Scale the base sets, so a set added by set progression isn't
                // scaled again; the deload cuts it like any other set.
                base = TrainingBlock.scaledSets(base, multiplier: block.setMultiplier)
                planned.sets = block.isDeload ? base : max(base, planned.sets)
            }
            if planned.sets > base { earnedSets[choice.id] = planned.sets }
            exercises.append(planned)
        }
        // This week's per-muscle targets (`VolumeProgression`) set the sets; `fit` still trims to the time.
        Self.applySetGoals(&exercises, goals: muscleSetGoals)
        // Ramp sets first, so the time they take counts when fitting.
        addWarmUps(&exercises)
        Self.fit(&exercises, minutes: minutes, style: style, warmUpMinutes: warmUpMinutes)
        // A muscle with a weekly target already has its sets; the others keep an earned set if time allows.
        let targeted = Set(muscleSetGoals.keys)
        earnedSets = earnedSets.filter { id, _ in
            guard let exercise = exercises.first(where: { $0.exerciseID == id }) else { return false }
            return VolumeProgression.primaryMuscle(exercise).map { !targeted.contains($0) } ?? true
        }
        Self.keepEarnedSets(&exercises, earned: earnedSets, minutes: minutes, style: style, warmUpMinutes: warmUpMinutes)
        // A deload week is meant to be short; every other session fills the time.
        if block?.isDeload != true {
            fill(&exercises, focus: focus, minutes: minutes, rpe: rpe, history: history, lifter: lifter, warmUpMinutes: warmUpMinutes,
                 goals: muscleSetGoals)
        }
        var workout = PlannedWorkout(focus: focus, title: focus.title, minutes: minutes, targetRPE: rpe, exercises: exercises, unit: gym.unit)
        workout.blockWeek = block
        workout.rationale = Self.rationale(focus: focus, focusReason: focusReason, minutes: minutes, recovery: recovery,
                                           rpe: rpe, block: block, exercises: exercises)
        workout.rationaleLead = Self.rationaleLead(focus: focus, focusReason: focusReason, block: block)
        workout.estimatedMinutes = Self.estimatedMinutes(exercises, style: style, warmUpMinutes: warmUpMinutes)
        return workout
    }

    /// The focus's movements for the session length (the long session adds
    /// `extraSlot`), with any priority movements moved to directly after the
    /// leading compound lifts: multi-joint lifts stay first (Nunes et al.
    /// 2021), the lagging muscle's movement comes next, the defaults after.
    static func orderedSlots(focus: WorkoutFocus, minutes: Int, priority: [MovementSlot]) -> [MovementSlot] {
        var base = minutes >= longSessionMinutes ? focus.slots + [focus.extraSlot] : focus.slots
        guard !priority.isEmpty else { return base }
        base.removeAll { priority.contains($0) }
        let leading = base.prefix { $0.isCompound }
        var unique: [MovementSlot] = []
        for slot in priority where !unique.contains(slot) { unique.append(slot) }
        return Array(leading) + unique + Array(base.dropFirst(leading.count))
    }

    /// Below this share of the time you picked, `fill` adds work. The 60-min
    /// session a user clocked at 40 min is what this guards against; the
    /// 85% floor is the app's choice (a plan should land near, never over).
    public static let fillFraction = 0.85
    /// Most working sets `fill` gives one exercise (`baseSets`' reasoning:
    /// about 6-8 sets per muscle in one session); the first two compound
    /// lifts may take a fifth before an extra exercise is added.
    public static let maximumSetsPerExercise = 4

    /// Adds working sets, then an exercise for the focus's `extraSlot`, until
    /// the estimate reaches `fillFraction` of `minutes`, never passing
    /// `minutes`. Sets go to the exercise with the fewest first (the earlier
    /// one on a tie), up to `maximumSetsPerExercise`, then a fifth on the
    /// first two compound lifts: more hard sets per muscle grow more muscle
    /// (Schoenfeld, Ogborn & Krieger, J Sports Sci 2017; Pelland et al.,
    /// Sports Med 2026), so spare time buys sets before variety.
    ///
    /// With per-muscle `goals` (`VolumeProgression.sessionGoals`), a set or
    /// the extra exercise only goes to a muscle still under its goal (or one
    /// without a goal), so spare time never pushes a muscle past the week's
    /// target; superset rounds count once per muscle (`VolumeProgression.directSets`).
    func fill(_ exercises: inout [PlannedExercise], focus: WorkoutFocus, minutes: Int, rpe: Double,
              history: [String: ExerciseHistory], lifter: LoadEstimator.Lifter, warmUpMinutes: Int,
              goals: [Muscle: Int] = [:]) {
        /// True when one more set on this exercise's main muscle stays within its goal.
        func underGoal(_ exercise: PlannedExercise, in list: [PlannedExercise]) -> Bool {
            guard let muscle = VolumeProgression.primaryMuscle(exercise), let goal = goals[muscle] else { return true }
            return (VolumeProgression.directSets(list)[muscle] ?? 0) < goal
        }
        func estimate(_ list: [PlannedExercise]) -> Int {
            Self.estimatedMinutes(list, style: style, warmUpMinutes: warmUpMinutes)
        }
        let target = Int((Double(minutes) * Self.fillFraction).rounded(.up))
        var triedExtra = false
        while estimate(exercises) < target {
            var added = false
            for index in Self.fillCandidates(exercises) where underGoal(exercises[index], in: exercises) {
                var candidate = exercises
                candidate[index].sets += 1
                if estimate(candidate) <= minutes {
                    exercises = candidate
                    added = true
                    break
                }
            }
            if added { continue }
            guard !triedExtra else { return }
            triedExtra = true
            let used = Set(exercises.map(\.exerciseID))
            guard let choice = alternatives(for: focus.extraSlot).first(where: { !used.contains($0.id) }) else { return }
            var extra = prescribe(choice, slot: focus.extraSlot, minutes: minutes, sessionRPE: rpe, history: history, lifter: lifter)
            extra.sets = Self.minimumSetsWhenShort
            guard underGoal(extra, in: exercises) else { return }
            var candidate = exercises + [extra]
            addWarmUps(&candidate)
            guard estimate(candidate) <= minutes else { return }
            exercises = candidate
        }
    }

    /// Where `fill` tries to add a set, in order: exercises under the cap,
    /// fewest sets first (earlier on a tie), then the first two compound
    /// lifts for a fifth set.
    static func fillCandidates(_ exercises: [PlannedExercise]) -> [Int] {
        let under = exercises.indices
            .filter { exercises[$0].sets < maximumSetsPerExercise }
            .sorted { (exercises[$0].sets, $0) < (exercises[$1].sets, $1) }
        let compounds = exercises.indices
            .filter { ExerciseCatalog.slot(for: exercises[$0].exerciseID)?.isCompound == true }
            .prefix(2)
            .filter { exercises[$0].sets < maximumSetsPerExercise + 1 && !under.contains($0) }
        return under + compounds
    }

    /// Shares each muscle's set goal for the session (`VolumeProgression.sessionGoals`)
    /// over the exercises that train it as their main muscle, in session
    /// order (the compound lifts come first, so they get any spare set), each
    /// kept to `TrainingBlock.setRange` (2-5). Exercises for muscles without a
    /// goal keep the sets they were given. A goal of 0 (the week's target is
    /// already met) leaves those exercises at the minimum.
    static func applySetGoals(_ exercises: inout [PlannedExercise], goals: [Muscle: Int]) {
        guard !goals.isEmpty else { return }
        for (muscle, goal) in goals {
            let indices = exercises.indices.filter { VolumeProgression.primaryMuscle(exercises[$0]) == muscle }
            guard !indices.isEmpty else { continue }
            let each = goal / indices.count
            let spare = goal % indices.count
            for (position, index) in indices.enumerated() {
                let sets = each + (position < spare ? 1 : 0)
                exercises[index].sets = max(TrainingBlock.setRange.lowerBound, min(TrainingBlock.setRange.upperBound, sets))
            }
        }
    }

    /// From here up a session is "long": a seventh exercise and four sets on
    /// isolation work too, so 75 minutes buys more than 60 does.
    public static let longSessionMinutes = 75

    /// Exercises per session by the time picked: 4 up to 30 min, 5 to 45, 6
    /// to 60, 7 from `longSessionMinutes`. `fit` trims whatever overruns.
    public static func exerciseCount(minutes: Int) -> Int {
        if minutes >= longSessionMinutes { return 7 }
        return minutes <= 30 ? 4 : (minutes <= 45 ? 5 : 6)
    }

    /// Working sets per exercise before a block week scales them and `fit`
    /// trims them. More weekly hard sets per muscle grow more muscle (dose-
    /// response, about 10+ sets/muscle/week: Schoenfeld, Ogborn & Krieger, J
    /// Sports Sci 2017; still rising with diminishing returns past about 20:
    /// Pelland et al., Sports Med 2026), so a longer session adds sets rather
    /// than only rest. The cap of four per exercise, and so about 6-8 sets per
    /// muscle in one session, is the app's choice: the meta-analyses are about
    /// weekly totals, and spreading sets over the week is as good or better
    /// than piling them into one session (Schoenfeld, Grgic & Krieger, J Sports
    /// Sci 2019, frequency meta-analysis; see `TrainingDayPlanner`). Short
    /// sessions give the big lifts 3 sets.
    public static func baseSets(compound: Bool, minutes: Int) -> Int {
        if minutes >= longSessionMinutes { return 4 }
        return compound ? (minutes <= 30 ? 3 : 4) : 3
    }

    /// The focus and its muscles, and the block week: the part of the
    /// rationale a screen showing those already can leave out.
    static func rationaleLead(focus: WorkoutFocus, focusReason: String?, block: TrainingBlock.WeekState?) -> String {
        let why = focusReason.map { " \($0)" } ?? ""
        var parts = ["\(focus.title)\(why): \(focus.muscles.lowercased())."]
        if let block { parts.append("\(block.label).") }
        return parts.joined(separator: " ")
    }

    /// Why this session today: the focus and its muscles, the effort from
    /// recovery (and the block week), then what the time bought. Effort is
    /// said as reps in reserve, the same words the sets use ("3-4 in reserve").
    static func rationale(focus: WorkoutFocus, focusReason: String?, minutes: Int, recovery: Int?,
                          rpe: Double, block: TrainingBlock.WeekState?, exercises: [PlannedExercise]) -> String {
        var parts = [rationaleLead(focus: focus, focusReason: focusReason, block: block)]
        let reserve = ReserveText.text(rpe: rpe)
        if block != nil {
            // The block week sets the reserve; only a low-recovery back-off needs saying.
            if let recovery, recovery < 67 { parts.append("Eased to \(reserve) for \(recovery)% recovery.") }
        } else if let recovery {
            let mood = recovery < 34 ? "an easy day" : (recovery < 67 ? "a normal day" : "a day to push")
            parts.append("Recovery \(recovery)%, \(mood): sets stop with \(reserve).")
        } else {
            parts.append("No recovery score yet, so a moderate effort: \(reserve).")
        }
        // Counts after `fit`, so the line never promises sets the time didn't allow.
        let sets = exercises.reduce(0) { $0 + $1.sets }
        parts.append("\(minutes) min: \(exercises.count) exercises, \(sets) working sets.")
        return parts.joined(separator: " ")
    }

    /// Ramp sets for the loaded compound lifts: a full ramp on the first,
    /// one feeler set on later ones, none on isolation work (`WarmUp`). A
    /// lift with no load (first time, nothing to estimate from) gets none:
    /// there's no weight to ramp to, so the first set finds the weight.
    public func addWarmUps(_ exercises: inout [PlannedExercise]) {
        var seenCompound = false
        for index in exercises.indices {
            let exercise = exercises[index]
            exercises[index].warmUpSets = nil
            guard ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound == true,
                  let load = exercise.load, let kind = exercise.loadKind else { continue }
            let role: WarmUp.Role = seenCompound ? .laterCompound : .firstCompound
            seenCompound = true
            let sets = WarmUp.sets(workingLoad: load, kind: kind, gym: gym, role: role)
            exercises[index].warmUpSets = sets.isEmpty ? nil : sets
        }
    }

    /// Fewest sets an exercise is cut to so a session fits the time you picked.
    /// Two sets per exercise is within the 2-3 the ACSM recommends (position
    /// stand, Med Sci Sports Exerc 2026), and per-session strength gains level
    /// off after about two sets (Remmert et al., SportRxiv 2025 preprint).
    static let minimumSetsWhenShort = 2

    /// Cuts sets until the estimated length fits `minutes`: always from the
    /// exercise with the most sets, the later one on a tie, so the main lifts
    /// keep theirs longest. If every exercise is down to two sets, the
    /// exercises are paired into supersets (`Supersets.pair`), which keeps
    /// the work and cuts the time; only then does the last exercise go
    /// (keeping at least two). With little time, fewer sets of the big
    /// multi-joint lifts and paired sets are the efficient choices (Iversen
    /// et al., Sports Med 2021).
    static func fit(_ exercises: inout [PlannedExercise], minutes: Int, style: TrainingStyle = .balanced,
                    warmUpMinutes: Int = 0) {
        var triedPairing = exercises.contains { $0.supersetGroup != nil }
        while estimatedMinutes(exercises, style: style, warmUpMinutes: warmUpMinutes) > minutes {
            let trimmable = exercises.indices.filter { exercises[$0].sets > minimumSetsWhenShort }
            if let index = trimmable.reversed().max(by: { exercises[$0].sets < exercises[$1].sets }) {
                exercises[index].sets -= 1
            } else if !triedPairing {
                triedPairing = true
                exercises = Supersets.pair(exercises: exercises, style: style)
            } else if exercises.count > 2 {
                exercises.removeLast()
                Supersets.dropOrphans(&exercises)
            } else {
                return
            }
        }
    }

    /// `fit` trims the exercise with the most sets first, which is the one set
    /// progression just added a set to. This moves the earned set back, one
    /// set at a time from the latest other straight exercise above two sets,
    /// as long as the session still fits the time; otherwise the trim stands.
    static func keepEarnedSets(_ exercises: inout [PlannedExercise], earned: [String: Int], minutes: Int,
                               style: TrainingStyle = .balanced, warmUpMinutes: Int = 0) {
        for (id, goal) in earned.sorted(by: { $0.key < $1.key }) {
            guard let index = exercises.firstIndex(where: { $0.exerciseID == id }),
                  exercises[index].supersetGroup == nil else { continue }
            while exercises[index].sets < goal {
                guard let donor = exercises.indices.reversed().first(where: { other in
                    other != index && earned[exercises[other].exerciseID] == nil &&
                        exercises[other].supersetGroup == nil && exercises[other].sets > minimumSetsWhenShort
                }) else { break }
                var trial = exercises
                trial[donor].sets -= 1
                trial[index].sets += 1
                guard estimatedMinutes(trial, style: style, warmUpMinutes: warmUpMinutes) <= minutes else { break }
                exercises = trial
            }
        }
    }

    /// The biggest jump in weight taken just for reaching the top of the rep
    /// range: the ACSM suggests adding 2-10% at a time (position stand, Med Sci
    /// Sports Exerc 2009).
    static let routineJumpFraction = 0.10
    /// When the next weight up is a bigger jump than that (light dumbbells,
    /// coarse stacks), earn it by beating the top of the range by this many
    /// reps first, as the ACSM's "1-2 reps over the desired number" rule does.
    static let bigJumpExtraReps = 2

    /// Weight for the top of the rep range at the target RPE, from your best
    /// estimated 1RM, rounded down to something you can actually load. If you
    /// reached the top of the range last time at the target effort or easier,
    /// it moves up one jump (double progression); a jump of over 10% needs two
    /// extra reps first.
    ///
    /// `mode` (`ProgressionMode`; Plotkin et al., PeerJ 2022: load and rep
    /// progression both work): `.load` is the rule above. `.reps` and `.sets`
    /// hold the heaviest top weight of the last few sessions
    /// (`ExerciseHistory.recentHeaviestWeight`), so one easier day doesn't
    /// lower it for good, and add reps (`repTarget`) or a set
    /// (`progressedSets`) instead. They move up one jump, whatever its size,
    /// once that's earned (`earnedLoadStep`): `.reps` at `bigJumpExtraReps`
    /// past the top of the range, `.sets` also at the top of the range on the
    /// most sets. A day with a lower effort target than last time (low
    /// recovery, deload) goes lighter for that day only; the session after an
    /// easier one goes back to the held weight without a step.
    public func suggestedLoad(history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double, kind: EquipmentKind,
                              mode: ProgressionMode = .load) -> Double? {
        let repsInReserve = max(0, 10 - rpe)
        let effectiveReps = Double(reps.upperBound) + repsInReserve
        let target = history.bestEstimatedOneRepMax / (1 + effectiveReps / 30)
        guard var load = gym.load(atMost: target, on: kind) else { return nil }
        if mode != .load {
            let held = gym.load(atMost: history.recentHeaviestWeight, on: kind) ?? load
            guard (history.lastRPE ?? rpe) <= rpe + 0.001 else { return min(load, held) }
            if !history.lastWasLighter, earnedLoadStep(history, reps: reps, mode: mode),
               let next = gym.nextLoad(above: held, on: kind) {
                return next
            }
            return held
        }
        if load <= history.lastWeight + 0.001,
           let next = gym.nextLoad(above: history.lastWeight, on: kind),
           history.lastReps >= reps.upperBound + (isBigJump(from: history.lastWeight, to: next) ? Self.bigJumpExtraReps : 0),
           (history.lastRPE ?? rpe) <= rpe {
            load = next
        }
        return load
    }

    func isBigJump(from current: Double, to next: Double) -> Bool {
        current > 0 && (next - current) / current > Self.routineJumpFraction + 0.0001
    }

    /// Plates or per-hand weight, plus a tip when the planner is holding you
    /// at this weight because the next one up is a big jump.
    func notes(load: Double, history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double, kind: EquipmentKind,
               mode: ProgressionMode = .load) -> String? {
        var parts: [String] = []
        if let plates = loadNote(load: load, kind: kind) { parts.append(plates) }
        // Rep and set progression already wait for the extra reps (`progressionNote`).
        if mode == .load, abs(load - history.lastWeight) < 0.001, history.lastReps >= reps.upperBound,
           let next = gym.nextLoad(above: load, on: kind), isBigJump(from: load, to: next) {
            let goal = reps.upperBound + Self.bigJumpExtraReps
            if history.lastReps < goal {
                let weight = next.formatted(.number.precision(.fractionLength(0...2)))
                parts.append("The next weight up (\(weight) \(gym.unit.rawValue)) is a big jump: get \(goal) reps at this one first.")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    public func loadNote(load: Double, kind: EquipmentKind) -> String? {
        let unit = gym.unit.rawValue
        func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
        switch kind {
        case .barbell, .ezBar, .smithMachine:
            guard let plates = gym.plateBreakdown(total: load, on: kind) else { return nil }
            if plates.isEmpty { return "Empty bar" }
            return "\(plates.map(fmt).joined(separator: " + ")) \(unit) per side"
        case .dumbbell, .kettlebell:
            return "\(fmt(load)) \(unit) each hand"
        default:
            return nil
        }
    }

    /// Seconds of lifting in a working set (app estimate: 6-12 reps at a
    /// controlled tempo) and in a ramp set (lighter, fewer reps).
    public static let workSecondsPerSet = 45
    public static let rampWorkSeconds = 30
    /// Walking to the next station, loading plates, setting a seat: about two
    /// minutes between exercises (app estimate from gym practice).
    public static let transitionMinutes = 2.0

    /// Session length, honest about everything that isn't a working set:
    /// - the movement warm-up (`warmUpMinutes`: `WarmUpRoutine.Routine.minutes`
    ///   for the short and full tiers, 0 for off and ramp-only, the default);
    /// - each ramp set (`warmUpSets`): `rampWorkSeconds` + `RestTimer.warmUpRestSeconds`;
    /// - each working set: `workSecondsPerSet` + the rest the timer will run
    ///   for this `style` (`RestTimer.defaultSeconds`; balanced: 3.25 min for
    ///   big lifts, 2.25 for small ones), at about 60% in a superset
    ///   (`Supersets.timeFraction`: the pair shares one rest);
    /// - `transitionMinutes` between exercises;
    /// - drop stages and mini-sets (`TimeSaver.stageSeconds`), with no rest of their own.
    /// Counting rest by style matters: the timer runs the style's rest, so an
    /// estimate at the longer balanced rest trimmed muscle-style sessions
    /// short (a 60-min plan that took 40).
    public static func estimatedMinutes(_ exercises: [PlannedExercise], style: TrainingStyle = .balanced,
                                        warmUpMinutes: Int = 0) -> Int {
        let compound = Double(RestTimer.defaultSeconds(style: style, compound: true) + workSecondsPerSet) / 60
        let isolation = Double(RestTimer.defaultSeconds(style: style, compound: false) + workSecondsPerSet) / 60
        let ramp = Double(RestTimer.warmUpRestSeconds + rampWorkSeconds) / 60
        var total = Double(max(0, warmUpMinutes)) + transitionMinutes * Double(max(0, exercises.count - 1))
        for exercise in exercises {
            let perSet = ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound == true ? compound : isolation
            let fraction = exercise.supersetGroup == nil ? 1 : Supersets.timeFraction
            total += Double(exercise.sets) * perSet * fraction
            total += Double(exercise.warmUpSets?.count ?? 0) * ramp
            // Drop stages and mini-sets (`TimeSaver`): their reps plus the weight change or short rest.
            if let kind = exercise.lastSetKind, let stages = exercise.stages {
                total += Double(stages.reduce(0) { $0 + TimeSaver.stageSeconds(for: kind, reps: $1.reps) }) / 60
            }
        }
        return Int(total.rounded())
    }

    /// Plain-text summary of the gym, for the AI coach.
    public func gymSummary() -> String {
        let unit = gym.unit.rawValue
        func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
        var lines = ["Gym: \(gym.name). Weights in \(unit)."]
        let kinds = EquipmentKind.allCases.filter { gym.has($0) && $0 != .bodyweight }.map(\.label)
        lines.append("Equipment: \(kinds.joined(separator: ", ")).")
        if gym.has(.barbell) {
            let plates = gym.plates.filter { $0.pairs > 0 }.map { "\(fmt($0.weight))×\($0.pairs) pairs" }
            lines.append("Barbell \(fmt(gym.barbellWeight)) \(unit); plates: \(plates.joined(separator: ", ")).")
        }
        if gym.has(.dumbbell), let low = gym.dumbbells.min(), let high = gym.dumbbells.max() {
            lines.append("Dumbbells: \(gym.dumbbells.count) pairs from \(fmt(low)) to \(fmt(high)) \(unit).")
        }
        if gym.has(.cable) {
            lines.append("Cable stack: \(fmt(gym.cableStack.start))–\(fmt(gym.cableStack.max)) by \(fmt(gym.cableStack.step)).")
        }
        if gym.has(.machine) {
            lines.append("Machines: \(fmt(gym.machineStack.start))–\(fmt(gym.machineStack.max)) by \(fmt(gym.machineStack.step)).")
        }
        if gym.has(.kettlebell), !gym.kettlebells.isEmpty {
            lines.append("Kettlebells: \(gym.kettlebells.sorted().map(fmt).joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }
}
