import Foundation

/// How a working set is done: a normal ("straight") set, a stage that
/// continues the set before it (drop set, rest-pause, myo-reps), or a set
/// taken to failure. Warm-up ramp sets stay a separate flag (`WarmUp`).
///
/// Evidence (docs/research/lifting-features.md §3.3):
/// - Drop sets built about as much muscle and strength as traditional sets
///   (ES about 0.08) in about half to a third of the time: Coleman M, et al.
///   Muscular adaptations in drop set vs. traditional training: a
///   meta-analysis. Int J Strength Cond 2022; Sødal LK, et al. Effects of drop
///   sets on skeletal muscle hypertrophy: a systematic review and
///   meta-analysis. Sports Med Open 2023.
/// - Rest-pause gave about the same, maybe slightly more, muscle growth than
///   traditional sets: Carvalho L, et al. Muscle hypertrophy and strength gains
///   after resistance training with different volume-matched loads: a
///   systematic review and meta-analysis. Appl Physiol Nutr Metab 2022;
///   Tsartsapakis I, et al. Advanced resistance training systems in
///   recreationally trained adults: systematic review and meta-analysis.
///   J Funct Morphol Kinesiol 2026;11(1):80.
/// - Myo-reps themselves have not been tested in trials. They're a rest-pause
///   variant, so the app labels them "untested" and expects roughly what
///   rest-pause gives, no more.
/// - Failure: stopping 1-3 reps short builds about as much muscle as failure
///   (Refalo et al., J Sports Sci 2024) and failure adds fatigue while barely
///   helping strength (Robinson et al., Sports Med 2024).
public enum SetKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case straight, drop, restPause, myoRep, failure

    public var id: String { rawValue }

    /// Stored as nil for a straight set, so logs from before set types read as straight.
    public init(storedValue: String?) {
        self = storedValue.flatMap(SetKind.init(rawValue:)) ?? .straight
    }

    /// True for a stage: a mini-set that carries on from the set before it
    /// with little or no rest. A stage isn't a set of its own: it doesn't get
    /// its own target, verdict, record or load change, and the set it belongs
    /// to counts once for effort (feature spec §3.3 risks).
    public var isStage: Bool {
        switch self {
        case .drop, .restPause, .myoRep: true
        case .straight, .failure: false
        }
    }

    /// Only straight sets move the next set's load (`Autoregulation`): a set
    /// to failure is RPE 10 on purpose, and a stage is fatigued by design.
    public var allowsAutoregulation: Bool { self == .straight }

    /// "Normal set", "Drop set" …, for menus.
    public var title: String {
        switch self {
        case .straight: "Normal set"
        case .drop: "Drop set"
        case .restPause: "Rest-pause"
        case .myoRep: "Myo-reps"
        case .failure: "To failure"
        }
    }

    /// The row label for a stage ("D", "RP", "M"); empty for the others,
    /// which keep their set number.
    public var shortLabel: String {
        switch self {
        case .drop: "D"
        case .restPause: "RP"
        case .myoRep: "M"
        case .straight, .failure: ""
        }
    }

    /// What one stage is called: "Drop 1 of 2", "Mini-set 2 of 3".
    public var stageName: String {
        switch self {
        case .drop: "Drop"
        case .restPause, .myoRep: "Mini-set"
        case .straight, .failure: "Set"
        }
    }

    /// One line on how to do it.
    public var howTo: String {
        switch self {
        case .straight: "Rest, then the next set."
        case .drop: "Straight after the set before: at least 20% lighter, no rest, as many good reps as you can."
        case .restPause: "Same weight after about \(SetKind.restPauseRestSeconds) s, as many good reps as you can."
        case .myoRep: "Same weight after 3-5 deep breaths, about \(SetKind.myoRepRestSeconds) s: a few reps, stop before form slips."
        case .failure: "Keep going until you can't do another rep with good form."
        }
    }

    /// The evidence in plain words, honest about how strong it is.
    public var evidence: String {
        switch self {
        case .straight:
            "The default."
        case .drop:
            "Drop sets built about as much muscle as normal sets in about half to a third of the time (Coleman 2022; Sødal 2023)."
        case .restPause:
            "Rest-pause built about as much muscle as normal sets, maybe slightly more (Carvalho 2022; Tsartsapakis 2026)."
        case .myoRep:
            "Myo-reps haven't been tested in trials. They're a kind of rest-pause, so expect roughly what rest-pause gives."
        case .failure:
            "Stopping 1-3 reps short builds about as much muscle (Refalo 2024), and failure adds fatigue (Robinson 2024). Best kept to the last set of small lifts."
        }
    }

    /// Rest before a rest-pause mini-set. Common rest-pause protocols use
    /// about 10-20 s between mini-sets (typical protocol in the trials pooled
    /// by Carvalho 2022 and Tsartsapakis 2026; the exact figure is not
    /// re-verified here, so the UI says "about").
    public static let restPauseRestSeconds = 20
    /// Rest before a myo-rep mini-set: "3-5 deep breaths" is the method's own
    /// description, not a trial result; about 15 s.
    public static let myoRepRestSeconds = 15

    /// Rest the timer runs before this stage: none for a drop (the rest
    /// timer is skipped between drop stages, feature spec §3.3), short for
    /// rest-pause and myo-reps; nil for a set that isn't a stage (normal rest).
    public var restBeforeSeconds: Int? {
        switch self {
        case .drop: 0
        case .restPause: SetKind.restPauseRestSeconds
        case .myoRep: SetKind.myoRepRestSeconds
        case .straight, .failure: nil
        }
    }

    /// The styles offered for a set that continues another.
    public static let stageKinds: [SetKind] = [.drop, .restPause, .myoRep]
}

