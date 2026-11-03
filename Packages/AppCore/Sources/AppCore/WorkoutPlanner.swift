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

    /// The slot an exercise belongs to, if it's in the catalog.
    public static func slot(for exerciseID: String) -> MovementSlot? {
        for (slot, list) in options where list.contains(where: { $0.id == exerciseID }) {
            return slot
        }
        return nil
    }

    public static func exercise(id: String) -> CatalogExercise? {
        options.values.lazy.flatMap { $0 }.first { $0.id == id }
    }
}

/// What you did on an exercise recently, in the gym's unit.
public struct ExerciseHistory: Sendable, Equatable {
    public var bestEstimatedOneRepMax: Double
    public var lastWeight: Double
    public var lastReps: Int
    public var lastRPE: Double?
    public var lastDate: Date

    public init(bestEstimatedOneRepMax: Double, lastWeight: Double, lastReps: Int, lastRPE: Double?, lastDate: Date) {
        self.bestEstimatedOneRepMax = bestEstimatedOneRepMax
        self.lastWeight = lastWeight
        self.lastReps = lastReps
        self.lastRPE = lastRPE
        self.lastDate = lastDate
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
}

extension PlannedExercise {
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
}

public struct WorkoutPlanner: Sendable {
    public var gym: GymProfile
    /// Rep ranges and effort, from the user's goals.
    public var style: TrainingStyle

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

    public func choose(_ slot: MovementSlot) -> CatalogExercise? {
        alternatives(for: slot).first
    }

    /// Every catalog exercise for a slot that this gym supports, best first.
    public func alternatives(for slot: MovementSlot) -> [CatalogExercise] {
        (ExerciseCatalog.options[slot] ?? []).filter { exercise in
            exercise.requires.allSatisfy { gym.has($0) } &&
            (exercise.load.map { !gym.achievableLoads(for: $0).isEmpty } ?? true)
        }
    }

    /// Sets, reps, effort and load for one exercise in a session.
    public func prescribe(
        _ choice: CatalogExercise,
        slot: MovementSlot,
        minutes: Int,
        sessionRPE rpe: Double,
        history: [String: ExerciseHistory]
    ) -> PlannedExercise {
        let compound = slot.isCompound
        let sets = compound ? (minutes <= 30 ? 3 : 4) : 3
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
                planned.load = suggestedLoad(history: past, reps: reps, rpe: setRPE, kind: kind)
                if let load = planned.load {
                    planned.note = notes(load: load, history: past, reps: reps, rpe: setRPE, kind: kind)
                }
            } else {
                planned.note = "First time: pick a weight you can lift \(reps.upperBound) times with \(Int(10 - setRPE)) left in the tank."
            }
        }
        return planned
    }

    public func plan(
        focus: WorkoutFocus,
        minutes: Int,
        recovery: Int?,
        history: [String: ExerciseHistory]
    ) -> PlannedWorkout {
        let rpe = Self.targetRPE(recovery: recovery)
        let exerciseCount = minutes <= 30 ? 4 : (minutes <= 45 ? 5 : 6)
        var exercises: [PlannedExercise] = []
        for slot in focus.slots {
            guard exercises.count < exerciseCount, let choice = choose(slot) else { continue }
            exercises.append(prescribe(choice, slot: slot, minutes: minutes, sessionRPE: rpe, history: history))
        }
        Self.fit(&exercises, minutes: minutes)
        return PlannedWorkout(focus: focus, title: focus.title, minutes: minutes, targetRPE: rpe, exercises: exercises, unit: gym.unit)
    }

    /// Fewest sets an exercise is cut to so a session fits the time you picked.
    /// Two sets per exercise is within the 2-3 the ACSM recommends (position
    /// stand, Med Sci Sports Exerc 2026), and per-session strength gains level
    /// off after about two sets (Remmert et al., SportRxiv 2025 preprint).
    static let minimumSetsWhenShort = 2

    /// Cuts sets until the estimated length fits `minutes`: always from the
    /// exercise with the most sets, the later one on a tie, so the main lifts
    /// keep theirs longest. If every exercise is down to two sets, the last
    /// exercise goes (keeping at least two). With little time, fewer sets of
    /// the big multi-joint lifts are the efficient choice (Iversen et al.,
    /// Sports Med 2021).
    static func fit(_ exercises: inout [PlannedExercise], minutes: Int) {
        while estimatedMinutes(exercises) > minutes {
            let trimmable = exercises.indices.filter { exercises[$0].sets > minimumSetsWhenShort }
            if let index = trimmable.reversed().max(by: { exercises[$0].sets < exercises[$1].sets }) {
                exercises[index].sets -= 1
            } else if exercises.count > 2 {
                exercises.removeLast()
            } else {
                return
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
    public func suggestedLoad(history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double, kind: EquipmentKind) -> Double? {
        let repsInReserve = max(0, 10 - rpe)
        let effectiveReps = Double(reps.upperBound) + repsInReserve
        let target = history.bestEstimatedOneRepMax / (1 + effectiveReps / 30)
        guard var load = gym.load(atMost: target, on: kind) else { return nil }
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
    func notes(load: Double, history: ExerciseHistory, reps: ClosedRange<Int>, rpe: Double, kind: EquipmentKind) -> String? {
        var parts: [String] = []
        if let plates = loadNote(load: load, kind: kind) { parts.append(plates) }
        if abs(load - history.lastWeight) < 0.001, history.lastReps >= reps.upperBound,
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

    /// Rough session length: 5 minutes of warm-up, then per set about 45 s of
    /// work plus the default rest (`RestTimer`, balanced style): 3.25 min for
    /// big lifts, 2.25 min for small ones.
    public static func estimatedMinutes(_ exercises: [PlannedExercise]) -> Int {
        let workSeconds = 45
        let compound = Double(RestTimer.defaultSeconds(style: .balanced, compound: true) + workSeconds) / 60
        let isolation = Double(RestTimer.defaultSeconds(style: .balanced, compound: false) + workSeconds) / 60
        let setMinutes = exercises.reduce(0.0) { total, exercise in
            let perSet = ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound == true ? compound : isolation
            return total + Double(exercise.sets) * perSet
        }
        return Int((5 + setMinutes).rounded())
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
