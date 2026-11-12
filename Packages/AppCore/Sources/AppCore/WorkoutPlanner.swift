import Foundation

/// Movement patterns the planner builds sessions from. Each has a list of
/// exercises (IDs from the bundled exercise library), best first; the planner
/// picks the first one your gym can do.
public enum MovementSlot: String, Codable, Sendable, CaseIterable {
    case horizontalPress, inclinePress, verticalPress, chestFly, lateralRaise, triceps
    case verticalPull, horizontalRow, rearDelt, biceps, hammerCurl
    case squat, hinge, singleLeg, legCurl, legExtension, calves, core
    /// Hip thrusts and glute bridges: the one movement with the glutes as the
    /// main muscle (added 2026-11; audit §12).
    case hipThrust

    public var isCompound: Bool {
        switch self {
        case .horizontalPress, .inclinePress, .verticalPress, .verticalPull, .horizontalRow, .squat, .hinge, .singleLeg,
             .hipThrust: true
        default: false
        }
    }

    public var muscleGroup: MuscleGroup {
        switch self {
        case .horizontalPress, .inclinePress, .verticalPress, .chestFly, .lateralRaise, .triceps: .push
        case .verticalPull, .horizontalRow, .rearDelt, .biceps, .hammerCurl: .pull
        case .squat, .hinge, .singleLeg, .legCurl, .legExtension, .calves, .hipThrust: .legs
        case .core: .core
        }
    }

    /// Lower body, upper-body push or upper-body pull: the regions that each
    /// get a ramp on their first lift (`WorkoutPlanner.addWarmUps`).
    public var warmUpRegion: MuscleGroup { muscleGroup }