/// Where each set sits in an exercise: warm-up number, working-set number,
/// and for a stage, which stage of which set. Stages belong to the working
/// set before them; a stage with no working set before it (straight after
/// the warm-ups, or first) counts as a working set of its own.
public enum SetStructure {
    public struct Item: Sendable, Equatable {
        public var isWarmup: Bool
        public var kind: SetKind

        public init(isWarmup: Bool, kind: SetKind) {
            self.isWarmup = isWarmup
            self.kind = kind
        }
    }

    public struct Position: Sendable, Equatable {
        /// 1-based among the warm-ups; nil for a working set or stage.
        public var warmUp: Int?
        /// 1-based working-set number; a stage carries its set's number. Nil for a warm-up.
        public var number: Int?
        /// 1-based place among its set's stages; nil for a warm-up or a working set.
        public var stage: Int?
        /// Stages in this set's cluster (on the working set and on each of its stages).
        public var stages: Int = 0

        public var isStage: Bool { stage != nil }
        public var isWarmup: Bool { warmUp != nil }

        public init(warmUp: Int? = nil, number: Int? = nil, stage: Int? = nil, stages: Int = 0) {
            self.warmUp = warmUp
            self.number = number
            self.stage = stage
            self.stages = stages
        }
    }

    public static func positions(_ items: [Item]) -> [Position] {
        var result: [Position] = []
        var warmUps = 0
        var sets = 0
        var leadIndex: Int?
        var leadOf: [Int?] = []
        for item in items {
            if item.isWarmup {
                warmUps += 1
                leadIndex = nil
                result.append(Position(warmUp: warmUps))
                leadOf.append(nil)
            } else if item.kind.isStage, let lead = leadIndex {
                result[lead].stages += 1
                result.append(Position(number: sets, stage: result[lead].stages))
                leadOf.append(lead)
            } else {
                sets += 1
                result.append(Position(number: sets))
                leadIndex = result.count - 1
                leadOf.append(nil)
            }
        }
        for index in result.indices {
            if let lead = leadOf[index] { result[index].stages = result[lead].stages }
        }
        return result
    }

    /// "Warm-up 1 of 3", "Set 2 of 3", "Drop 1 of 2", "Mini-set 2 of 3".
    public static func title(at index: Int, in items: [Item]) -> String {
        let all = positions(items)
        guard index >= 0, index < all.count else { return "Set" }
        let position = all[index]
        if let warmUp = position.warmUp {
            return "Warm-up \(warmUp) of \(all.filter(\.isWarmup).count)"
        }
        if let stage = position.stage {
            return "\(items[index].kind.stageName) \(stage) of \(position.stages)"
        }
        let total = all.filter { !$0.isWarmup && !$0.isStage }.count
        return "Set \(position.number ?? 1) of \(total)"
    }

