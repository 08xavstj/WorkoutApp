import Foundation
#if canImport(AppCore)
import AppCore
#endif

/// e.g. "60 kg" / "135 lb".
nonisolated func watchFormat(_ kilograms: Double, unit: String) -> String {
    let value = unit == "lb" ? kilograms * 2.20462 : kilograms
    return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
}

/// The number alone in the gym's unit: "82.5", "185".
nonisolated func watchWeightNumber(_ kilograms: Double, unit: String) -> String {
    let value = unit == "lb" ? kilograms * 2.20462 : kilograms
    return value.formatted(.number.precision(.fractionLength(0...1)))
}

/// "82.5 kilograms", "185 pounds", for VoiceOver.
nonisolated func watchSpokenWeight(_ kilograms: Double, unit: String) -> String {
    "\(watchWeightNumber(kilograms, unit: unit)) \(unit == "lb" ? "pounds" : "kilograms")"
}

/// A set about to be ticked off: what was planned, and the loads the gym can make.
nonisolated struct PendingSet: Identifiable, Equatable, Sendable {
    var exerciseIndex: Int
    var setIndex: Int
    /// Stable ids (`ExerciseSnapshot.id`, `SetSnapshot.order`) for the phone.
    var exerciseID: Int
    var setOrder: Int?
    /// The exercise's id that survives a reorder on the phone (`ExerciseSnapshot.key`).
    var exerciseKey: String?
    var reps: Int
    var weightKg: Double
    /// The reps and weight the snapshot had: what was changed on the wrist is
    /// told apart from what wasn't (`WatchCommand.completeSet`).
    var baseReps: Int
    var baseWeightKg: Double
    /// Effort to pre-select: 10 minus the target reps in reserve, else the planned RPE.
    var suggestedRPE: Int?
    var isWarmup: Bool
    /// A plank or side plank: `reps` are seconds and the weight isn't edited.
    var isHold: Bool
    /// What the crown steps through (`LoadStepper`): the gym's loads around
    /// the planned weight, else steps of its smallest jump.
    var stepper: LoadStepper
    var unit: String
    let id: String

    /// Achievable weights in kg, ascending; never empty.
    var loads: [Double] { stepper.loads }

    init(session: WatchSession, exerciseIndex: Int, setIndex: Int, reps: Int, weightKg: Double) {
        let exercise = session.exercises[exerciseIndex]
        let set = exercise.sets[setIndex]
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        exerciseID = exercise.id
        setOrder = set.order
        exerciseKey = exercise.key
        id = session.setKey(exercise: exerciseIndex, set: setIndex)
        self.reps = reps
        self.weightKg = weightKg
        baseReps = set.reps
        baseWeightKg = set.weightKg
        suggestedRPE = set.suggestedRPE
        isWarmup = set.isWarmup
        isHold = exercise.isHold == true
        unit = session.unit
        // Around the planned weight, so the crown starts on it.
        stepper = LoadStepper(achievableKg: exercise.achievableLoadsKg, weightKg: set.weightKg, stepKg: session.step)
    }
}

/// Reps and weight changed on the wrist before the set is ticked (nil: not changed).
nonisolated struct SetEdit: Equatable, Sendable {
    var reps: Int?
    var weightKg: Double?
}

extension WatchSession.SetSnapshot {
    /// "Target 30 s" for a plank or side plank, whose reps are seconds. Reps in
    /// reserve don't apply to a hold, so they're left out.
    nonisolated var holdTargetLine: String? {
        guard let targetReps, targetReps > 0 else { return nil }
        return "Target \(targetReps) s"
    }

    /// "Last 30 s", or nil without a matching set last time. A hold is timed:
    /// it has no reps left to rate, so no effort is shown.
    nonisolated var holdGhostLine: String? {
        guard let lastReps, lastReps > 0 else { return nil }
        return "Last \(lastReps) s"
    }

    /// "Last time 80 kilograms, 8 reps, 2 in reserve", for VoiceOver.
    nonisolated func spokenGhost(unit: String) -> String? {
        guard let lastReps, lastReps > 0, let lastWeightKg else { return nil }
        var line = lastWeightKg > 0
            ? "Last time \(watchSpokenWeight(lastWeightKg, unit: unit)), \(lastReps) reps"
            : "Last time \(lastReps) reps"
        if let lastRPE {
            let left = Int(max(0, 10 - lastRPE).rounded())
            line += ", \(left) in reserve"
        }
        return line
    }
}

extension WatchWorkoutModel {
    /// The open set of exercise `index` as Done would log it: the wrist's
    /// edits, else the rep counter's count, else the plan.
    func pendingSet(exercise index: Int) -> PendingSet? {
        guard let session = snapshot, index < session.exercises.count,
              let setIndex = session.exercises[index].sets.firstIndex(where: { !$0.isCompleted }) else { return nil }
        let set = session.exercises[index].sets[setIndex]
        let key = session.setKey(exercise: index, set: setIndex)
        let edit = setEdits[key]
        // A hold's "reps" are seconds: never take them from the rep counter.
        let counted = session.exercises[index].isHold == true ? nil : RepCounter.shared.countedReps(forSet: key)
        return PendingSet(session: session, exerciseIndex: index, setIndex: setIndex,
                          reps: edit?.reps ?? counted ?? set.reps, weightKg: edit?.weightKg ?? set.weightKg)
    }

    /// The set Done logs now: the shown exercise's open set (not during the warm-up).
    var currentPendingSet: PendingSet? {
        guard let session = snapshot, session.currentWarmUpStep == nil, let index = shownExercise else { return nil }
        return pendingSet(exercise: index)
    }

    /// Logs the shown set as it stands.
    func logCurrentSet() {
        RepCounter.shared.stop()
        guard let set = currentPendingSet else { return }
        completeSet(set, reps: set.reps, weightKg: set.weightKg, rpe: nil)
    }

    /// Changes the shown set's weight or reps before Done.
    func edit(_ set: PendingSet, reps: Int? = nil, weightKg: Double? = nil) {
        var edit = setEdits[set.id] ?? SetEdit()
        if let reps { edit.reps = reps }
        if let weightKg { edit.weightKg = weightKg }
        guard edit != setEdits[set.id] else { return }
        setEdits[set.id] = edit
    }

    /// The rep counter takes over the reps (Count was tapped): a reps edit goes.
    func clearRepsEdit(_ key: String) {
        guard setEdits[key]?.reps != nil else { return }
        setEdits[key]?.reps = nil
    }
}
