import Foundation

// MARK: - Abs finisher
//
// A 5- or 10-minute block of direct ab work added on top of a session.
//
// Evidence, and how far it goes:
// - Abs are trained like any other muscle: about 10-20 hard sets a week grows
//   the most muscle for most people (Schoenfeld, Ogborn & Krieger, J Sports Sci
//   2017, dose-response meta-analysis). Direct studies of the abs are few, so
//   applying this to them is an extrapolation. A 5-minute finisher gives 4
//   hard sets; on three sessions a week that is 12, inside the range.
// - Variety of trunk patterns: curling the spine (crunches), the pelvis
//   (reverse crunches, leg raises), resisting extension (dead bug, rollout,
//   plank) and resisting rotation or side bending (Pallof press, side plank).
//   The trunk's job in lifting is mostly to brace and resist movement
//   (McGill, Strength Cond J 2010), while the rectus abdominis grows with
//   dynamic, loadable flexion (Contreras & Schoenfeld, Strength Cond J 2011,
//   "To crunch or not to crunch"). Splitting "upper" and "lower" abs isn't
//   well supported; the leg-raise pattern is here for variety.
// - Spot reduction doesn't work: six weeks of ab training didn't reduce
//   belly fat (Vispute et al., J Strength Cond Res 2011). The UI says so.
// - Goal tailoring: strength puts the bracing patterns (anti-extension,
//   anti-rotation) first, as that is what carries over to heavy lifts
//   (McGill 2010); muscle puts loaded flexion first, since load lets the
//   sets progress like any lift. The reps follow the goal's small-lift
//   range (`WorkoutPlanner.prescribe`); muscle grows across a wide rep range
//   when sets go near failure (Schoenfeld et al., J Strength Cond Res 2017).
// - The circuit's short rest (30 s after each pair, about 85 s between sets
//   of the same move) is the app's choice to fit the minutes. Rest under
//   about 60 s grew slightly less muscle than longer rest, a small difference
//   (Singer et al., Front Sports Act Living 2024).
// - Lower-back pain: spine flexion and rollouts are left out or eased
//   (`PainGuard.extraAreas`, coaching convention after McGill 2010).

/// The trunk pattern a core exercise trains.
public enum CorePattern: String, Codable, Sendable, CaseIterable {
    /// Curling the spine: crunches.
    case flexion
    /// Curling the pelvis up: reverse crunches, knee and leg raises.
    case legRaise
    /// Keeping the spine still against extension: dead bug, rollout, plank.
    case antiExtension
    /// Resisting rotation or side bending: Pallof press, side plank, side bend.
    case rotationLateral

    public var title: String {
        switch self {
        case .flexion: "Crunch"
        case .legRaise: "Leg raise"
        case .antiExtension: "Brace"
        case .rotationLateral: "Anti-rotation"
        }
    }

    /// Crunches and leg raises move the spine; the other two resist movement.
    public var isDynamic: Bool { self == .flexion || self == .legRaise }
}

/// A core exercise's pattern and how it is dosed. The exercise itself
/// (name, equipment) is in `ExerciseCatalog.options[.core]`.
public struct CoreMove: Sendable, Equatable {
    public var id: String
    public var pattern: CorePattern
    /// Held for time: reps are logged as seconds (`CoreMoves.holdSeconds`).
    public var isHold: Bool
    /// Done on each side in turn: the reps (or seconds) are per side.
    public var perSide: Bool
    /// Sides alternate rep by rep (dead bug, bicycle crunch): reps count both sides.
    public var alternating: Bool

    init(_ id: String, _ pattern: CorePattern, hold: Bool = false, perSide: Bool = false, alternating: Bool = false) {
        self.id = id
        self.pattern = pattern
        isHold = hold
        self.perSide = perSide
        self.alternating = alternating
    }
}

public enum CoreMoves {
    /// Every core exercise, best first within a pattern: a loadable option
    /// first (it can progress like a lift), holds last (logged in seconds).
    public static let all: [CoreMove] = [
        CoreMove("Cable_Crunch", .flexion),
        CoreMove("Crunches", .flexion),
        CoreMove("Decline_Crunch", .flexion),
        CoreMove("Air_Bike", .flexion, alternating: true),
        CoreMove("Hanging_Leg_Raise", .legRaise),
        CoreMove("Knee_Hip_Raise_On_Parallel_Bars", .legRaise),
        CoreMove("Cable_Reverse_Crunch", .legRaise),
        CoreMove("Reverse_Crunch", .legRaise),
        CoreMove("Dead_Bug", .antiExtension, alternating: true),
        CoreMove("Barbell_Ab_Rollout_-_On_Knees", .antiExtension),
        CoreMove("Plank", .antiExtension, hold: true),
        CoreMove("Pallof_Press", .rotationLateral, perSide: true),
        CoreMove("Dumbbell_Side_Bend", .rotationLateral, perSide: true),
        CoreMove("Side_Bridge", .rotationLateral, hold: true, perSide: true),
    ]