    /// The most hard sets one set and its stages count for. The trials
    /// compared a drop or rest-pause cluster with about three straight sets
    /// and found similar growth (Coleman 2022; Sødal 2023; Carvalho 2022), so
    /// a cluster counts as the straight sets it stands in for: the set plus
    /// one per stage, up to three. That is also exactly what "Same work, less
    /// time" (`TimeSaver`) replaces (stages = sets − 1), so a converted
    /// session meets its planned sets. The cap and the one-per-stage rule are
    /// the app's reading of those trials, not a trial result; myo-reps are
    /// untested and counted the same way. (This replaces the feature spec's
    /// first "one and a half", which made a converted session look 1.5 sets
    /// short of its plan per exercise and held the weekly volume back.)
    public static let maximumClusterCredit = 3.0

    /// Hard sets for a working set and its stages, for weekly volume: 1 + one
    /// per stage, at most `maximumClusterCredit`. Fatigue (`MuscleRecovery`)
    /// and session effort count it as one set.
    public static func hardSetCredit(stages: Int) -> Double {
        min(maximumClusterCredit, 1 + Double(max(0, stages)))
    }
}

/// "Same work, less time": on a short session, each small (isolation)
/// lift's straight sets become one set followed by drop stages, rest-pause
/// or myo-rep mini-sets, which cuts the rests between them.
///
/// Evidence: drop sets ≈ traditional sets for hypertrophy and strength in
/// about half to a third of the time (Coleman 2022; Sødal 2023, full
/// citations on `SetKind`); rest-pause ≈ traditional, maybe a small edge
/// (Carvalho 2022; Tsartsapakis 2026); myo-reps untested. The time saved is
/// the planner's own estimate (`WorkoutPlanner.estimatedMinutes`), not a
/// figure from the trials. Goal tailoring (feature spec §3.3): the evidence
/// is about muscle growth, so it's offered for muscle and general-health
/// goals; for strength these sets don't replace heavy straight sets.
public enum TimeSaver {
    /// Sessions this short get the offer: the planner's shortest tier
    /// (`WorkoutPlanner.exerciseCount`: 4 exercises at 30 minutes or less)
    /// and the weekly plan's "short version". An app choice.
    public static let shortSessionMinutes = 30

    /// Each drop takes off at least this share of the weight: drop-set
    /// trials mostly cut about 20-30% a stage (protocols in Sødal 2023; not
    /// re-verified here). The UI says "at least 20%": the drop is rounded down to the gym.
    public static let dropFraction = 0.2
    /// At most two drops: 1-3 is the usual range in the trials (not
    /// re-verified); two keeps the stages short. An app choice.
    public static let maximumDrops = 2
    /// Rest-pause mini-sets after the first set (app choice inside the usual 1-3).
    public static let maximumRestPauseStages = 2
    /// Myo-rep mini-sets: the method describes 3-5; the app plans 3.
    public static let myoRepStages = 3
    /// Reps planned for a myo-rep mini-set: the method's 3-5, middle.
    public static let myoRepReps = 4
    /// Seconds a rep takes, from the planner's 45 s for a 6-12 rep set
    /// (`WorkoutPlanner.workSecondsPerSet`; app estimate).
    public static let secondsPerRep = 4
    /// Changing the weight for a drop: pin, rack or plates (app estimate).
    public static let dropChangeSeconds = 15

    /// Stages planned when `sets` straight sets become one: one fewer than
    /// the sets they replace for drops and rest-pause (so the number of
    /// efforts stays the same), capped; myo-reps always plan their three.
    public static func stageCount(for kind: SetKind, replacingSets sets: Int) -> Int {
        switch kind {
        case .drop: max(1, min(maximumDrops, sets - 1))
        case .restPause: max(1, min(maximumRestPauseStages, sets - 1))
        case .myoRep: myoRepStages
        case .straight, .failure: 0
        }
    }

    /// Reps to pre-fill on a stage. They're a starting point (log what you
    /// do): a drop stage at the lighter weight gets about the bottom of the
    /// range, a rest-pause mini-set about a third of it, a myo-rep mini-set
    /// 4 (app estimates).
    public static func stageReps(for kind: SetKind, reps: ClosedRange<Int>) -> Int {
        switch kind {
        case .drop: reps.lowerBound
        case .restPause: max(2, reps.lowerBound / 3)
        case .myoRep: myoRepReps
        case .straight, .failure: reps.upperBound
        }
    }