    /// A movement for the same main muscles to use when the gym has nothing
    /// for this one (a bodyweight gym has no pull-up bar but can row under a
    /// table; a dumbbell gym has no leg extension but can split squat), so
    /// the muscle isn't silently dropped (audit 2026-11 §12). Nil when
    /// there's no sensible stand-in.
    public var fallback: MovementSlot? {
        switch self {
        case .verticalPull: .horizontalRow
        case .horizontalRow: .verticalPull
        case .horizontalPress: .inclinePress
        case .inclinePress: .horizontalPress
        case .legExtension: .singleLeg
        case .legCurl: .hinge
        case .hipThrust: .hinge
        case .biceps: .hammerCurl
        case .hammerCurl: .biceps
        default: nil
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

    /// Slots in priority order (variant A); shorter sessions use the first
    /// few. This is what a session keeps, not the order it's done in: the
    /// planner does multi-joint lifts first (`WorkoutPlanner.liftOrder`),
    /// because lifts done early gain more strength while muscle growth
    /// doesn't depend on order (Nunes et al., Eur J Sport Sci 2021; ACSM
    /// position stand, Med Sci Sports Exerc 2009). Weekly targets and
    /// capacity (`VolumeProgression`) read this list.
    public var slots: [MovementSlot] { slots(variant: 0) }

    /// How many versions the focus alternates between (`slots(variant:)`).
    public var variantCount: Int {
        switch self {
        case .upper, .fullBody: 2
        default: 1
        }
    }

    /// The focus's slots for version A (0) or B (1), most important first.
    ///
    /// **Arms get their own work.** Presses and rows aren't enough for them:
    /// - Bench pressing alone grew the triceps' lateral head but barely its
    ///   long head; adding a triceps extension grew all of it (Brandão et al.,
    ///   J Strength Cond Res 2020, 43 men, 10 weeks).
    /// - Curls grew the elbow flexors about twice as much as rows (11% vs 5%;
    ///   Mannarino et al., J Strength Cond Res 2021, 10 untrained men, each
    ///   arm one exercise; small, so modest evidence).
    /// So a triceps extension and a curl rank straight after the first two
    /// or three compound lifts on push, pull and upper days, and push and
    /// pull days take a second arm exercise from 60 minutes (the planner
    /// picks a different one: an overhead extension then a pushdown, a curl
    /// then a hammer curl). Rows and pulldowns already work the rear delts
    /// (Franke et al., J Sports Med Phys Fitness 2015, EMG; cited from memory), so on upper day B the
    /// direct rear-delt movement waits for a long session.
    ///
    /// **Legs get a leg curl and a leg extension early.** Squats grew the
    /// vasti and glutes but not the rectus femoris or the hamstrings (Kubo et
    /// al., Eur J Appl Physiol 2019), so both rank before a second
    /// squat-pattern lift, and the lower day has a leg extension too. The
    /// curl ranks first: when time runs out the last small lift goes, and
    /// the quads still have the squat.
    ///
    /// **Every muscle each week.** No compound lift trains the calves, and
    /// the abs get little from them, so a calf raise and a core movement sit
    /// inside the first five of the leg, lower, pull and full-body lists: a
    /// 45-minute week still reaches them (each major muscle group at least
    /// twice a week: ACSM position stand 2026; twice beat once for growth:
    /// Schoenfeld, Ogborn & Krieger, Sports Med 2016). With the abs finisher
    /// on, the core movement gives its place to the next one in the list.
    ///
    /// Upper and full-body days alternate two versions, so a week of them
    /// covers side delts, an incline and an overhead press, and both pulls,
    /// with pushing and pulling sets about even across the pair (ACSM
    /// position stand, Med Sci Sports Exerc 2026: every major muscle group at
    /// least twice a week; some exercise variation spreads regional growth:
    /// Kassiano et al., J Strength Cond Res 2022, review). Side delts rank
    /// before the incline press on push days so sessions under an hour keep
    /// them. The exact lists are the app's choice inside that evidence.
    public func slots(variant: Int) -> [MovementSlot] {
        let b = variant % max(1, variantCount) == 1
        switch self {
        case .push: return [.horizontalPress, .verticalPress, .lateralRaise, .triceps, .inclinePress, .triceps]
        case .pull: return [.verticalPull, .horizontalRow, .biceps, .rearDelt, .core, .hammerCurl]
        case .legs: return [.squat, .hinge, .legCurl, .legExtension, .calves, .singleLeg]
        case .upper:
            // A's fifth is the curl and B's the triceps extension, so 45-minute upper days share them out.
            return b ? [.inclinePress, .verticalPull, .horizontalRow, .verticalPress, .triceps, .biceps]
                     : [.horizontalPress, .horizontalRow, .verticalPull, .lateralRaise, .biceps, .triceps]
        case .lower: return [.squat, .hinge, .legCurl, .calves, .core, .legExtension]
        case .fullBody:
            // One press and one pull each; A's small lifts are calves and core, B's core and
            // side delts, so a week of full-body days reaches every muscle.
            return b ? [.hinge, .inclinePress, .horizontalRow, .singleLeg, .core, .lateralRaise]
                     : [.squat, .horizontalPress, .verticalPull, .hinge, .calves, .core]
        }
    }

    /// The seventh movement for a long session (`WorkoutPlanner.longSessionMinutes`)
    /// in version A.
    public var extraSlot: MovementSlot { extraSlot(variant: 0) }

    /// The seventh movement for a long session: the first of `extraSlots`.
    public func extraSlot(variant: Int) -> MovementSlot {
        extraSlots(variant: variant).first ?? .core
    }

    /// Movements beyond the six, in order: the first is the long session's
    /// seventh; the next stands in when the core movement is left out (the
    /// abs finisher is on) and is what `fill` adds when there's still time.
    /// Each is a pattern the version hasn't covered, else a second exercise
    /// for a muscle with room (the planner picks a different exercise).
    /// Full-body days get their direct arm work here: with one press and one
    /// pull a session, arms are the muscles furthest under the weekly band.
    public func extraSlots(variant: Int) -> [MovementSlot] {
        let b = variant % max(1, variantCount) == 1
        switch self {
        case .push: return [.chestFly, .lateralRaise]
        case .pull: return [.horizontalRow, .verticalPull]
        case .legs: return [.hipThrust, .calves]
        case .upper: return b ? [.rearDelt, .lateralRaise] : [.verticalPress, .rearDelt]
        case .lower: return [.singleLeg, .hipThrust]
        case .fullBody: return b ? [.triceps, .calves] : [.biceps, .lateralRaise]
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

extension CatalogExercise {
    /// Done one side at a time, so each set takes about twice the work time
    /// (`WorkoutPlanner.estimatedMinutes`; audit 2026-11 §10).
    public var isUnilateral: Bool { ExerciseCatalog.unilateralIDs.contains(id) }
}

public enum ExerciseCatalog {
    static func ex(_ id: String, _ name: String, _ load: EquipmentKind?, _ requires: EquipmentKind...) -> CatalogExercise {
        CatalogExercise(id: id, name: name, load: load, requires: Set(requires).union(load.map { [$0] } ?? []))
    }

    /// Exercises done one side at a time (`CatalogExercise.isUnilateral`).
    public static let unilateralIDs: Set<String> = [
        "Split_Squat_with_Dumbbells", "Barbell_Lunge", "Bodyweight_Walking_Lunge", "Dumbbell_Lunges",
        "One-Arm_Dumbbell_Row", "Dumbbell_One-Arm_Triceps_Extension", "One-Arm_Kettlebell_Swings",
        "Single_Leg_Glute_Bridge"
    ]

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
            // Second, so a session's second triceps exercise works the arm at
            // the side instead of repeating the overhead position (variety
            // across positions: Kassiano et al. 2022, review; app choice).
            ex("Triceps_Pushdown_-_Rope_Attachment", "Rope Pushdown", .cable),
            ex("Dumbbell_One-Arm_Triceps_Extension", "Overhead Triceps Extension", .dumbbell),
            ex("EZ-Bar_Skullcrusher", "EZ-Bar Skullcrusher", .ezBar, .bench),
            ex("Machine_Triceps_Extension", "Machine Triceps Extension", .machine),
            // Barbell-only gyms: a close-grip press before bench dips, which are hard on the shoulder.
            ex("Close-Grip_Barbell_Bench_Press", "Close-Grip Bench Press", .barbell, .bench),
            ex("Dips_-_Triceps_Version", "Dips", nil, .dipStation),
            ex("Bench_Dips", "Bench Dips", nil, .bench)
        ],
        .verticalPull: [
            ex("Wide-Grip_Lat_Pulldown", "Lat Pulldown", .cable),
            ex("Pullups", "Pull-Ups", nil, .pullUpBar),
            ex("Chin-Up", "Chin-Ups", nil, .pullUpBar),
            ex("Band_Assisted_Pull-Up", "Band-Assisted Pull-Ups", nil, .pullUpBar, .bands)
        ],
        .horizontalRow: [
            ex("Bent_Over_Barbell_Row", "Barbell Row", .barbell),
            ex("Seated_Cable_Rows", "Seated Cable Row", .cable),
            ex("One-Arm_Dumbbell_Row", "One-Arm Dumbbell Row", .dumbbell, .bench),
            ex("Leverage_Iso_Row", "Machine Row", .machine),
            ex("Dumbbell_Incline_Row", "Chest-Supported Dumbbell Row", .dumbbell, .bench),
            ex("Lying_T-Bar_Row", "Chest-Supported T-Bar Row", .machine),
            // No equipment at all: a row under a low bar or a sturdy table.
            ex("Inverted_Row", "Inverted Row (low bar or sturdy table)", nil)
        ],
        .rearDelt: [
            ex("Face_Pull", "Face Pull", .cable),
            ex("Reverse_Flyes", "Reverse Fly", .dumbbell),
            ex("Reverse_Machine_Flyes", "Reverse Pec Deck", .machine),
            ex("Band_Pull_Apart", "Band Pull-Apart", nil, .bands)
        ],
        .biceps: [
            // Dumbbells first: each arm works on its own and the wrist can turn, and their
            // growth is no different from a barbell's in the studies there are (app choice,
            // and the user's preference). A lift you've logged still comes first (`choose`).
            ex("Dumbbell_Bicep_Curl", "Dumbbell Curl", .dumbbell),
            // Arm behind the body: the biceps works stretched. Incline curls
            // grew the upper part of the elbow flexors more and preacher
            // curls the lower part (Kassiano et al., Int J Sports Med 2025,
            // 63 untrained women), so neither is "the best": a second curl
            // in a session is the incline one, for a different position.
            ex("Incline_Dumbbell_Curl", "Incline Dumbbell Curl", .dumbbell, .bench),
            ex("Barbell_Curl", "Barbell Curl", .barbell),
            ex("EZ-Bar_Curl", "EZ-Bar Curl", .ezBar),
            ex("Machine_Bicep_Curl", "Machine Curl", .machine),
            ex("Machine_Preacher_Curls", "Machine Preacher Curl", .machine)
        ],
        .hammerCurl: [
            ex("Hammer_Curls", "Hammer Curl", .dumbbell),
            ex("Cable_Hammer_Curls_-_Rope_Attachment", "Cable Hammer Curl", .cable)
        ],
        .squat: [
            ex("Barbell_Squat", "Back Squat", .barbell, .squatRack),
            ex("Leg_Press", "Leg Press", .machine),
            ex("Hack_Squat", "Hack Squat", .machine),
            ex("Smith_Machine_Squat", "Smith Machine Squat", .smithMachine),
            ex("Goblet_Squat", "Goblet Squat", .kettlebell),
            ex("Dumbbell_Squat", "Dumbbell Squat", .dumbbell),
            ex("Bodyweight_Squat", "Bodyweight Squat", nil)
        ],
        .hinge: [
            ex("Romanian_Deadlift", "Romanian Deadlift", .barbell),
            ex("Barbell_Deadlift", "Deadlift", .barbell),
            ex("Stiff-Legged_Dumbbell_Deadlift", "Dumbbell Romanian Deadlift", .dumbbell),
            ex("One-Arm_Kettlebell_Swings", "Kettlebell Swing", .kettlebell),
            // Machine-only gyms: the back-extension station (bodyweight, hold a plate to load it).
            ex("Hyperextensions_Back_Extensions", "Back Extension", nil, .machine)
        ],
        .singleLeg: [
            ex("Split_Squat_with_Dumbbells", "Dumbbell Split Squat", .dumbbell),
            ex("Barbell_Lunge", "Barbell Lunge", .barbell, .squatRack),
            ex("Dumbbell_Lunges", "Dumbbell Lunge", .dumbbell),
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
            ex("Calf_Raise_On_A_Dumbbell", "Dumbbell Calf Raise", .dumbbell),
            ex("Seated_Calf_Raise", "Seated Calf Raise", .machine)
        ],
        // Glutes as the main muscle: hip thrusts load the glutes hardest at
        // full hip extension (Contreras et al., J Appl Biomech 2015, EMG; a
        // growth advantage over squats isn't established: Plotkin et al.,
        // Front Physiol 2023).
        .hipThrust: [
            ex("Barbell_Hip_Thrust", "Hip Thrust", .barbell, .bench),
            ex("Barbell_Glute_Bridge", "Barbell Glute Bridge", .barbell),
            ex("Pull_Through", "Cable Pull-Through", .cable),
            ex("Single_Leg_Glute_Bridge", "Single-Leg Glute Bridge", nil)
        ],
        // The first three are the planner's long-standing picks for the core
        // slot; the rest give the abs finisher (`AbsFinisher`) one option per
        // trunk pattern in most gyms. Patterns, holds and per-side moves are
        // tagged in `CoreMoves`; library IDs from free-exercise-db (guides,
        // images and muscles come from there). Holds are named with
        // "(seconds)": a set's reps are logged as seconds held.
        .core: [
            ex("Hanging_Leg_Raise", "Hanging Leg Raise", nil, .pullUpBar),
            ex("Cable_Crunch", "Cable Crunch", .cable),
            ex("Plank", "Plank (seconds)", nil),
            ex("Crunches", "Crunch", nil),
            ex("Decline_Crunch", "Decline Crunch", nil, .bench),
            ex("Air_Bike", "Bicycle Crunch", nil),
            ex("Cable_Reverse_Crunch", "Cable Reverse Crunch", .cable),
            ex("Knee_Hip_Raise_On_Parallel_Bars", "Captain's Chair Knee Raise", nil, .dipStation),
            ex("Reverse_Crunch", "Reverse Crunch", nil),
            ex("Dead_Bug", "Dead Bug", nil),
            ex("Barbell_Ab_Rollout_-_On_Knees", "Barbell Rollout (knees)", nil, .barbell),
            ex("Pallof_Press", "Pallof Press", .cable),
            ex("Dumbbell_Side_Bend", "Dumbbell Side Bend", .dumbbell),
            ex("Side_Bridge", "Side Plank (seconds)", nil)
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
        case .horizontalRow: ["Upper back", "Lats", "Biceps"]
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
        case .hipThrust: ["Glutes", "Hamstrings"]
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
    /// The reps to aim for on each working set today (`WorkoutPlanner.progression`:
    /// one more than last time at the same weight, what the new weight allows
    /// after a step up, the middle of the range for an estimated first
    /// weight). Nil = the top of `reps` (no history, a fixed weight).
    /// Optional, so older plans decode.
    public var targetReps: Int? = nil
    /// Rest after a set (after both halves of a superset), in seconds, when the
    /// plan sets its own: the abs finisher's short circuit rest
    /// (`AbsFinisher.restSeconds`). Nil = the rest timer's usual choice.
    /// Optional, so older plans decode.
    public var restSeconds: Int? = nil
    /// True for an exercise of the abs finisher (`AbsFinisher`), added on top
    /// of the session's time. Optional, so older plans decode.
    public var isFinisher: Bool? = nil
    /// What the last block's report changed for this exercise ("6-10 reps:
    /// applied from the Block 3 report", `WorkoutPlanner.BlockPreferences`).
    /// Nil when nothing. Optional, so older plans decode.
    public var adjustmentNote: String? = nil
}

extension PlannedExercise {
    /// Reps each working set aims for today: `targetReps`, else the top of the range.
    public var repsToday: Int { targetReps ?? reps.upperBound }
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
    /// Why the plan runs shorter than the time picked, or fills it past this
    /// week's set targets (`WorkoutPlanner.lengthNote`). Nil when neither.
    /// Optional, so saved plans still decode.
    public var lengthNote: String? = nil

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
    /// Changes applied from the last block's report for this block
    /// (`NextBlockAdjustments.plannerPreferences`): rep ranges and variation swaps.
    public var blockPreferences: BlockPreferences? = nil

    /// Rep ranges and preferred variations from the last block's report.
    /// A swap only ever reorders what `alternatives` already allows (the gym's
    /// equipment, the never-again list, pain), so it never plans an exercise
    /// the gym can't support or the pain log rules out.
    public struct BlockPreferences: Sendable, Equatable {
        /// Exercise ID → its rep range this block.
        public var repRanges: [String: ClosedRange<Int>]
        /// Stalled exercise ID → the variation preferred in its place.
        public var swaps: [String: String]
        /// Exercise ID → the line shown with it (`PlannedExercise.adjustmentNote`).
        public var notes: [String: String]

        public init(repRanges: [String: ClosedRange<Int>] = [:], swaps: [String: String] = [:], notes: [String: String] = [:]) {
            self.repRanges = repRanges
            self.swaps = swaps
            self.notes = notes
        }
    }

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

    /// The exercise a plan uses for a slot: one you've logged, most recently
    /// done first, else the first option (`alternatives`). Keeping the
    /// variant you actually do keeps its history, so double progression
    /// works from your own numbers; a plan that swapped your dumbbell curl
    /// for a barbell curl had to estimate a cautious first-time weight
    /// (`LoadEstimator`, 85%, top of the range: about half the weight at 15
    /// reps). A pain regression the filter put first (`ExerciseFilter.apply`)
    /// still wins: a logged lift that loads a 3-5/10 area isn't preferred.
    public func choose(_ slot: MovementSlot, excluding used: Set<String>,
                       history: [String: ExerciseHistory]) -> CatalogExercise? {
        let options = alternatives(for: slot).filter { !used.contains($0.id) }
        guard let first = options.first else { return nil }
        if let filter = exerciseFilter, filter.regressArea(forExerciseID: first.id, slot: slot) == nil,
           PainGuard.regressionSlot(for: first.id) != nil {
            return first
        }
        let logged = options.filter { option in
            history[option.id] != nil && exerciseFilter?.regressArea(forExerciseID: option.id, slot: slot) == nil
        }
        let picked = logged.max { (history[$0.id]?.lastDate ?? .distantPast) < (history[$1.id]?.lastDate ?? .distantPast) } ?? first
        // The block report's swap: the new variation in place of the stalled one, if it's an option here.
        if let swapID = blockPreferences?.swaps[picked.id], let swap = options.first(where: { $0.id == swapID }),
           exerciseFilter?.regressArea(forExerciseID: swap.id, slot: slot) == nil {
            return swap
        }
        return picked
    }

    /// Every catalog exercise for a slot that this gym supports, best first.
    public func alternatives(for slot: MovementSlot) -> [CatalogExercise] {
        let supported = (ExerciseCatalog.options[slot] ?? []).filter { exercise in
            exercise.requires.allSatisfy { gym.has($0) } &&
            (exercise.load.map { !gym.achievableLoads(for: $0).isEmpty } ?? true)
        }
        let allowed = exerciseFilter?.apply(to: supported, slot: slot, gym: gym) ?? supported
        return preferringSwaps(allowed, slot: slot)
    }

    /// The block report's preferred variation moved just ahead of the
    /// exercise it replaces, when both are allowed here and it doesn't load
    /// a painful area (a pain regression the filter put first stays first).
    func preferringSwaps(_ options: [CatalogExercise], slot: MovementSlot) -> [CatalogExercise] {
        guard let swaps = blockPreferences?.swaps, !swaps.isEmpty else { return options }
        var result = options
        for (fromID, toID) in swaps.sorted(by: { $0.key < $1.key }) {
            guard let from = result.firstIndex(where: { $0.id == fromID }),
                  let to = result.firstIndex(where: { $0.id == toID }), to > from,
                  exerciseFilter?.regressArea(forExerciseID: toID, slot: slot) == nil else { continue }
            let preferred = result.remove(at: to)
            result.insert(preferred, at: from)
        }
        return result
    }

    /// The rep range and per-set effort for a slot in this style. `heavy`
    /// marks the session's first big lift in the strength + muscle style.
    ///
    /// Effort: big lifts stop 2-3 reps short of failure; small lifts go
    /// closer, since muscle growth benefits from proximity to failure while
    /// strength barely does and failure adds fatigue (Robinson et al., Sports
    /// Med 2024). Muscle-style small lifts are 8-12 (was 10-15): growth is
    /// similar across loads near failure (Schoenfeld et al., J Strength Cond
    /// Res 2017), and reps-in-reserve guesses get worse on long sets
    /// (Halperin et al., Sports Med 2022). The heavy first lift (4-6 reps,
    /// about 80-85% 1RM) is where strength responds best (ACSM position
    /// stand, Med Sci Sports Exerc 2026: ≥80% 1RM, early in the session).
    public func repsAndEffort(slot: MovementSlot, sessionRPE rpe: Double, heavy: Bool = false) -> (reps: ClosedRange<Int>, rpe: Double) {
        let compound = slot.isCompound
        switch style {
        case .balanced:
            return (compound ? 6...8 : (slot == .core ? 10...15 : 10...12), compound ? rpe : min(9.5, rpe + 1))
        case .strength:
            return (compound ? 3...6 : (slot == .core ? 8...12 : 8...10), compound ? min(rpe, 8) : min(9, rpe + 0.5))
        case .muscle:
            return (compound ? 6...10 : (slot == .core ? 10...15 : 8...12), compound ? min(8.5, rpe + 0.5) : min(9.5, rpe + 1.5))
        case .strengthAndMuscle:
            if compound && heavy { return (4...6, min(8.5, rpe + 0.5)) }
            return (compound ? 6...10 : (slot == .core ? 10...15 : 8...12), compound ? min(8.5, rpe + 0.5) : min(9.5, rpe + 1.5))
        case .endurance:
            return (compound ? 10...15 : 12...20, compound ? min(rpe, 7.5) : min(8.5, rpe + 0.5))
        }
    }

    /// True when the exercise at `position` in a session is its heavy lift:
    /// the first one, if it is a big lift, in the strength + muscle style.
    public func isHeavy(slot: MovementSlot, position: Int?) -> Bool {
        style == .strengthAndMuscle && slot.isCompound && position == 0
    }

    /// Sets, reps, effort and load for one exercise in a session. With
    /// history the load follows double progression (`suggestedLoad`) and the
    /// change is written out (`progressionNote`); without it a starting
    /// weight is estimated from your other lifts or body weight
    /// (`LoadEstimator`), else the note says to find one. Bodyweight lifts
    /// with history add a rep a session, then say how to make them harder
    /// (`bodyweightProgression`). `position` is the exercise's place in the
    /// session (the first big lift is heavy in the strength + muscle style);
    /// `setsFixed` is true when this week's set targets fix its sets, so set
    /// progression can't add one and the lift moves by load instead.
    public func prescribe(
        _ choice: CatalogExercise,
        slot: MovementSlot,
        minutes: Int,
        sessionRPE rpe: Double,
        history: [String: ExerciseHistory],
        lifter: LoadEstimator.Lifter = .unknown,
        position: Int? = nil,
        setsFixed: Bool = false
    ) -> PlannedExercise {
        let compound = slot.isCompound
        let sets = Self.baseSets(compound: compound, minutes: minutes)
        let heavy = isHeavy(slot: slot, position: position)
        let prescription = repsAndEffort(slot: slot, sessionRPE: rpe, heavy: heavy)
        var reps = prescription.reps
        let setRPE = prescription.rpe
        // A hold (plank, side plank) is prescribed in seconds, logged as reps (`CoreMoves`).
        let isHold = CoreMoves.move(id: choice.id)?.isHold == true
        if isHold {
            reps = CoreMoves.holdSeconds
        } else if let range = blockPreferences?.repRanges[choice.id] {
            // The block report's rep range for a stalled lift (`NextBlockAdjustments`).
            reps = range
        }
        var planned = PlannedExercise(
            exerciseID: choice.id, name: choice.name, sets: sets, reps: reps,
            rpe: setRPE, load: nil, loadKind: choice.load, note: nil
        )
        if !isHold { planned.adjustmentNote = blockPreferences?.notes[choice.id] }
        // The style's own rest where it differs from the timer's usual (`RestTimer`).
        if heavy { planned.restSeconds = RestTimer.heavyLiftSeconds }
        if let kind = choice.load {
            if let past = history[choice.id] {
                var mode = progressionMode(for: choice.id, kind: kind, compound: compound, at: past.lastWeight)
                // Weekly set targets fix the sets, so a set can't be added: move the load instead.
                if mode == .sets, setsFixed { mode = .load }
                let today = progression(history: past, reps: reps, rpe: setRPE, kind: kind, mode: mode,
                                        lowerBody: slot.muscleGroup == .legs)
                planned.load = today?.load
                planned.targetReps = today?.targetReps
                if let load = planned.load {
                    planned.note = notes(load: load, history: past, reps: reps, rpe: setRPE, kind: kind, mode: mode)
                    planned.progressionNote = progressionNote(load: load, history: past, reps: reps, mode: mode, rpe: setRPE,
                                                              loadKind: kind, target: planned.targetReps)
                    // Set progression: one more set than last time, before the
                    // block, the week's targets and the time fit (`plan`).
                    if mode == .sets, let more = progressedSets(load: load, history: past, reps: reps, rpe: setRPE) {
                        planned.sets = max(planned.sets, more)
                    }
                }
            } else if let estimate = LoadEstimator.estimate(exerciseID: choice.id, reps: reps, rpe: setRPE,
                                                            history: history, lifter: lifter, gym: gym) {
                planned.load = estimate.load
                // The estimate is for the middle of the range ("aim for 8").
                planned.targetReps = estimate.reps > 0 ? estimate.reps : nil
                planned.note = [estimate.note, loadNote(load: estimate.load, kind: kind)].compactMap { $0 }.joined(separator: ". ")
            } else {
                let middle = LoadEstimator.estimateReps(reps)
                planned.note = "First time: pick a weight you could lift about \(middle + Int(10 - setRPE)) times, and do \(middle)."
            }
        } else if !isHold, let past = history[choice.id], past.lastReps > 0 {
            bodyweightProgression(&planned, history: past)
        }
        // Rep targets past the top (rep progression, a big next jump) stretch the range shown.
        if let target = planned.targetReps, target > planned.reps.upperBound {
            planned.reps = planned.reps.lowerBound...target
        }
        return planned
    }

    /// Bodyweight lifts (pull-ups, dips, push-ups): one more rep than last
    /// time up to `bigJumpExtraReps` past the top of the range, then a note
    /// to add weight or move to a harder version; under the bottom of the
    /// range, a note to use assistance. Adding reps grows muscle and
    /// strength about as well as adding load (Plotkin et al., PeerJ 2022);
    /// the steps are the app's choice (audit 2026-11 §11).
    func bodyweightProgression(_ planned: inout PlannedExercise, history: ExerciseHistory) {
        let reps = planned.reps
        let top = reps.upperBound + Self.bigJumpExtraReps
        let effortHeld = (history.lastRPE ?? planned.rpe) <= planned.rpe + 0.001
        if history.lastReps < reps.lowerBound {
            planned.targetReps = reps.lowerBound
            planned.progressionNote = "Last time \(history.lastReps) reps: use an assisted machine or a band, or an easier version, to get \(reps.lowerBound)"
            return
        }
        if history.lastReps >= top, effortHeld {
            planned.targetReps = top
            let unit = gym.unit == .kg ? "2.5-5 kg" : "5-10 lb"
            planned.progressionNote = "You hit \(history.lastReps) reps: add \(unit) (a dip belt or a dumbbell) or a harder version"
            return
        }
        let target = effortHeld ? min(history.lastReps + 1, top) : max(reps.lowerBound, min(history.lastReps, top) - 1)
        planned.targetReps = max(reps.lowerBound, target)
        planned.progressionNote = effortHeld
            ? "Aim for \(planned.targetReps ?? target) reps: one more than last time"
            : "\(planned.targetReps ?? target) reps for today's effort"
    }

    /// "+5 lb from last time: you hit 8 reps at RPE 7", "Same weight, aim
    /// for 7 reps; the weight goes up once you hit 8", or "−10 lb from last time for today's
    /// effort". Makes the double progression visible. With rep or set
    /// progression (`ProgressionMode`) the held weight says what to add
    /// instead. `rpe` is today's target (nil: as last time); `loadKind` lets
    /// the note see a big next jump (the top moves up `bigJumpExtraReps`).
    func progressionNote(load: Double, history: ExerciseHistory, reps: ClosedRange<Int>, mode: ProgressionMode = .load,
                         rpe: Double? = nil, loadKind: EquipmentKind? = nil, target: Int? = nil) -> String {
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
            // After a step, the reps the new weight allows (`progression`).
            let aim = target.map { ". Aim for \($0) reps" } ?? ""
            if let last = history.lastRPE, let rpe, last <= rpe - Self.catchUpGap + 0.001, history.lastReps >= reps.lowerBound {
                return "+\(fmt(delta)) \(unit): last time was easier than planned (\(history.lastReps) reps at RPE \(last.formatted()))\(aim)"
            }
            return "+\(fmt(delta)) \(unit) from last time: you hit \(history.lastReps) reps\(effort)\(aim)"
        }
        if delta < -0.001 {
            return "−\(fmt(-delta)) \(unit) from last time for today's effort"
        }
        let goal = reps.upperBound + Self.bigJumpExtraReps
        let today = rpe ?? history.lastRPE ?? 8
        // An easier day at the same weight: a rep fewer than last time (`progression`).
        guard isHeldAtLastWeight(load: load, history: history, rpe: today) else {
            let count = target ?? max(reps.lowerBound, min(max(history.lastReps, reps.lowerBound), reps.upperBound) - 1)
            // Half a point over the target: same weight and reps, no ease (`progression`).
            if !history.lastWasLighter, let last = history.lastRPE, last <= today + VolumeProgression.effortTolerance + 0.001 {
                return "Same weight, \(count) reps again: last time was a little harder than planned"
            }
            return "Same weight, \(count) reps for today's effort"
        }
        // The gym's heaviest weight: reps build past the range instead (`extendedReps`).
        if let kind = loadKind, gym.nextLoad(above: load, on: kind) == nil {
            let aim = target ?? max(reps.lowerBound, min(history.lastReps + 1, reps.upperBound))
            return "Your gym's heaviest: aim for \(aim) reps. Reps go past the range here to keep the sets hard"
        }
        // Reps past the range while the next weight is a jump out of reach (`extendedReps`).
        if let target, target > history.lastReps + 1 || target > goal,
           let last = history.lastRPE, last <= today - Self.catchUpGap + 0.001 {
            return "Same weight, aim for \(target) reps: last time was easy (\(history.lastReps) reps at RPE \(last.formatted())) and the next weight up is a big jump"
        }
        switch mode {
        case .load:
            // Double progression (`progression`): one more rep at the same weight.
            var top = reps.upperBound
            if let kind = loadKind, let next = gym.nextLoad(above: load, on: kind), isBigJump(from: load, to: next) {
                top += Self.bigJumpExtraReps
            }
            let target = target ?? max(reps.lowerBound, min(history.lastReps + 1, top))
            if target >= top { return "Same weight: hit \(target) reps and it goes up next time" }
            return "Same weight, aim for \(target) reps; the weight goes up once you hit \(top)"
        case .reps:
            let target = repTarget(load: load, history: history, reps: reps, rpe: today)
                ?? max(reps.lowerBound, min(history.lastReps + 1, goal))
            return "Same weight as last time: aim for \(target) reps; the weight goes up once you hit \(goal)"
        case .sets:
            let most = TrainingBlock.setRange.upperBound
            if progressedSets(load: load, history: history, reps: reps, rpe: today) != nil {
                return "Same weight, one more set: you hit \(reps.upperBound) reps; the weight goes up once you reach \(most) sets"
            }
            return "Same weight: hit \(reps.upperBound) reps to add a set; the weight goes up once you reach \(most) sets"
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
    /// "big jump" is the next weight up from `load` being over 10% heavier,
    /// or over 5% for a single-joint lift (`smallLiftJumpFraction`).
    public func progressionMode(for exerciseID: String, kind: EquipmentKind?, compound: Bool, at load: Double) -> ProgressionMode {
        if let own = progressionModes[exerciseID] { return own }
        var bigJump = false
        if let kind, let next = gym.nextLoad(above: load, on: kind) {
            bigJump = isBigJump(from: load, to: next, compound: compound)
        }
        return ProgressionMode.suggested(kind: kind, compound: compound, bigJump: bigJump)
    }

    /// Builds a session. With a `block` week the sets scale by the week's
    /// multiplier (`TrainingBlock.scaledSets`) and the effort comes from its
    /// RIR target, still lowered on a low-recovery day. Compound lifts get
    /// warm-up ramp sets (`WarmUp`), then sessions that overrun the time are
    /// trimmed, paired into supersets, then shortened (`fit`), and sessions
    /// that come in well under it get sets or an extra exercise (`fill`), so
    /// the estimate lands as close under the time you picked as the sets allow.
    /// Long sessions (`longSessionMinutes`) add the focus's `extraSlot` and a
    /// fourth set on isolation work. `focusReason` ("because of the soreness
    /// you reported") goes into the plan's `rationale`. Body weight, sex,
    /// training status, age and any numbers you gave (`anchorOneRepMaxKg`)
    /// feed starting weights for lifts without history (`LoadEstimator`);
    /// `warmUpMinutes` is the movement warm-up (`WarmUpRoutine`) the session
    /// starts with: 0 (the default) for the off and ramp-only tiers, the
    /// routine's minutes for short and full.
    /// `prioritySlots` (from `MuscleCoverage`) are movements for muscles
    /// behind on the week's sets: they go straight after the compound lifts,
    /// so a short session drops a default isolation movement instead of them.
    /// `includeCore` false leaves the core movement out when the abs finisher
    /// (`AbsFinisher`) is on: the finisher trains abs on top of the time, so
    /// `fit` can't trim them away and they aren't trained twice. `variant`
    /// picks version A (0) or B (1) of an upper or full-body day
    /// (`WorkoutFocus.slots(variant:)`); nil alternates from your history
    /// (`suggestedVariant`).
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
        muscleSetGoals: [Muscle: Int] = [:],
        includeCore: Bool = true,
        variant: Int? = nil,
        age: Int? = nil,
        anchorOneRepMaxKg: [MovementSlot: Double] = [:]
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
                                       muscleSetGoals: muscleSetGoals, includeCore: includeCore, variant: variant,
                                       age: age, anchorOneRepMaxKg: anchorOneRepMaxKg)
            let before = workout.estimatedMinutes
            exerciseFilter.capLoads(&workout, planner: guarded, history: history, warmUpMinutes: warmUpMinutes)
            // Lighter loads can mean fewer ramp sets: say so if the plan now runs short.
            if workout.lengthNote == nil, let estimate = workout.estimatedMinutes, estimate != before {
                workout.lengthNote = Self.lengthNote(minutes: workout.minutes, estimate: estimate,
                                                     deload: block?.isDeload == true, filledPastGoals: false,
                                                     warmUpMinutes: warmUpMinutes)
            }
            return workout
        }
        let minutes = max(0, minutes)
        let rpe = Self.targetRPE(recovery: recovery, block: block)
        let lifter = LoadEstimator.Lifter(bodyMassKg: bodyMassKg, sex: sex, status: trainingStatus, age: age,
                                          anchorOneRepMaxKg: anchorOneRepMaxKg)
        let version = variant ?? Self.suggestedVariant(focus: focus, history: history)
        let exerciseCount = Self.exerciseCount(minutes: minutes)
        let slots = Self.orderedSlots(focus: focus, minutes: minutes, priority: prioritySlots, includeCore: includeCore,
                                      variant: version)
        var exercises: [PlannedExercise] = []
        // Sets earned by set progression (`progressedSets`), by exercise.
        var earnedSets: [String: Int] = [:]
        for slot in slots {
            // A repeated slot (the long session's extra) gets a different exercise.
            let used = Set(exercises.map(\.exerciseID))
            guard exercises.count < exerciseCount else { continue }
            // Nothing for this movement here: a stand-in for the same muscles, if the gym has one.
            let found = pick(slot, excluding: used, minutes: minutes, rpe: rpe, history: history, lifter: lifter,
                             position: exercises.count, goals: muscleSetGoals)
                ?? slot.fallback.flatMap { stand in
                    alternatives(for: slot).isEmpty
                        ? pick(stand, excluding: used, minutes: minutes, rpe: rpe, history: history, lifter: lifter,
                               position: exercises.count, goals: muscleSetGoals)
                        : nil
                }
            guard var planned = found else { continue }
            let plannedSlot = ExerciseCatalog.slot(for: planned.exerciseID) ?? slot
            var base = Self.baseSets(compound: plannedSlot.isCompound, minutes: minutes)
            if let block {
                // Scale the base sets, so a set added by set progression isn't
                // scaled again; the deload cuts it like any other set.
                base = TrainingBlock.scaledSets(base, multiplier: block.setMultiplier)
                planned.sets = block.isDeload ? base : max(base, planned.sets)
            }
            if planned.sets > base { earnedSets[planned.exerciseID] = planned.sets }
            exercises.append(planned)
        }
        // Chosen by priority, done compound lifts first (`liftOrder`).
        exercises = Self.liftOrder(exercises)
        // This week's per-muscle targets (`VolumeProgression`) set the sets; `fit` still trims to the time.
        let deload = block?.isDeload == true
        Self.applySetGoals(&exercises, goals: muscleSetGoals, deload: deload)
        Self.capSessionVolume(&exercises, minutes: minutes, deload: deload)
        // Ramp sets first, so the time they take counts when fitting.
        addWarmUps(&exercises, minutes: minutes)
        Self.fit(&exercises, minutes: minutes, style: style, warmUpMinutes: warmUpMinutes, deload: deload)
        // A muscle with a weekly target already has its sets; the others keep an earned set if time allows.
        let targeted = Set(muscleSetGoals.keys)
        earnedSets = earnedSets.filter { id, _ in
            guard let exercise = exercises.first(where: { $0.exerciseID == id }) else { return false }
            return VolumeProgression.primaryMuscle(exercise).map { !targeted.contains($0) } ?? true
        }
        Self.keepEarnedSets(&exercises, earned: earnedSets, minutes: minutes, style: style, warmUpMinutes: warmUpMinutes,
                            deload: deload)
        // A deload week is meant to be short; every other session fills the time.
        var filledPastGoals = false
        if !deload {
            filledPastGoals = fill(&exercises, focus: focus, minutes: minutes, rpe: rpe, history: history, lifter: lifter,
                                   warmUpMinutes: warmUpMinutes, goals: muscleSetGoals, variant: version)
        }
        var workout = PlannedWorkout(focus: focus, title: focus.title, minutes: minutes, targetRPE: rpe, exercises: exercises, unit: gym.unit)
        workout.blockWeek = block
        workout.rationale = Self.rationale(focus: focus, focusReason: focusReason, minutes: minutes, recovery: recovery,
                                           rpe: rpe, block: block, exercises: exercises)
        workout.rationaleLead = Self.rationaleLead(focus: focus, focusReason: focusReason, block: block)
        let estimate = Self.estimatedMinutes(exercises, style: style, warmUpMinutes: warmUpMinutes)
        workout.estimatedMinutes = estimate
        workout.lengthNote = exercises.isEmpty
            ? Self.emptyNote(focus: focus, planner: self)
            : Self.lengthNote(minutes: minutes, estimate: estimate, deload: deload, filledPastGoals: filledPastGoals,
                              warmUpMinutes: warmUpMinutes)
        return workout
    }

    /// Version A (0) or B (1) for an upper or full-body day: the one whose
    /// own movements (those not in the other version) you did longest ago,
    /// so the two alternate; A with no history. Always 0 for a focus with
    /// one version.
    public static func suggestedVariant(focus: WorkoutFocus, history: [String: ExerciseHistory]) -> Int {
        guard focus.variantCount > 1 else { return 0 }
        let a = Set(focus.slots(variant: 0))
        let b = Set(focus.slots(variant: 1))
        func latest(_ slots: Set<MovementSlot>) -> Date {
            var newest = Date.distantPast
            for (id, past) in history {
                guard let slot = ExerciseCatalog.slot(for: id), slots.contains(slot) else { continue }
                newest = max(newest, past.lastDate)
            }
            return newest
        }
        let lastA = latest(a.subtracting(b))
        let lastB = latest(b.subtracting(a))
        return lastA > lastB ? 1 : 0
    }

    /// The exercise for a slot, prescribed: `choose`'s pick, unless it's a
    /// first-time lift whose lightest load is far above your estimated
    /// starting weight (an empty 20 kg bar for a 7 kg curl, a 100% dumbbell
    /// jump): then the next option the gym has that you can load, if any
    /// (`tooHeavyFactor`). Nil when the gym has no option for the slot.
    func pick(_ slot: MovementSlot, excluding used: Set<String>, minutes: Int, rpe: Double,
              history: [String: ExerciseHistory], lifter: LoadEstimator.Lifter, position: Int,
              goals: [Muscle: Int]) -> PlannedExercise? {
        guard let first = choose(slot, excluding: used, history: history) else { return nil }
        let setsFixed = goals[MuscleCoverage.muscles(for: slot).primary] != nil
        func make(_ choice: CatalogExercise) -> PlannedExercise {
            prescribe(choice, slot: slot, minutes: minutes, sessionRPE: rpe, history: history, lifter: lifter,
                      position: position, setsFixed: setsFixed)
        }
        func tooHeavy(_ choice: CatalogExercise) -> Bool {
            guard history[choice.id] == nil, choice.load != nil else { return false }
            let reps = repsAndEffort(slot: slot, sessionRPE: rpe, heavy: isHeavy(slot: slot, position: position))
            guard let estimate = LoadEstimator.estimate(exerciseID: choice.id, reps: reps.reps, rpe: reps.rpe,
                                                        history: history, lifter: lifter, gym: gym) else { return false }
            return estimate.load > estimate.target * Self.tooHeavyFactor + 0.001
        }
        guard tooHeavy(first) else { return make(first) }
        let others = alternatives(for: slot).filter { !used.contains($0.id) && $0.id != first.id }
        if let lighter = others.first(where: { !tooHeavy($0) }) { return make(lighter) }
        var planned = make(first)
        let line = "The lightest weight here may be heavy for you: do the reps you can, or swap the exercise."
        planned.note = [planned.note, line].compactMap { $0 }.joined(separator: " ")
        return planned
    }

    /// A first-time load more than this many times the estimate (because the
    /// gym's lightest load is that heavy) makes `pick` try another option.
    /// App choice: 30% over is about four reps short at a 10-rep target.
    public static let tooHeavyFactor = 1.3

    /// Why a focus has no exercises: what rules things out (pain or "never
    /// again", else the gym's equipment), and a focus that does fit.
    static func emptyNote(focus: WorkoutFocus, planner: WorkoutPlanner) -> String {
        var unfiltered = planner
        unfiltered.exerciseFilter = nil
        let slots = Set(focus.slots(variant: 0) + focus.slots(variant: 1))
        let gymHasSome = slots.contains { !unfiltered.alternatives(for: $0).isEmpty }
        let reason = gymHasSome
            ? "Everything for this focus is on your never-again list or loads a sore area."
            : "Your gym's equipment has nothing for this focus."
        let other = WorkoutFocus.allCases.first { candidate in
            candidate != focus && candidate.slots.contains { slot in slot != .core && !planner.alternatives(for: slot).isEmpty }
        }
        guard let other else { return reason }
        return reason + " Try \(other.shortTitle.lowercased()) instead."
    }

    /// Why the plan's length differs from the time picked, when it does: a
    /// deload week is meant to be short, this week's set targets can need
    /// fewer sets than the time holds (`fill` then adds sets past them, within
    /// `VolumeProgression.sessionCap`), and a movement warm-up can leave a
    /// short session no room (the plan is then at its minimum and runs over).
    /// Nil when the plan fills the time with the week's own targets.
    static func lengthNote(minutes: Int, estimate: Int, deload: Bool, filledPastGoals: Bool,
                           warmUpMinutes: Int = 0) -> String? {
        let short = Double(estimate) < Double(minutes) * fillFraction
        if Double(estimate) > Double(minutes) * 1.1 + 0.5 {
            if warmUpMinutes > 0 {
                return "About \(estimate) min with the \(warmUpMinutes)-min warm-up: the fewest sets that still train well. Pick a longer time or a shorter warm-up."
            }
            return "About \(estimate) min: the fewest sets that still train well."
        }
        if deload, short { return "Deload week: about half the sets, so this runs about \(estimate) of your \(minutes) min." }
        if short { return "About \(estimate) of your \(minutes) min: that's every set this plan can add today." }
        if filledPastGoals { return "This week's set targets fit in less time, so extra sets fill your \(minutes) min." }
        return nil
    }

    /// The order a session is done in: multi-joint lifts first, each group in
    /// the order it was chosen, core last. A curl before a row, or a triceps
    /// extension before a press, tires the small muscle the big lift needs:
    /// lifts done later in a session lose reps and gain less strength, while
    /// muscle growth is about the same in either order (Nunes et al., Eur J
    /// Sport Sci 2021, meta-analysis; Simão et al., Sports Med 2012, review).
    static func liftOrder(_ exercises: [PlannedExercise]) -> [PlannedExercise] {
        func slot(_ exercise: PlannedExercise) -> MovementSlot? { ExerciseCatalog.slot(for: exercise.exerciseID) }
        let compounds = exercises.filter { slot($0)?.isCompound == true }
        let core = exercises.filter { slot($0) == .core }
        let small = exercises.filter { slot($0)?.isCompound != true && slot($0) != .core }
        return compounds + small + core
    }

    /// The focus's movements for the session length (the long session adds
    /// `extraSlot`), with any priority movements moved to directly after the
    /// leading compound lifts: multi-joint lifts stay first (Nunes et al.
    /// 2021), the lagging muscle's movement comes next, the defaults after.
    /// With `includeCore` false (the abs finisher is on and covers the core,
    /// `AbsFinisher`) the core movement is left out, so abs aren't trained twice.
    static func orderedSlots(focus: WorkoutFocus, minutes: Int, priority: [MovementSlot],
                             includeCore: Bool = true, variant: Int = 0) -> [MovementSlot] {
        let own = focus.slots(variant: variant)
        var extras = focus.extraSlots(variant: variant)
        var base = own
        if minutes >= longSessionMinutes, !extras.isEmpty { base.append(extras.removeFirst()) }
        if !includeCore {
            // The finisher covers the core: the next extra movement takes its place,
            // so the session keeps its number of exercises.
            let before = base.count
            base.removeAll { $0 == .core }
            if base.count < before, base.count < exerciseCount(minutes: minutes), !extras.isEmpty {
                base.append(extras.removeFirst())
            }
        }
        let priority = includeCore ? priority : priority.filter { $0 != .core }
        guard !priority.isEmpty else { return base }
        var unique: [MovementSlot] = []
        for slot in priority where !unique.contains(slot) { unique.append(slot) }
        // Each priority movement moves up once: a second exercise for it (push day's
        // second triceps movement) keeps its own place.
        for slot in unique {
            if let index = base.firstIndex(of: slot) { base.remove(at: index) }
        }
        let leading = base.prefix { $0.isCompound }
        return Array(leading) + unique + Array(base.dropFirst(leading.count))
    }

    /// Below this share of the time you picked, `fill` goes past the week's
    /// set goals, and a plan still under it says why (`lengthNote`). The
    /// 60-min session a user clocked at 40 min is what this guards against;
    /// the 90% floor is the app's choice (a plan should land near, never
    /// over; it was 85%, which let a plan 10-15% short pass with no word).
    public static let fillFraction = 0.9
    /// Most working sets `fill` gives one exercise (`baseSets`' reasoning:
    /// about 6-8 sets per muscle in one session); the first two compound
    /// lifts may take a fifth before an extra exercise is added.
    public static let maximumSetsPerExercise = 4

    /// Adds working sets, then an exercise for the focus's `extraSlot`, while
    /// one more still fits in `minutes` (never passing it). Compound lifts
    /// under `minimumCompoundSets` get theirs back first; then sets go to the
    /// exercise with the fewest (the earlier one on a tie), up to
    /// `maximumSetsPerExercise`, then a fifth on the first two compound
    /// lifts: more hard sets per muscle grow more muscle (Schoenfeld, Ogborn
    /// & Krieger, J Sports Sci 2017; Pelland et al., Sports Med 2026), so
    /// spare time buys sets before variety.
    ///
    /// With per-muscle `goals` (`VolumeProgression.sessionGoals`), a set or
    /// the extra exercise first goes only to a muscle still under its goal (or
    /// one without a goal); superset rounds count once per muscle
    /// (`VolumeProgression.directSets`). When the goals are met and the plan
    /// is still short of `fillFraction` (week 1's 10 sets a muscle shared
    /// over the week's sessions held a 75-min upper day to 18 sets), a second
    /// pass adds sets past the goals. Every pass keeps each muscle within
    /// `VolumeProgression.sessionCap` direct sets in this session: the
    /// benefit of piling sets into one session flattens after about 6-10
    /// (Pelland et al., Sports Med 2026; Remmert et al., SportRxiv 2025
    /// preprint), and a 90-min legs day had reached 21 quad sets. The extra
    /// exercise is added at most once. Returns true when the second pass
    /// added anything.
    @discardableResult
    func fill(_ exercises: inout [PlannedExercise], focus: WorkoutFocus, minutes: Int, rpe: Double,
              history: [String: ExerciseHistory], lifter: LoadEstimator.Lifter, warmUpMinutes: Int,
              goals: [Muscle: Int] = [:], variant: Int = 0) -> Bool {
        let target = Int((Double(minutes) * Self.fillFraction).rounded(.up))
        func estimate(_ list: [PlannedExercise]) -> Int {
            Self.estimatedMinutes(list, style: style, warmUpMinutes: warmUpMinutes)
        }
        let cap = VolumeProgression.sessionCap(minutes: minutes)
        var capped: [Muscle: Int] = [:]
        for muscle in Muscle.allCases { capped[muscle] = cap }
        // Goals, each kept within the session cap; muscles without one stop at the cap.
        var limits = capped
        for (muscle, goal) in goals { limits[muscle] = min(cap, max(0, goal)) }
        // Past the goals: a few sets more a muscle, so a long week of sessions
        // doesn't pile far past the weekly ceiling (`VolumeProgression.ceiling`).
        var beyond = capped
        for (muscle, goal) in goals { beyond[muscle] = min(cap, max(0, goal) + Self.setsPastGoal) }
        var triedExtra = false
        fillPass(&exercises, focus: focus, minutes: minutes, rpe: rpe, history: history, lifter: lifter,
                 warmUpMinutes: warmUpMinutes, limits: limits, variant: variant, triedExtra: &triedExtra)
        guard !goals.isEmpty, estimate(exercises) < target else { return false }
        let before = exercises
        fillPass(&exercises, focus: focus, minutes: minutes, rpe: rpe, history: history, lifter: lifter,
                 warmUpMinutes: warmUpMinutes, limits: beyond, variant: variant, triedExtra: &triedExtra)
        return exercises != before
    }

    /// Sets `fill`'s second pass may add past a muscle's goal for the
    /// session. App choice: six sessions a week each filling a muscle to the
    /// session cap had planned 26 shoulder sets against a ceiling of 20.
    public static let setsPastGoal = 4

    /// One pass of `fill`: sets, then the extra exercise (once per `fill`,
    /// `triedExtra`), while each muscle's direct sets stay under `limits`
    /// (no entry: no limit).
    private func fillPass(_ exercises: inout [PlannedExercise], focus: WorkoutFocus, minutes: Int, rpe: Double,
                          history: [String: ExerciseHistory], lifter: LoadEstimator.Lifter, warmUpMinutes: Int,
                          limits: [Muscle: Int], variant: Int, triedExtra: inout Bool) {
        /// True when one more set on this exercise's main muscle stays within its limit.
        func underLimit(_ exercise: PlannedExercise, in list: [PlannedExercise]) -> Bool {
            guard let muscle = VolumeProgression.primaryMuscle(exercise), let limit = limits[muscle] else { return true }
            return (VolumeProgression.directSets(list)[muscle] ?? 0) < limit
        }
        func estimate(_ list: [PlannedExercise]) -> Int {
            Self.estimatedMinutes(list, style: style, warmUpMinutes: warmUpMinutes)
        }
        // Fill as close to the time picked as the sets allow: a plan that only
        // reached the 85% floor still left a user 10+ minutes short.
        while estimate(exercises) < minutes {
            var added = false
            for index in Self.fillCandidates(exercises) where underLimit(exercises[index], in: exercises) {
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
            // The first extra movement the session doesn't have yet, else a second
            // exercise for one it has, the last listed first (a different exercise:
            // `pick` skips `used`).
            let extras = focus.extraSlots(variant: variant)
            let present = Set(exercises.compactMap { ExerciseCatalog.slot(for: $0.exerciseID) })
            let ordered = extras.filter { !present.contains($0) } + extras.filter { present.contains($0) }.reversed()
            var withExtra: [PlannedExercise]?
            for slot in ordered {
                guard var extra = pick(slot, excluding: used, minutes: minutes, rpe: rpe, history: history, lifter: lifter,
                                       position: exercises.count, goals: [:]) else { continue }
                extra.sets = Self.setFloor(extra, deload: false)
                // All of its sets must fit under the muscle's limit, not just the first.
                if let muscle = VolumeProgression.primaryMuscle(extra), let limit = limits[muscle],
                   (VolumeProgression.directSets(exercises)[muscle] ?? 0) + extra.sets > limit { continue }
                // In lift order, unless supersets are already paired (their order stands).
                let paired = exercises.contains { $0.supersetGroup != nil }
                var candidate = paired ? exercises + [extra] : Self.liftOrder(exercises + [extra])
                addWarmUps(&candidate, minutes: minutes)
                guard estimate(candidate) <= minutes else { continue }
                withExtra = candidate
                break
            }
            guard let withExtra else { return }
            exercises = withExtra
        }
    }

    /// Where `fill` tries to add a set, in order: compound lifts under
    /// `minimumCompoundSets` (so a big lift isn't left at 2 sets while a
    /// small one gets a third), then exercises under the cap, fewest sets
    /// first (earlier on a tie), then the first two compound lifts for a
    /// fifth set.
    static func fillCandidates(_ exercises: [PlannedExercise]) -> [Int] {
        func isCompound(_ index: Int) -> Bool { ExerciseCatalog.slot(for: exercises[index].exerciseID)?.isCompound == true }
        let shortCompounds = exercises.indices.filter { isCompound($0) && exercises[$0].sets < minimumCompoundSets }
        let under = exercises.indices
            .filter { exercises[$0].sets < maximumSetsPerExercise && !shortCompounds.contains($0) }
            .sorted { (exercises[$0].sets, $0) < (exercises[$1].sets, $1) }
        let compounds = exercises.indices
            .filter { isCompound($0) }
            .prefix(2)
            .filter { exercises[$0].sets < maximumSetsPerExercise + 1 && !under.contains($0) && !shortCompounds.contains($0) }
        return shortCompounds + under + compounds
    }

    /// Shares each muscle's set goal for the session (`VolumeProgression.sessionGoals`)
    /// over the exercises that train it as their main muscle, in session
    /// order (the compound lifts come first, so they get any spare set), each
    /// kept to `TrainingBlock.setRange` (2-5), and a compound lift to at least
    /// `minimumCompoundSets` outside a deload (so a goal of 5 over a row and a
    /// pulldown is 3 + 3, not 3 + 2). Exercises for muscles without a goal
    /// keep the sets they were given. A goal of 0 (the week's target is
    /// already met) leaves those exercises at the minimum.
    static func applySetGoals(_ exercises: inout [PlannedExercise], goals: [Muscle: Int], deload: Bool = false) {
        guard !goals.isEmpty else { return }
        for (muscle, goal) in goals {
            let indices = exercises.indices.filter { VolumeProgression.primaryMuscle(exercises[$0]) == muscle }
            guard !indices.isEmpty else { continue }
            let each = goal / indices.count
            let spare = goal % indices.count
            for (position, index) in indices.enumerated() {
                let sets = each + (position < spare ? 1 : 0)
                let floor = max(TrainingBlock.setRange.lowerBound, setFloor(exercises[index], deload: deload))
                exercises[index].sets = max(floor, min(TrainingBlock.setRange.upperBound, sets))
            }
        }
    }

    /// Keeps each muscle within `VolumeProgression.sessionCap` direct sets in
    /// the session: sets come off its later exercises above the floor
    /// (`setFloor`), the one with the most sets first, then off its first
    /// lift, then its latest exercise goes (one stays). The benefit
    /// of piling sets into one session flattens after about 6-10 (Pelland et
    /// al., Sports Med 2026); a long push day had planned 16 chest sets.
    static func capSessionVolume(_ exercises: inout [PlannedExercise], minutes: Int, deload: Bool) {
        // Short sessions' caps (4 at 20 min) are for sharing out the week; here at least two
        // exercises of 3 sets may stay, so a 20-min leg day keeps its curl and squat.
        let cap = max(VolumeProgression.sessionCap(minutes: minutes), 2 * minimumCompoundSets)
        for _ in 0..<200 {
            let direct = VolumeProgression.directSets(exercises)
            guard let muscle = Muscle.allCases.first(where: { (direct[$0] ?? 0) > cap }) else { return }
            let indices = exercises.indices.filter { VolumeProgression.primaryMuscle(exercises[$0]) == muscle }
            // The muscle's first lift keeps its sets longest; among the others, from the one with
            // the most sets (the later on a tie), so the cut is shared: squat 4, split squat 3,
            // leg extension 3, not 4 / 4 / 2.
            let above = indices.reversed().filter { exercises[$0].sets > setFloor(exercises[$0], deload: deload) }
            let later = above.filter { $0 != indices.first }
            let most = later.map { exercises[$0].sets }.max()
            if let index = later.first(where: { exercises[$0].sets == most }) ?? above.first {
                exercises[index].sets -= 1
            } else if indices.count > 1, let last = indices.last {
                exercises.remove(at: last)
            } else {
                return
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
        // Effort shows as rep goals on the sets (`RepGoal`), not a reps-in-reserve number.
        if block != nil {
            // The block week sets the effort; only a low-recovery back-off needs saying.
            if let recovery, recovery < 67 { parts.append("Effort eased for \(recovery)% recovery: rep goals are a little easier.") }
        } else if let recovery {
            let mood = recovery < 34 ? "an easy day, with easier rep goals" : (recovery < 67 ? "a normal day" : "a day to push")
            parts.append("Recovery \(recovery)%, \(mood).")
        } else {
            parts.append("No recovery score yet, so a moderate effort.")
        }
        // Counts after `fit`, so the line never promises sets the time didn't allow.
        let sets = exercises.reduce(0) { $0 + $1.sets }
        parts.append("\(minutes) min: \(exercises.count) exercises, \(sets) working sets.")
        return parts.joined(separator: " ")
    }

    /// Ramp sets for the loaded compound lifts: a full ramp on the first
    /// lift, a two-step ramp on the first lift of each other region (lower
    /// body, upper-body push, upper-body pull: in full body, the bench after
    /// squats used to get one feeler set), one feeler set on later lifts of a
    /// region already warmed, none on
    /// isolation work (`WarmUp`). In sessions of 30 min or less the first
    /// lift gets a two-step ramp and later lifts none, so ramp sets don't
    /// take a third of the time (audit 2026-11 §15). A lift with no load
    /// (first time, nothing to estimate from) gets none: there's no weight
    /// to ramp to, so the first set finds the weight. `minutes` nil = a
    /// long session.
    public func addWarmUps(_ exercises: inout [PlannedExercise], minutes: Int? = nil) {
        let short = (minutes ?? Int.max) <= Self.briefWarmUpMinutes
        var warmed: Set<MuscleGroup> = []
        for index in exercises.indices {
            let exercise = exercises[index]
            exercises[index].warmUpSets = nil
            guard let slot = ExerciseCatalog.slot(for: exercise.exerciseID), slot.isCompound,
                  let load = exercise.load, let kind = exercise.loadKind else { continue }
            let region = slot.warmUpRegion
            let role: WarmUp.Role
            if short {
                guard warmed.isEmpty else { continue }
                role = .brief
            } else if warmed.isEmpty {
                role = .firstCompound
            } else {
                role = warmed.contains(region) ? .laterCompound : .brief
            }
            warmed.insert(region)
            let sets = WarmUp.sets(workingLoad: load, kind: kind, gym: gym, role: role)
            exercises[index].warmUpSets = sets.isEmpty ? nil : sets
        }
    }

    /// Sessions this short get a brief ramp on the first lift only (`addWarmUps`). App choice.
    public static let briefWarmUpMinutes = 30

    /// Fewest sets an exercise is cut to so a session fits the time you picked.
    /// Two sets per exercise is within the 2-3 the ACSM recommends (position
    /// stand, Med Sci Sports Exerc 2026), and per-session strength gains level
    /// off after about two sets (Remmert et al., SportRxiv 2025 preprint).
    static let minimumSetsWhenShort = 2
    /// Fewest working sets a multi-joint lift keeps outside a deload, while
    /// the time allows. Multiple sets gain more strength and size than one
    /// (Ralston et al., Sports Med 2017; Schoenfeld, Ogborn & Krieger, J
    /// Sports Sci 2017), and the ACSM's 2-3+ sets per exercise (position
    /// stand, Med Sci Sports Exerc 2009 and 2026) leaves the main lifts at
    /// the top of that; 3 rather than 2 is the app's choice for the lifts
    /// that carry the most load. Isolation work may go down to 2.
    public static let minimumCompoundSets = 3

    /// The fewest sets `fit` cuts this exercise to before pairing or cutting
    /// further: 3 for a compound lift (`minimumCompoundSets`, 2 in a deload), else 2.
    static func setFloor(_ exercise: PlannedExercise, deload: Bool) -> Int {
        guard !deload, ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound == true else { return minimumSetsWhenShort }
        return minimumCompoundSets
    }

    /// Cuts sets until the estimated length fits `minutes`: one set off each
    /// muscle before a second off any (a week's band allows one set under
    /// the target per session), then from the exercise with the most sets,
    /// the later one on a tie, so the main lifts keep theirs longest, and
    /// compound lifts keep 3 (`setFloor`). Then the
    /// exercises are paired into supersets (`Supersets.pair`), which keeps
    /// the work and cuts the time; then the last isolation exercise outside
    /// a superset goes, then (in sessions over 20 minutes) the last exercise,
    /// keeping at least two, so a big lift isn't cut to 2 sets while another
    /// exercise stays; only then do compound lifts go down to two. With little time, fewer exercises
    /// with 2-3 sets each, mostly multi-joint and paired, are the efficient
    /// choices (Iversen et al., Sports Med 2021; ACSM position stand, Med
    /// Sci Sports Exerc 2026: 2-3 sets per exercise).
    static func fit(_ exercises: inout [PlannedExercise], minutes: Int, style: TrainingStyle = .balanced,
                    warmUpMinutes: Int = 0, deload: Bool = false) {
        var triedPairing = exercises.contains { $0.supersetGroup != nil }
        // Sessions of 20 min or less (or with a warm-up taking a third of the time) keep more
        // exercises at 2 sets each instead of fewer at 3: more total sets in the time.
        let roomy = minutes > AbsFinisher.shortSessionMinutes && warmUpMinutes * 3 < minutes
        // Sets cut per main muscle: one off each before a second off any, so the cuts stay inside
        // each week's band (one set under the target per session; `VolumeProgression.Target.band`).
        var cuts: [Muscle: Int] = [:]
        func cutRank(_ index: Int) -> (Int, Int) {
            let cut = VolumeProgression.primaryMuscle(exercises[index]).map { cuts[$0, default: 0] } ?? 0
            return (cut, -exercises[index].sets)
        }
        while estimatedMinutes(exercises, style: style, warmUpMinutes: warmUpMinutes) > minutes {
            let aboveFloor = exercises.indices.filter { exercises[$0].sets > setFloor(exercises[$0], deload: deload) }
            let trimmable = exercises.indices.filter { exercises[$0].sets > minimumSetsWhenShort }
            if let index = aboveFloor.reversed().min(by: { cutRank($0) < cutRank($1) }) {
                exercises[index].sets -= 1
                if let muscle = VolumeProgression.primaryMuscle(exercises[index]) { cuts[muscle, default: 0] += 1 }
            } else if triedPairing, !deload, exercises.count > 2,
                      let index = exercises.indices.last(where: { index in
                          exercises[index].supersetGroup == nil
                              && ExerciseCatalog.slot(for: exercises[index].exerciseID)?.isCompound != true
                      }) ?? (roomy ? exercises.count - 1 : nil) {
                // An unpaired small lift first; in a session with room for 3-set big lifts, else the last exercise.
                exercises.remove(at: index)
                Supersets.dropOrphans(&exercises)
            } else if triedPairing, let index = trimmable.reversed().max(by: { exercises[$0].sets < exercises[$1].sets }) {
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
                               style: TrainingStyle = .balanced, warmUpMinutes: Int = 0, deload: Bool = false) {
        for (id, goal) in earned.sorted(by: { $0.key < $1.key }) {
            guard let index = exercises.firstIndex(where: { $0.exerciseID == id }),
                  exercises[index].supersetGroup == nil else { continue }
            while exercises[index].sets < goal {
                guard let donor = exercises.indices.reversed().first(where: { other in
                    other != index && earned[exercises[other].exerciseID] == nil &&
                        exercises[other].supersetGroup == nil && exercises[other].sets > setFloor(exercises[other], deload: deload)
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
    /// For single-joint lifts (curls, triceps extensions, raises) a next
    /// weight more than this much heavier makes the lift rep-first
    /// (`progressionMode`): the lower half of the ACSM's 2-10%. Their loads
    /// are small, so one plate or stack pin is a large share (2.5 kg on a
    /// 25 kg curl is 10%), about three reps' worth of load by Epley, and a
    /// step that size made the weight bounce up and down near the lifter's
    /// limit. Adding reps builds muscle and strength as well as adding load
    /// (Plotkin et al., PeerJ 2022). The 5% line is the app's choice; the
    /// stand's own wording on smaller steps for small-muscle exercises
    /// couldn't be checked here.
    static let smallLiftJumpFraction = 0.05
    /// When the next weight up is a bigger jump than that (light dumbbells,
    /// coarse stacks), earn it by beating the top of the range by this many
    /// reps first, as the ACSM's "1-2 reps over the desired number" rule does.
    static let bigJumpExtraReps = 2
    /// The most an easier day (low recovery, a lower block RIR, the deload)
    /// takes off last time's working weight. Easing means about one more rep
    /// in reserve, and each rep in reserve is worth roughly 2-4% of 1RM on the
    /// RIR-based RPE scale (Helms et al., Strength Cond J 2016; Zourdos et
    /// al., J Strength Cond Res 2016), so even 2-3 extra reps in reserve stay
    /// within 10%. A best e1RM from an older, lighter-RPE or high-rep set
    /// otherwise could suggest far less. 10% is the app's cap; a pain cap
    /// (`ExerciseFilter.capLoad`) applies on top.
    public static let easedDropFraction = 0.10
    /// Last time over today's effort target by more than
    /// `VolumeProgression.effortTolerance` but by at most this many RPE
    /// points, where the next weight down is a coarse step: the same weight
    /// with one rep fewer, not the lighter weight (`repEased`). On the
    /// RIR-based RPE scale a point is a rep in reserve (Zourdos et al., J
    /// Strength Cond Res 2016; Helms et al., Strength Cond J 2016), so a rep
    /// off brings the set back to the target, while a step down worth two or
    /// more of those corrections overshoots it: the next session is then
    /// clearly easy and the weight goes straight back up. Near the lifter's
    /// limit that cycled 34 → 32 → 34 → 32 kg dumbbells for 12 weeks. A
    /// one-rep miss is also within the ~1-rep error of reps-in-reserve
    /// guesses (Halperin et al., Sports Med 2022), the band the set-by-set
    /// rule holds the load in (`Autoregulation.toleranceReps`). App choice.
    public static let repEaseOvershoot = Autoregulation.toleranceReps
    /// The most reps a set is asked for when the weight can't go up (the
    /// gym's heaviest, or the next weight out of reach) and last time was
    /// clearly easier than planned (`extendedReps`). Loads from about 30% of
    /// 1RM build about as much muscle as heavy ones when sets end near
    /// failure (Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW, J Strength Cond
    /// Res 2017;31:3508-23, meta-analysis; its low-load trials ran up to about
    /// 25-35 reps), while sets far from failure build less (Robinson et al.,
    /// Sports Med 2024). Past 30 a harder variation is the better tool, and
    /// reps-in-reserve guesses get worse on long sets (Halperin et al. 2022);
    /// the 30 is the app's choice.
    public static let maximumExtendedReps = 30

    /// Today's weight and rep target for a lift with history (`progression`).
    public struct Progression: Sendable, Equatable {
        /// In the gym's unit, loadable on this gym.
        public var load: Double
        /// The reps to aim for on each working set today.
        public var targetReps: Int
    }

    /// Today's weight for a lift with history: `progression(...)?.load`.
    public func suggestedLoad(history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double, kind: EquipmentKind,
                              mode: ProgressionMode = .load) -> Double? {
        progression(history: history, reps: reps, rpe: rpe, kind: kind, mode: mode)?.load
    }

    /// How far one session may move the weight up when last time was clearly
    /// easier than planned (`catchUp`): +15% for upper-body lifts and +20%
    /// for lower-body lifts, +30% while a lift has fewer than three logged
    /// sessions (the first weight was an estimate). RPE-based adjustment
    /// works about as well as fixed loading (Hickmott et al., Sports Med Open
    /// 2022); novices can progress faster than the ACSM's routine 2-10%
    /// (position stand, Med Sci Sports Exerc 2009). The caps are the app's
    /// choice (audit 2026-11 §2).
    public static let catchUpFraction = (upper: 0.15, lower: 0.20, early: 0.30)
    /// Reps in reserve read from a logged RPE are capped at 4 for 1RM records
    /// (`OneRepMax`), but a set at RPE 5 had more left; for the catch-up the
    /// cap is 6, flagged as low accuracy (Halperin et al., Sports Med 2022:
    /// estimates far from failure are the least accurate).
    public static let catchUpMaxReserve = 6.0
    /// True for a logged RPE of 5 or less: the RIR-based scale stops there
    /// (5+ reps left; Zourdos et al., J Strength Cond Res 2016), so how much
    /// was left isn't known, only that it was a lot.
    static func reserveUnknown(_ rpe: Double?) -> Bool {
        guard let rpe, rpe.isFinite else { return false }
        return rpe <= 5 + 0.001
    }

    /// The gap, in reps in reserve, between last time and today's target that
    /// counts as "clearly easier than planned": 2, past the ~1-rep error of
    /// reps-in-reserve guesses (Halperin et al. 2022).
    public static let catchUpGap = 2.0

    /// Double progression: keep the weight and add a rep each session until
    /// the top of the rep range, then add the smallest jump and aim for the
    /// reps your last session's estimated 1RM predicts at the new weight
    /// (82.5 × 10 at 2-3 in reserve → 85 × 8, not 85 × 6: dropping to the
    /// bottom of the range left about five reps in reserve; audit 2026-11 §4).
    /// The ACSM position stand (Med Sci Sports Exerc 2009) adds 2-10% once
    /// the target reps are beaten; Plotkin et al. (PeerJ 2022) found adding
    /// reps grows muscle and strength as well as adding load. "One more rep
    /// than last time" as the step is an app choice.
    ///
    /// Before anything else, a session that was clearly easier than planned
    /// (`catchUpGap` or more reps in reserve over today's target, reps
    /// inside the range) moves the weight to what that session's 1RM says,
    /// capped by `catchUpFraction`, so a light first weight catches up in a
    /// session or two instead of a step a session for months.
    ///
    /// `.load` (`ProgressionMode`):
    /// - last time inside the rep range, at today's effort or easier: same
    ///   weight, one rep more (82.5 × 6 → 82.5 × 7), capped at the top;
    /// - at the top: the next weight up. When that's a jump of over 10%
    ///   (light dumbbells, coarse stacks), the top moves `bigJumpExtraReps`
    ///   higher first, as the ACSM's "1-2 reps over" rule does;
    /// - a lower effort target than last time (low recovery, deload), last
    ///   reps outside the range, or a lighter last session: the weight comes
    ///   from your best estimated 1RM for the reps at today's reps in reserve
    ///   (Epley), rounded down to something you can load, never above last
    ///   time on an easier day. After an easier day it goes back to the
    ///   recent heaviest weight only if your best 1RM says you can do the
    ///   bottom of the range there (so a weight you missed reps at doesn't
    ///   come straight back).
    ///
    /// `.reps` and `.sets` hold the heaviest top weight of the last few
    /// sessions (`ExerciseHistory.recentHeaviestWeight`), so one easier day
    /// doesn't lower it for good, and add reps (`repTarget`, up to
    /// `bigJumpExtraReps` past the top) or a set (`progressedSets`). They move
    /// up one jump, whatever its size, once that's earned (`earnedLoadStep`).
    /// A lower effort target than last time goes lighter for that day only.
    public func progression(history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double, kind: EquipmentKind,
                            mode: ProgressionMode = .load, lowerBody: Bool = false) -> Progression? {
        let repsInReserve = max(0, 10 - rpe)
        // Last time at least `catchUpGap` reps fresher than today's target.
        let clearlyEasier = history.lastRPE.map { $0.isFinite && $0 <= rpe - Self.catchUpGap + 0.001 } ?? false
        /// A step to `next` that is a big jump (light dumbbells, coarse stacks)
        /// is taken only when last session says you'd get at least half the
        /// bottom of the range there (then build reps at it); a 10 → 20 lb face
        /// pull for a lifter whose 1RM is 16 isn't a step. App choice.
        func stepWithinReach(_ next: Double) -> Bool {
            let from = history.lastWeight
            guard isBigJump(from: from, to: next) else { return true }
            // RPE 5 or less: how much was left isn't known; a jump up to a third is taken on trust.
            if Self.reserveUnknown(history.lastRPE), from > 0, next <= from * (1 + 1.0 / 3) + 0.001 { return true }
            let lastReserve = history.lastRPE.map { max(0, min(Self.catchUpMaxReserve, 10 - $0)) } ?? repsInReserve
            let oneRepMax = from * (1 + (Double(max(0, history.lastReps)) + lastReserve) / 30)
            // At the rep ceiling and still clearly easy: the reps can't grow, so the step is
            // taken if that 1RM (a floor at RPE 5 or less) is over it.
            if history.lastReps >= Self.maximumExtendedReps, clearlyEasier, next < oneRepMax { return true }
            let reachable = 30 * (oneRepMax / next - 1) - repsInReserve
            return reachable >= Double(reps.lowerBound) / 2 - 0.001
        }
        // Reps past the range at a weight that can't go up (`extendedReps`) count as in range:
        // the next sessions build from there, not from the top of the range (23 reps → 8).
        let extendedZone = history.lastReps > reps.upperBound && !history.lastWasLighter
            && (gym.nextLoad(above: history.lastWeight, on: kind).map { !stepWithinReach($0) } ?? true)
        let repRoof = extendedZone ? max(reps.upperBound, Self.maximumExtendedReps) : reps.upperBound
        let lastInRange = min(max(history.lastReps, reps.lowerBound), repRoof)
        /// An easier day there: reps are the dial, a rep off per RPE point over
        /// today's target (one point is about one rep in reserve: Zourdos et al. 2016).
        func extendedEase() -> Progression? {
            guard extendedZone, let last = history.lastRPE, last.isFinite,
                  let held = gym.load(atMost: history.lastWeight, on: kind) else { return nil }
            let off = max(1, Int((last - rpe).rounded(.up)))
            return Progression(load: held, targetReps: max(reps.lowerBound, lastInRange - off))
        }
        /// The loadable weight for `count` reps at today's reps in reserve,
        /// never more than `easedDropFraction` under last time's weight (or
        /// the one load step down where the gym's jumps are coarser).
        func estimate(_ count: Int) -> Double? {
            guard let raw = gym.load(atMost: history.bestEstimatedOneRepMax / (1 + (Double(count) + repsInReserve) / 30), on: kind) else {
                return nil
            }
            // The lightest allowed: within 10% of last time; where the next
            // weight down is a bigger step (coarse stacks, light dumbbells),
            // last time's weight, eased by a rep instead (`easedReps`).
            let lowest = history.lastWeight * (1 - Self.easedDropFraction)
            let last = gym.load(atMost: history.lastWeight, on: kind) ?? history.lastWeight
            let floor = min(last, gym.nextLoad(above: lowest - 0.002, on: kind) ?? last)
            return max(raw, floor)
        }
        /// Reps on an easier day: as last time (kept in the range), one fewer
        /// when the weight stays at last time's, so the set ends with about one
        /// more rep in reserve (Helms et al. 2016).
        func easedReps(_ load: Double) -> Int {
            load >= history.lastWeight - 0.001 ? max(reps.lowerBound, lastInRange - 1) : lastInRange
        }
        /// The reps last session's estimated 1RM predicts at `load` with
        /// today's reps in reserve, kept in the range; at least the middle of
        /// the range when last time's RPE was 5 or less (the 1RM is then an
        /// underestimate: how much was left isn't known).
        func repsAt(_ load: Double) -> Int {
            let predicted = predictedReps(load)
            guard Self.reserveUnknown(history.lastRPE) else { return predicted }
            return max(predicted, LoadEstimator.estimateReps(reps))
        }
        func predictedReps(_ load: Double) -> Int {
            let lastReserve = history.lastRPE.map { max(0, min(Self.catchUpMaxReserve, 10 - $0)) } ?? repsInReserve
            let oneRepMax = history.lastWeight * (1 + (Double(max(0, history.lastReps)) + lastReserve) / 30)
            guard load > 0, oneRepMax.isFinite, oneRepMax > 0 else { return reps.lowerBound }
            let predicted = (30 * (oneRepMax / load - 1) - repsInReserve).rounded(.down)
            guard predicted.isFinite else { return reps.lowerBound }
            return max(reps.lowerBound, min(reps.upperBound, Int(max(0, min(100, predicted)))))
        }
        /// True when your best estimated 1RM says you can do within a rep of
        /// the bottom of the range at `load` with today's reps in reserve
        /// (reps-in-reserve guesses are about a rep out: Halperin et al. 2022).
        func canDo(_ load: Double) -> Bool {
            let best = history.bestEstimatedOneRepMax
            guard best.isFinite, best > 0 else { return true }
            return load <= best / (1 + (Double(reps.lowerBound - 1) + repsInReserve) / 30) + 0.001
        }
        /// Going back to the recent heaviest weight after a lighter session:
        /// only when that session was an easier day and the heaviest is
        /// within reach (`canDo`). An easier day either asked for less effort
        /// (logged at least a point under today's target: a deload, low
        /// recovery) or was cut well under your best (its estimated 1RM under
        /// 90% of your best: a pain cap takes about 20% off). A lighter session at about today's
        /// effort and your usual strength means the heavier weight was too
        /// much: stay and add reps, rather than ping-pong between the two.
        func backTo(_ load: Double) -> Bool {
            guard canDo(load) else { return false }
            if (history.lastRPE ?? rpe - 1) <= rpe - 1 + 0.001 { return true }
            let last = OneRepMax.estimate(weight: history.lastWeight, reps: history.lastReps, rpe: history.lastRPE)
            return last < history.bestEstimatedOneRepMax * 0.9
        }
        // Last time was at or under today's effort target: the rep (or weight) goes up.
        let strictlyHeld = (history.lastRPE ?? rpe) <= rpe + 0.001
        // Up to half a point over still counts as on target (reps in reserve are guessed to about
        // a rep: Halperin et al. 2022); the weight and reps then stay, rather than easing off and
        // bouncing back next time (24 → 22 → 24 kg).
        let effortHeld = (history.lastRPE ?? rpe) <= rpe + VolumeProgression.effortTolerance + 0.001
        let added = strictlyHeld ? 1 : 0
        if strictlyHeld, let caught = catchUp(history: history, reps: reps, rpe: rpe, kind: kind, lowerBody: lowerBody) {
            return Progression(load: caught, targetReps: repsAt(caught))
        }
        if mode != .load {
            guard let estimated = estimate(lastInRange) else { return nil }
            let held = gym.load(atMost: history.recentHeaviestWeight, on: kind) ?? estimated
            guard effortHeld else {
                if let eased = repEased(history: history, lastReps: lastInRange, reps: reps, rpe: rpe, kind: kind) ?? extendedEase() {
                    return eased
                }
                let load = min(estimated, held)
                return Progression(load: load, targetReps: easedReps(load))
            }
            if history.lastWasLighter {
                // Back to the held weight after an easier day; else stay where you are and add reps.
                if backTo(held) { return Progression(load: held, targetReps: lastInRange) }
                let stay = gym.load(atMost: history.lastWeight, on: kind) ?? estimated
                return Progression(load: stay, targetReps: max(reps.lowerBound, min(history.lastReps + added, reps.upperBound)))
            }
            if strictlyHeld, earnedLoadStep(history, reps: reps, mode: mode), let next = gym.nextLoad(above: held, on: kind),
               stepWithinReach(next) {
                return Progression(load: next, targetReps: repsAt(next))
            }
            let top = mode == .reps ? reps.upperBound + Self.bigJumpExtraReps : reps.upperBound
            let target = max(reps.lowerBound, min(history.lastReps + added, extendedZone ? repRoof : top))
            // Clearly easy at the top with no step in reach (or nothing heavier): more reps.
            if strictlyHeld, history.lastReps >= top || gym.nextLoad(above: held, on: kind) == nil,
               let extended = extendedReps(history: history, reps: reps, rpe: rpe) {
                return Progression(load: held, targetReps: max(target, extended))
            }
            return Progression(load: held, targetReps: target)
        }
        guard effortHeld else {
            if let eased = repEased(history: history, lastReps: lastInRange, reps: reps, rpe: rpe, kind: kind) ?? extendedEase() {
                return eased
            }
            guard let estimated = estimate(lastInRange) else { return nil }
            // An easier day: never heavier than last time.
            let cap = gym.load(atMost: history.lastWeight, on: kind) ?? estimated
            let load = min(estimated, cap)
            return Progression(load: load, targetReps: easedReps(load))
        }
        // After one easier session: back to the recent top weight (if it's
        // within reach), no step for the easy reps.
        if history.lastWasLighter, let back = gym.load(atMost: history.recentHeaviestWeight, on: kind), backTo(back) {
            return Progression(load: back, targetReps: lastInRange)
        }
        guard let held = gym.load(atMost: history.lastWeight, on: kind) else { return nil }
        let next = gym.nextLoad(above: history.lastWeight, on: kind)
        let bigJump = next.map { isBigJump(from: history.lastWeight, to: $0) } ?? false
        let top = reps.upperBound + (bigJump ? Self.bigJumpExtraReps : 0)
        if history.lastReps < reps.lowerBound {
            // Missed the range: a weight you can do the bottom of it with, not above last time.
            let estimated = estimate(reps.lowerBound) ?? held
            return Progression(load: min(estimated, held), targetReps: reps.lowerBound)
        }
        guard strictlyHeld, history.lastReps >= top, let next, stepWithinReach(next) else {
            let target = max(reps.lowerBound, min(history.lastReps + added, extendedZone ? repRoof : top))
            // Clearly easy at the top with no step in reach (or nothing heavier): more reps.
            if strictlyHeld, history.lastReps >= top || next == nil,
               let extended = extendedReps(history: history, reps: reps, rpe: rpe) {
                return Progression(load: held, targetReps: max(target, extended))
            }
            return Progression(load: held, targetReps: target)
        }
        // Well past the top: the 1RM estimate may say more than one jump.
        if history.lastReps > top, let estimated = estimate(reps.upperBound), estimated > next + 0.001 {
            return Progression(load: estimated, targetReps: repsAt(estimated))
        }
        return Progression(load: next, targetReps: repsAt(next))
    }

    /// The weight after a session that was clearly easier than planned, or
    /// nil when the rule doesn't apply: no RPE logged, fewer than
    /// `catchUpGap` extra reps in reserve, reps under the range, a lighter
    /// (easier-day) session, or no heavier weight to load. From that
    /// session's estimated 1RM (reps in reserve up to `catchUpMaxReserve`)
    /// for the middle of the range at today's effort, capped by
    /// `catchUpFraction`, rounded down to a load the gym can make.
    func catchUp(history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double, kind: EquipmentKind,
                 lowerBody: Bool) -> Double? {
        guard let lastRPE = history.lastRPE, lastRPE.isFinite, lastRPE <= rpe - Self.catchUpGap + 0.001,
              history.lastReps >= reps.lowerBound, history.lastWeight > 0, history.lastWeight.isFinite,
              !history.lastWasLighter else { return nil }
        let lastReserve = max(0, min(Self.catchUpMaxReserve, 10 - lastRPE))
        let oneRepMax = history.lastWeight * (1 + (Double(min(history.lastReps, 30)) + lastReserve) / 30)
        let middle = Double(LoadEstimator.estimateReps(reps))
        let early = history.recentWeights.count < ExerciseHistory.recentSessions
        let rise = early ? Self.catchUpFraction.early : (lowerBody ? Self.catchUpFraction.lower : Self.catchUpFraction.upper)
        var wanted = oneRepMax / (1 + (middle + max(0, 10 - rpe)) / 30)
        // RPE 5 or less only says "5 or more left", so the 1RM above is a floor: take at least
        // half the allowed rise (a whole one overshot: 85 → 110 → 140 for a 146 1RM).
        if Self.reserveUnknown(lastRPE) { wanted = max(wanted, history.lastWeight * (1 + rise / 2)) }
        let target = min(wanted, history.lastWeight * (1 + rise))
        guard target.isFinite, let next = gym.nextLoad(above: history.lastWeight, on: kind),
              next <= history.lastWeight * (1 + rise) + 0.001 else { return nil }
        // At least one step up: the set was clearly too easy (RPE 5 only says "5 or more left").
        let load = max(next, gym.load(atMost: target, on: kind) ?? next)
        return load
    }

    /// The same weight with one rep fewer when last time went a little past
    /// today's effort target (over `VolumeProgression.effortTolerance`, at
    /// most `repEaseOvershoot` RPE points), a rep can come off inside the
    /// range, and the next weight down is more than twice the cut the miss
    /// calls for: by Epley each RPE point is about 1/(30 + reps + reps in
    /// reserve) of the load (2.4% at 10 reps, 1.5 in reserve), so a 2 kg
    /// step off 34 kg dumbbells (5.9%) overshoots while 2.5 kg off a 105 kg
    /// bar (2.4%) is the cut itself. Nil otherwise: a bigger miss, reps at
    /// the bottom of the range, or a fine step eases the load (`progression`).
    /// `lastReps` is last time's reps kept in the range (or the extended reps, `extendedReps`).
    func repEased(history: ExerciseHistory, lastReps: Int, reps: ClosedRange<Int>, rpe: Double,
                  kind: EquipmentKind) -> Progression? {
        guard let last = history.lastRPE, last.isFinite, rpe.isFinite else { return nil }
        let over = last - rpe
        guard over > VolumeProgression.effortTolerance + 0.001, over <= Self.repEaseOvershoot + 0.001,
              history.lastReps > reps.lowerBound, lastReps > reps.lowerBound, history.lastWeight > 0,
              let held = gym.load(atMost: history.lastWeight, on: kind), abs(held - history.lastWeight) < 0.001 else { return nil }
        let cut = over / (30 + Double(lastReps) + max(0, 10 - rpe))
        if let lower = gym.achievableLoads(for: kind).last(where: { $0 < held - 0.001 }), (held - lower) / held <= 2 * cut {
            return nil
        }
        return Progression(load: held, targetReps: lastReps - 1)
    }

    /// Reps past the range when the weight stays although last time was
    /// clearly easier than planned (`catchUpGap` or more reps fresher): the
    /// gym has nothing heavier, or the top of the range is done and the next
    /// weight is a jump out of reach (`stepWithinReach`). Last time's reps
    /// plus the extra reps in reserve it had over today's target (at least
    /// one; RPE 5 or less counts as 5 left, the scale's floor: Zourdos et
    /// al. 2016), at most `maximumExtendedReps`. With the top of the range as the cap, a lifter
    /// stronger than the gym's heaviest dumbbell logged sets at RPE 5 for
    /// months: well short of the effort target, so they barely counted as
    /// hard sets (`VolumeProgression.hardSetRPE`). The rising reps also lift
    /// the 1RM estimate, which brings a big next jump within reach. Nil when
    /// last time wasn't clearly easier, was a lighter (easier-day) session,
    /// or was under the range.
    func extendedReps(history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double) -> Int? {
        guard let last = history.lastRPE, last.isFinite, rpe.isFinite, last <= rpe - Self.catchUpGap + 0.001,
              !history.lastWasLighter, history.lastReps >= reps.lowerBound else { return nil }
        let lastReserve = min(Self.catchUpMaxReserve, 10 - last)
        let gain = max(1, Int((lastReserve - max(0, 10 - rpe)).rounded(.down)))
        return min(Self.maximumExtendedReps, history.lastReps + gain)
    }

    /// More than the routine jump: over 10%, or over 5% for a single-joint
    /// lift when choosing its progression mode (`smallLiftJumpFraction`).
    func isBigJump(from current: Double, to next: Double, compound: Bool = true) -> Bool {
        let limit = compound ? Self.routineJumpFraction : Self.smallLiftJumpFraction
        return current > 0 && (next - current) / current > limit + 0.0001
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
    /// - each working set: `workSecondsPerSet` (twice that one side at a
    ///   time, `ExerciseCatalog.unilateralIDs`), and after every set but the
    ///   exercise's last the rest the timer will run: the plan's own
    ///   (`PlannedExercise.restSeconds`), else the style's for the pattern
    ///   (`RestTimer.defaultSeconds(style:slot:)`; balanced: 2.5 min for big
    ///   lifts, 3 for squats and hinges, 1.5 for small ones), at about 60% in
    ///   a superset (`Supersets.timeFraction`: the pair shares one rest);
    /// - `transitionMinutes` between exercises: walking over and setting up is
    ///   the rest after the last set, so that rest isn't counted twice;
    /// - drop stages and mini-sets (`TimeSaver.stageSeconds`), with no rest of their own.
    /// Counting rest by style matters: the timer runs the style's rest, so an
    /// estimate at the longer balanced rest trimmed muscle-style sessions
    /// short (a 60-min plan that took 40). Counting the last set's rest as
    /// well as the walk to the next exercise did the same: a 75-min upper
    /// plan held 18 sets and took a user 42.5 min.
    public static func estimatedMinutes(_ exercises: [PlannedExercise], style: TrainingStyle = .balanced,
                                        warmUpMinutes: Int = 0) -> Int {
        let ramp = Double(RestTimer.warmUpRestSeconds + rampWorkSeconds) / 60
        var total = Double(max(0, warmUpMinutes)) + transitionMinutes * Double(max(0, exercises.count - 1))
        for exercise in exercises {
            // The plan's own rest (the heavy first lift), else the style's for the pattern.
            let slot = ExerciseCatalog.slot(for: exercise.exerciseID)
            let restSeconds = exercise.restSeconds.flatMap { $0 > 0 ? $0 : nil }
                ?? RestTimer.defaultSeconds(style: style, slot: slot)
            let rest = Double(restSeconds) / 60
            // One side at a time: about twice the work per set (audit 2026-11 §10).
            let sides = ExerciseCatalog.unilateralIDs.contains(exercise.exerciseID) ? 2.0 : 1.0
            let work = Double(workSecondsPerSet) * sides / 60
            let fraction = exercise.supersetGroup == nil ? 1 : Supersets.timeFraction
            let sets = Double(max(0, exercise.sets))
            total += (sets * work + max(0, sets - 1) * rest) * fraction
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