    public static func move(id: String) -> CoreMove? {
        all.first { $0.id == id }
    }

    /// Seconds per hold. App choice: short holds repeated, as McGill
    /// recommends for trunk endurance (Strength Cond J 2010), rather than
    /// minute-long planks; the hold time isn't a tested optimum.
    public static let holdSeconds: ClosedRange<Int> = 20...30
}

public enum AbsFinisher {
    /// How long the finisher runs. Off, 5 or 10 minutes on top of the session.
    public enum Length: Int, Codable, Sendable, CaseIterable, Identifiable {
        case off = 0
        case five = 5
        case ten = 10

        public var id: Int { rawValue }
        public var minutes: Int { rawValue }

        public var label: String {
            switch self {
            case .off: "Off"
            case .five: "5 min"
            case .ten: "10 min"
            }
        }

        /// Exercises it aims for: one dynamic and one bracing move in 5
        /// minutes, one of each pattern in 10.
        public var exerciseCount: Int {
            switch self {
            case .off: 0
            case .five: 2
            case .ten: 4
            }
        }
    }

    // MARK: Time model (app estimates, like `WorkoutPlanner.workSecondsPerSet`)

    /// Sets per exercise: two rounds of the circuit. Two sets is within the
    /// 2-3 the ACSM recommends per exercise (`WorkoutPlanner.minimumSetsWhenShort`).
    public static let setsPerExercise = 2
    /// Rest after each pair (both halves done): short, to fit the minutes (app choice).
    public static let restSeconds = 30
    /// A set of 10-15 reps at a controlled tempo.
    public static let repWorkSeconds = 40
    /// One side of a per-side move (Pallof press, side bend).
    public static let perSideWorkSeconds = 30
    /// Moving from one exercise to the next on the floor or at the cable.
    public static let changeoverSeconds = 15
    /// Getting a mat or setting the cable before the first set.
    public static let setupSeconds = 30

    /// One finisher: its exercises, in order, paired as supersets.
    public struct Plan: Sendable, Equatable {
        public var length: Length
        public var exercises: [PlannedExercise]
        /// Estimated minutes (`estimatedSeconds`), at most `length.minutes`.
        public var estimatedMinutes: Int

        /// Working sets for abs it adds.
        public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

        /// "Abs finisher · 5 min".
        public var title: String { "Abs finisher · \(length.label)" }

        /// "2 moves, 2 rounds, 4 sets for abs."
        public var summary: String {
            let rounds = exercises.map(\.sets).max() ?? 0
            return "\(exercises.count) moves, \(rounds) rounds, \(totalSets) sets for abs."
        }
    }

    /// Sessions this short (and a plan's short version) skip the finisher:
    /// 5-10 minutes on top of a 15-20 minute session adds a third to a half
    /// to the time you picked. App choice.
    public static let shortSessionMinutes = 20

    /// The finisher length to use for a session: off for short sessions
    /// (`shortSessionMinutes` or less, or the plan's short version), else your choice.
    public static func length(_ chosen: Length, sessionMinutes: Int, isShortVersion: Bool = false) -> Length {
        (isShortVersion || sessionMinutes <= shortSessionMinutes) ? .off : chosen
    }

    /// What the finisher does and doesn't do, for the UI.
    public static let evidenceNote = "Abs grow like other muscles, with about 10-20 hard sets a week (Schoenfeld 2017). Ab work won't burn belly fat on its own (Vispute 2011): that comes from diet and overall activity."

    /// Builds a finisher for the session.
    /// - Parameters:
    ///   - planner: the gym, the goal's style and the pain / never-again
    ///     filter (`WorkoutPlanner.exerciseFilter`); only exercises it
    ///     allows are picked.
    ///   - history: loads for the loadable moves (cable crunch, Pallof press).
    ///   - recentExerciseIDs: exercises from recent sessions, newest first:
    ///     patterns and exercises done least recently come first, so the
    ///     finisher rotates.
    ///   - excluding: exercises already in the session (no double core).
    ///   - sessionRPE: the session's target, for the sets' effort.
    ///   - firstGroup: the first superset group number to use (one past the session's).
    /// - Returns: nil when off or nothing fits the gym and filter.
    public static func make(
        length: Length,
        planner: WorkoutPlanner,
        history: [String: ExerciseHistory] = [:],
        recentExerciseIDs: [String] = [],
        excluding: Set<String> = [],
        sessionRPE: Double = 8,
        firstGroup: Int = 1
    ) -> Plan? {
        guard length != .off else { return nil }
        let picks = choose(count: length.exerciseCount, planner: planner, recentExerciseIDs: recentExerciseIDs,
                           excluding: excluding)
        guard !picks.isEmpty else { return nil }
        var prescribed = picks.map { prescribe($0, planner: planner, history: history, sessionRPE: sessionRPE) }
        // Fewer moves when the estimate runs past the minutes (per-side moves take longer).
        var exercises = paired(prescribed, firstGroup: firstGroup)
        while estimatedSeconds(exercises) > length.minutes * 60 + 29, prescribed.count > 1 {
            prescribed.removeLast()
            exercises = paired(prescribed, firstGroup: firstGroup)
        }
        return Plan(length: length, exercises: exercises, estimatedMinutes: minutes(estimatedSeconds(exercises)))
    }