    /// Time a stage adds, in seconds: its reps plus the weight change or the
    /// short rest before it.
    public static func stageSeconds(for kind: SetKind, reps: Int) -> Int {
        let before = kind == .drop ? dropChangeSeconds : (kind.restBeforeSeconds ?? 0)
        return max(0, reps) * secondsPerRep + before
    }

    /// Drop loads after `load`, each the heaviest the gym can make that's at
    /// least `dropFraction` lighter than the one before (dumbbell rack, stack
    /// pin or plates to strip). Fewer than `stages` when the gym runs out of
    /// lighter weights; empty when there is none.
    public static func dropLoads(from load: Double, kind: EquipmentKind, gym: GymProfile, stages: Int) -> [Double] {
        let loads = gym.achievableLoads(for: kind)
        var result: [Double] = []
        var current = load
        for _ in 0..<max(0, stages) {
            let target = current * (1 - dropFraction)
            guard let next = loads.last(where: { $0 <= target + 0.001 }), next > 0, next < current - 0.001 else { break }
            result.append(next)
            current = next
        }
        return result
    }

    /// True when the exercise can take the style: not the first exercise
    /// (fatigue carries over into everything after it, feature spec §3.3),
    /// an isolation movement (never a multi-joint lift, see below), not core,
    /// not in a superset (a no-rest chain doesn't fit "one set of each, then
    /// rest"), two or more straight sets, and for drops a load the gym can
    /// make lighter.
    ///
    /// Multi-joint lifts (squats, presses, rows, deadlifts) always keep
    /// straight sets. That's a safety choice, not a trial result: stages and
    /// failure with no rest under a heavy bar are where form breaks down, and
    /// strength gains little from going that close to failure (Robinson et
    /// al., Sports Med 2024).
    public static func isEligible(_ exercise: PlannedExercise, at index: Int, kind: SetKind, gym: GymProfile) -> Bool {
        guard kind.isStage, index > 0, exercise.lastSetKind == nil, exercise.supersetGroup == nil, exercise.sets >= 2,
              let slot = ExerciseCatalog.slot(for: exercise.exerciseID), !slot.isCompound, slot != .core else { return false }
        guard kind == .drop else { return true }
        guard let loadKind = exercise.loadKind, gym.has(loadKind), !gym.achievableLoads(for: loadKind).isEmpty else { return false }
        guard let load = exercise.load else { return true }
        return !dropLoads(from: load, kind: loadKind, gym: gym, stages: 1).isEmpty
    }

    /// Makes the exercise's straight sets one set plus stages of `kind`.
    /// Drop loads are rounded to the gym; with no planned load (first time)
    /// the stages say "at least 20% lighter" and carry no load.
    /// Rest-pause and myo-rep stages keep the set's load (`load` nil = same).
    public static func convert(_ exercise: inout PlannedExercise, to kind: SetKind, gym: GymProfile) {
        let count = stageCount(for: kind, replacingSets: exercise.sets)
        let reps = stageReps(for: kind, reps: exercise.reps)
        var stages: [PlannedExercise.Stage]
        if kind == .drop, let load = exercise.load, let loadKind = exercise.loadKind {
            stages = dropLoads(from: load, kind: loadKind, gym: gym, stages: count).map { PlannedExercise.Stage(load: $0, reps: reps) }
        } else {
            stages = Array(repeating: PlannedExercise.Stage(load: nil, reps: reps), count: count)
        }
        guard !stages.isEmpty else { return }
        exercise.sets = 1
        exercise.lastSetKind = kind
        exercise.stages = stages
    }

    /// The workout with every eligible exercise converted, and its time re-estimated.
    public static func apply(_ kind: SetKind, to workout: PlannedWorkout, gym: GymProfile,
                             style: TrainingStyle = .balanced, warmUpMinutes: Int = 0) -> PlannedWorkout {
        var result = workout
        var changed = false
        for index in result.exercises.indices where isEligible(result.exercises[index], at: index, kind: kind, gym: gym) {
            convert(&result.exercises[index], to: kind, gym: gym)
            changed = changed || result.exercises[index].lastSetKind == kind
        }
        guard changed else { return workout }
        let before = WorkoutPlanner.estimatedMinutes(workout.exercises, style: style, warmUpMinutes: warmUpMinutes)
        let after = WorkoutPlanner.estimatedMinutes(result.exercises, style: style, warmUpMinutes: warmUpMinutes)
        result.estimatedMinutes = after
        let saved = max(0, before - after)
        let sentence = "Small lifts as one \(kind.title.lowercased()) each: about \(saved) min less."
        result.rationale = result.rationale.isEmpty ? sentence : result.rationale + " " + sentence
        return result
    }