    /// The pattern order for a goal style (see the evidence notes above).
    public static func patternPriority(style: TrainingStyle) -> [CorePattern] {
        switch style {
        case .strength: [.antiExtension, .rotationLateral, .flexion, .legRaise]
        case .muscle, .strengthAndMuscle: [.flexion, .legRaise, .antiExtension, .rotationLateral]
        case .balanced, .endurance: [.flexion, .antiExtension, .legRaise, .rotationLateral]
        }
    }

    /// The exercises, in session order: for two, one dynamic (crunch or leg
    /// raise) and one bracing move; for more, one per pattern, then second
    /// picks. Within a family the pattern done least recently wins, the
    /// goal's order on a tie; within a pattern the exercise done least
    /// recently, the catalog's order on a tie. An exercise that loads a
    /// 3-5/10 area goes after ones that don't.
    static func choose(count: Int, planner: WorkoutPlanner, recentExerciseIDs: [String],
                       excluding: Set<String>) -> [CatalogExercise] {
        let priority = patternPriority(style: planner.style)
        let pool = planner.alternatives(for: .core).filter { !excluding.contains($0.id) && CoreMoves.move(id: $0.id) != nil }
        // Smaller = done more recently; nil = not in the recent sessions.
        func recency(_ id: String) -> Int? { recentExerciseIDs.firstIndex(of: id) }
        func eased(_ id: String) -> Bool { planner.exerciseFilter?.regressArea(forExerciseID: id, slot: .core) != nil }
        // The catalog order within a pattern (`CoreMoves.all`): loadable first, holds last.
        func rank(_ exercise: CatalogExercise) -> (Int, Int, Int, Int) {
            let recent = recency(exercise.id)
            let base = CoreMoves.all.firstIndex { $0.id == exercise.id } ?? CoreMoves.all.count
            return (eased(exercise.id) ? 1 : 0, recent == nil ? 0 : 1, recent.map { -$0 } ?? 0, base)
        }
        var byPattern: [CorePattern: [CatalogExercise]] = [:]
        for pattern in CorePattern.allCases {
            let options = pool
                .filter { CoreMoves.move(id: $0.id)?.pattern == pattern }
                .sorted { rank($0) < rank($1) }
            if !options.isEmpty { byPattern[pattern] = options }
        }
        // Patterns not done recently first, then the least recent; the goal's order on a tie.
        func patternRecency(_ pattern: CorePattern) -> Int? {
            recentExerciseIDs.firstIndex { CoreMoves.move(id: $0)?.pattern == pattern }
        }
        let ordered = priority.filter { byPattern[$0] != nil }.sorted { a, b in
            let ra = patternRecency(a), rb = patternRecency(b)
            let ka = (ra == nil ? 0 : 1, ra.map { -$0 } ?? 0, priority.firstIndex(of: a) ?? 0)
            let kb = (rb == nil ? 0 : 1, rb.map { -$0 } ?? 0, priority.firstIndex(of: b) ?? 0)
            return ka < kb
        }
        var patterns: [CorePattern] = []
        if count == 2 {
            // One that moves the spine and one that resists movement.
            if let dynamic = ordered.first(where: \.isDynamic) { patterns.append(dynamic) }
            if let brace = ordered.first(where: { !$0.isDynamic }) { patterns.append(brace) }
        }
        for pattern in ordered where patterns.count < count && !patterns.contains(pattern) {
            patterns.append(pattern)
        }
        var picks: [(pattern: CorePattern, exercise: CatalogExercise)] = []
        for pattern in patterns {
            if let first = byPattern[pattern]?.first { picks.append((pattern, first)) }
        }
        // Too few patterns in this gym: second exercises, in the same order.
        var depth = 1
        while picks.count < count, depth < 4 {
            for pattern in ordered where picks.count < count {
                if let options = byPattern[pattern], depth < options.count {
                    picks.append((pattern, options[depth]))
                }
            }
            depth += 1
        }
        // Session order: the goal's pattern order.
        let sorted = picks.enumerated().sorted { a, b in
            let pa = priority.firstIndex(of: a.element.pattern) ?? 0
            let pb = priority.firstIndex(of: b.element.pattern) ?? 0
            return (pa, a.offset) < (pb, b.offset)
        }
        return sorted.map(\.element.exercise)
    }

    /// Sets, reps and load from the planner (`WorkoutPlanner.prescribe`: the
    /// goal's small-lift reps and effort, load progression for loadable
    /// moves), then the finisher's sets and rest, and notes for holds and
    /// per-side moves.
    static func prescribe(_ exercise: CatalogExercise, planner: WorkoutPlanner, history: [String: ExerciseHistory],
                          sessionRPE: Double) -> PlannedExercise {
        var planned = planner.prescribe(exercise, slot: .core, minutes: 45, sessionRPE: sessionRPE, history: history)
        planned.sets = setsPerExercise
        planned.restSeconds = restSeconds
        planned.isFinisher = true
        planned.warmUpSets = nil
        let move = CoreMoves.move(id: exercise.id)
        var lines: [String] = []
        if move?.isHold == true {
            let hold = CoreMoves.holdSeconds
            let sides = move?.perSide == true ? " each side" : ""
            lines.append("Hold \(hold.lowerBound)-\(hold.upperBound) s\(sides); log the seconds as reps.")
        } else if move?.perSide == true {
            lines.append("Reps are per side.")
        } else if move?.alternating == true {
            lines.append("Alternate sides; reps count both sides.")
        }
        if let note = planned.note, !note.isEmpty { lines.insert(note, at: 0) }
        planned.note = lines.isEmpty ? nil : lines.joined(separator: " ")
        // A lighter load and a note on a move that loads a 3-5/10 area (`PainGuard`).
        planner.exerciseFilter?.capLoad(&planned, slot: .core, gym: planner.gym)
        return planned
    }

    /// Pairs the exercises in order (A1/A2, B1/B2) as supersets; an odd last
    /// one stays a straight set.
    static func paired(_ exercises: [PlannedExercise], firstGroup: Int) -> [PlannedExercise] {
        var result = exercises
        var group = max(1, firstGroup)
        var index = 0
        while index < result.count {
            if index + 1 < result.count {
                result[index].supersetGroup = group
                result[index + 1].supersetGroup = group
                group += 1
                index += 2
            } else {
                result[index].supersetGroup = nil
                index += 1
            }
        }
        return result
    }

    /// Seconds of work in one set: the hold or the reps, twice for a per-side move.
    static func workSeconds(_ exercise: PlannedExercise) -> Int {
        let move = CoreMoves.move(id: exercise.exerciseID)
        let perSide = move?.perSide == true
        if move?.isHold == true {
            return CoreMoves.holdSeconds.upperBound * (perSide ? 2 : 1)
        }
        return perSide ? perSideWorkSeconds * 2 : repWorkSeconds
    }

    /// How long the finisher takes: setup, then each pair's rounds (both
    /// halves, a changeover, the rest) or a straight exercise's sets (work
    /// and rest), with a changeover between blocks.
    public static func estimatedSeconds(_ exercises: [PlannedExercise]) -> Int {
        guard !exercises.isEmpty else { return 0 }
        var total = setupSeconds
        var index = 0
        var blocks = 0
        while index < exercises.count {
            let first = exercises[index]
            let rest = first.restSeconds ?? restSeconds
            if let group = first.supersetGroup, index + 1 < exercises.count, exercises[index + 1].supersetGroup == group {
                let second = exercises[index + 1]
                let rounds = max(first.sets, second.sets)
                total += rounds * (workSeconds(first) + workSeconds(second) + changeoverSeconds + rest)
                index += 2
            } else {
                total += first.sets * (workSeconds(first) + rest)
                index += 1
            }
            blocks += 1
        }
        return total + changeoverSeconds * max(0, blocks - 1)
    }

    static func minutes(_ seconds: Int) -> Int {
        Int((Double(seconds) / 60).rounded())
    }

    /// One past the highest superset group in a list (1 when there is none).
    public static func nextGroup(after exercises: [PlannedExercise]) -> Int {
        (exercises.compactMap(\.supersetGroup).max() ?? 0) + 1
    }

    /// The workout with the finisher's exercises after its own. The plan's
    /// `estimatedMinutes` stays the main session's: the finisher is on top.
    public static func appending(_ finisher: Plan?, to workout: PlannedWorkout) -> PlannedWorkout {
        guard let finisher, !finisher.exercises.isEmpty else { return workout }
        var result = workout
        result.exercises += finisher.exercises
        return result
    }
}