    /// One style the builder can offer for a short session.
    public struct Option: Sendable, Equatable, Identifiable {
        public var kind: SetKind
        /// The exercises it changes, in plan order.
        public var exerciseNames: [String]
        /// The planner's estimate of the time it saves (whole minutes, at least 1).
        public var minutesSaved: Int

        public var id: String { kind.rawValue }

        public init(kind: SetKind, exerciseNames: [String], minutesSaved: Int) {
            self.kind = kind
            self.exerciseNames = exerciseNames
            self.minutesSaved = minutesSaved
        }
    }

    /// Muscle growth, general health, or no goal set: the evidence is about
    /// hypertrophy. A strength-only goal doesn't get the offer.
    public static func suitsGoals(_ goals: Goals?) -> Bool {
        guard let goals, !goals.focuses.isEmpty else { return true }
        return goals.focuses.contains(.muscle) || goals.focuses.contains(.health)
    }

    /// What to say about strength: for a strength-only goal why there's no
    /// offer, for a mixed goal that the main lifts stay as they are; nil otherwise.
    public static func strengthNote(_ goals: Goals?) -> String? {
        guard let goals, goals.focuses.contains(.strength) else { return nil }
        if suitsGoals(goals) {
            return "For strength these don't replace heavy straight sets, so your main lifts stay as they are."
        }
        return "Drop sets and myo-reps are a muscle-building tool. For strength they don't replace heavy straight sets, so a short strength session keeps them."
    }

    /// The styles to offer on this plan: only for a short session
    /// (`shortSessionMinutes`), a goal they suit, and at least one eligible
    /// exercise; each with the minutes it saves. Drop sets first (the best
    /// evidence), myo-reps last (untested). Styles saving under a minute are left out.
    public static func options(for workout: PlannedWorkout, minutes: Int, goals: Goals?, gym: GymProfile,
                               style: TrainingStyle = .balanced, warmUpMinutes: Int = 0) -> [Option] {
        guard minutes <= shortSessionMinutes, suitsGoals(goals),
              !workout.exercises.contains(where: { $0.lastSetKind != nil }) else { return [] }
        let before = WorkoutPlanner.estimatedMinutes(workout.exercises, style: style, warmUpMinutes: warmUpMinutes)
        var result: [Option] = []
        for kind in SetKind.stageKinds {
            let applied = apply(kind, to: workout, gym: gym, style: style, warmUpMinutes: warmUpMinutes)
            let names = applied.exercises.filter { $0.lastSetKind == kind }.map(\.name)
            let saved = before - WorkoutPlanner.estimatedMinutes(applied.exercises, style: style, warmUpMinutes: warmUpMinutes)
            if !names.isEmpty, saved >= 1 {
                result.append(Option(kind: kind, exerciseNames: names, minutesSaved: saved))
            }
        }
        return result
    }

    /// "Drop set: 12 → 9 → 7 kg, no rest between", "Rest-pause: then 2
    /// mini-sets of about 3, 20 s apart", "Myo-reps (untested): then 3
    /// mini-sets of about 4, 3-5 breaths apart"; nil for straight sets.
    public static func describe(_ exercise: PlannedExercise, unit: LoadUnit) -> String? {
        guard let kind = exercise.lastSetKind, let stages = exercise.stages, !stages.isEmpty else { return nil }
        func fmt(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
        let reps = stages.first?.reps ?? 0
        let plural = stages.count == 1 ? "" : "s"
        switch kind {
        case .drop:
            let loads = stages.compactMap(\.load)
            if let load = exercise.load, loads.count == stages.count {
                let chain = ([load] + loads).map(fmt).joined(separator: " → ")
                return "Drop set: \(chain) \(unit.rawValue), no rest between"
            }
            return "Drop set: then \(stages.count) drop\(plural), each at least 20% lighter, no rest between"
        case .restPause:
            return "Rest-pause: then \(stages.count) mini-set\(plural) of about \(reps), \(SetKind.restPauseRestSeconds) s apart"
        case .myoRep:
            return "Myo-reps (untested in trials): then \(stages.count) mini-set\(plural) of about \(reps), 3-5 breaths apart"
        case .straight, .failure:
            return nil
        }
    }
}
