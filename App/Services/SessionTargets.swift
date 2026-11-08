import Foundation
import SwiftData
import AppCore

/// The planned reps and effort for each exercise of a live session, keyed by
/// the session's start time, in UserDefaults (like `SupersetRegistry`).
/// `SetLog.reps` is overwritten with what you did, and `SetLog` has no field
/// for the plan (adding one needs a schema migration), so the targets the
/// live view compares against are kept here. Entries older than two days go.
enum SessionTargets {
    nonisolated struct Target: Codable, Sendable, Equatable {
        var repsLow: Int
        var repsHigh: Int
        /// The planned effort for each working set, 1-10 (block RIR and recovery included).
        var rpe: Double
        /// The planned working weight (kg), so a set-by-set change also moves
        /// sets still at the plan's weight. Optional: older saves decode.
        var loadKg: Double? = nil
        /// The pain cap on this lift's working weight (kg; `PainGuard.loadCapFraction`,
        /// set by the planner). Set-by-set changes never go above it. Nil = no cap.
        var maxLoadKg: Double? = nil
        /// Today's rep target from double progression (`PlannedExercise.targetReps`):
        /// one more than last time at the same weight. Nil = the top of the range.
        var targetReps: Int? = nil
        /// How the weight moved since last time ("Same weight, aim for 7 reps"),
        /// shown under the exercise name. Nil without history.
        var progressionNote: String? = nil
        /// The plan's own rest after a set (`PlannedExercise.restSeconds`: the
        /// abs finisher's short circuit rest). Nil = the usual rest timer.
        var restSeconds: Int? = nil

        /// Reps each working set aims for today.
        var repsToday: Int { targetReps ?? repsHigh }

        /// Reps in reserve the plan asks for.
        var targetRIR: Double { max(0, 10 - rpe) }
    }

    private static let key = "sessionTargets"
    private static let keepSeconds: TimeInterval = 2 * 86_400

    /// Saves the plan's targets by exercise position (`ExerciseLog.order`).
    /// `unit` is the plan's load unit, for the planned weight.
    static func save(_ exercises: [PlannedExercise], for sessionStart: Date, unit: LoadUnit? = nil) {
        var all = load()
        let cutoff = Date.now.addingTimeInterval(-keepSeconds)
        all = all.filter { WatchSession.startDate(for: $0.key).map { $0 >= cutoff } ?? false }
        var entry: [String: Target] = [:]
        for (index, exercise) in exercises.enumerated() {
            entry[String(index)] = target(for: exercise, unit: unit)
        }
        if !entry.isEmpty { all[WatchSession.id(for: sessionStart)] = entry }
        store(all)
    }

    /// Adds targets for exercises appended to a running session (the abs
    /// finisher), at their `orders`, keeping the session's other targets.
    static func add(_ exercises: [PlannedExercise], orders: [Int], for sessionStart: Date, unit: LoadUnit? = nil) {
        var all = load()
        let id = WatchSession.id(for: sessionStart)
        var entry = all[id] ?? [:]
        for (exercise, order) in zip(exercises, orders) {
            entry[String(order)] = target(for: exercise, unit: unit)
        }
        guard !entry.isEmpty else { return }
        all[id] = entry
        store(all)
    }

    private static func target(for exercise: PlannedExercise, unit: LoadUnit?) -> Target {
        var loadKg: Double?
        if let unit, let load = exercise.load, load > 0 { loadKg = unit.toKilograms(load) }
        return Target(repsLow: exercise.reps.lowerBound, repsHigh: exercise.reps.upperBound,
                      rpe: exercise.rpe, loadKg: loadKg, maxLoadKg: exercise.maxLoadKg,
                      targetReps: exercise.targetReps, progressionNote: exercise.progressionNote,
                      restSeconds: exercise.restSeconds)
    }

    static func target(for sessionStart: Date, order: Int) -> Target? {
        load()[WatchSession.id(for: sessionStart)]?[String(order)]
    }

    /// After exercises are reordered: each target moves to its exercise's new
    /// order (`mapping`: old → new; orders not in it stay).
    static func remap(for sessionStart: Date, _ mapping: [Int: Int]) {
        var all = load()
        let id = WatchSession.id(for: sessionStart)
        guard let entry = all[id] else { return }
        all[id] = remapped(entry, mapping)
        store(all)
    }

    private static func load() -> [String: [String: Target]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: [String: Target]].self, from: data) else { return [:] }
        return saved
    }

    private static func store(_ all: [String: [String: Target]]) {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// The one autoregulation change made per exercise per session
/// (`Autoregulation`), keyed by session start and exercise order, so it
/// happens at most once and the live view and the Watch can show it.
enum AutoregulationLog {
    nonisolated struct Entry: Codable, Sendable, Equatable {
        /// `SetLog.order` of the first set that was changed.
        var setOrder: Int
        /// "Next set 62.5 kg (you had 3 in reserve)".
        var message: String
        /// The new target reps when the change was to reps.
        var reps: Int?
        /// The sets as they were before the change, for Undo. Nil when nothing
        /// changed (a pain hold) or for entries saved before Undo existed.
        var restore: [Restore]? = nil
        /// True once undone: the note goes, and no second change is made
        /// (still at most one per exercise per session).
        var undone: Bool? = nil

        nonisolated struct Restore: Codable, Sendable, Equatable {
            var setOrder: Int
            var weightKg: Double
            var reps: Int
        }

        /// Shown on the phone and the Watch while its set is still to do.
        var isShown: Bool { undone != true }
    }

    private static let key = "autoregulationLog"
    private static let keepSeconds: TimeInterval = 2 * 86_400

    static func entry(for sessionStart: Date, order: Int) -> Entry? {
        load()[WatchSession.id(for: sessionStart)]?[String(order)]
    }

    static func save(_ entry: Entry, for sessionStart: Date, order: Int) {
        var all = load()
        let cutoff = Date.now.addingTimeInterval(-keepSeconds)
        all = all.filter { WatchSession.startDate(for: $0.key).map { $0 >= cutoff } ?? false }
        let id = WatchSession.id(for: sessionStart)
        var session = all[id] ?? [:]
        session[String(order)] = entry
        all[id] = session
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// After exercises are reordered: each entry moves to its exercise's new order.
    static func remap(for sessionStart: Date, _ mapping: [Int: Int]) {
        var all = load()
        let id = WatchSession.id(for: sessionStart)
        guard let session = all[id] else { return }
        all[id] = remapped(session, mapping)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load() -> [String: [String: Entry]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: [String: Entry]].self, from: data) else { return [:] }
        return saved
    }
}

/// Live-set helpers shared by the workout screen and `WatchSync`: last
/// session's matching sets ("ghosts"), the targets, the set-by-set load
/// change (`Autoregulation`) and end-of-exercise records (`SetFeedback`).
enum LiveSetCoach {
    /// Reps in reserve the plan asks of this exercise: the session's planned
    /// effort, else the training block's week (`TrainingBlock.WeekState.targetRIR`).
    static func targetRIR(sessionStart: Date, order: Int, blockRIR: Int?) -> Double? {
        if let target = SessionTargets.target(for: sessionStart, order: order) { return target.targetRIR }
        return blockRIR.map { Double($0) }
    }

    /// Target reps for a set: today's planned reps (`Target.repsToday`), or
    /// the reps an autoregulation change set from this set on.
    static func targetReps(for set: SetLog, target: SessionTargets.Target?, entry: AutoregulationLog.Entry?) -> Int? {
        // A drop stage or mini-set is "as many good reps as you can", not a target (`SetKind`).
        if set.kind.isStage { return nil }
        if let entry, entry.isShown, let reps = entry.reps, set.order >= entry.setOrder { return reps }
        return target?.repsToday
    }

    /// After a working set is ticked: compares its RPE with the target and,
    /// when the gap is two reps or more, changes the remaining sets that are
    /// still at the logged weight or the plan's weight (ones you've set to
    /// something else are left alone). At most once per exercise per session;
    /// never off the first working set. Only straight sets count
    /// (`SetKind.allowsAutoregulation`): a set to failure is RPE 10 on purpose
    /// and drop stages or mini-sets are fatigued by design, so neither moves
    /// the load, and stages are never changed. Never above the plan's pain cap
    /// (`Target.maxLoadKg`): a "go heavier" there is held, and says why. Nil
    /// (and nothing saved) when no set changed, so the note never claims a
    /// change that wasn't made.
    @discardableResult
    static func autoregulate(after set: SetLog, in exercise: ExerciseLog, sessionStart: Date,
                             gym: GymProfile, blockRIR: Int? = nil) -> AutoregulationLog.Entry? {
        guard set.isCompleted, !set.isWarmup, set.kind.allowsAutoregulation,
              AutoregulationLog.entry(for: sessionStart, order: exercise.order) == nil,
              let rir = targetRIR(sessionStart: sessionStart, order: exercise.order, blockRIR: blockRIR) else { return nil }
        let working = exercise.orderedSets.filter { !$0.isWarmup && !$0.kind.isStage }
        guard let index = working.firstIndex(where: { $0.persistentModelID == set.persistentModelID }) else { return nil }
        let remaining = working.dropFirst(index + 1).filter { !$0.isCompleted }
        guard let next = remaining.first else { return nil }
        let kind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load
        // A loaded lift logged without a weight: nothing to adjust from.
        if kind != nil, set.weightKg <= 0 { return nil }
        let unit = gym.unit
        let logged = LiftProgress.LoggedSet(weight: unit.fromKilograms(set.weightKg), reps: set.reps, rpe: set.rpe)
        guard let suggestion = Autoregulation.nextSet(after: logged, setNumber: index + 1, targetRIR: rir,
                                                      alreadyAdjusted: false, kind: kind, gym: gym),
              let message = suggestion.message(unit: unit.rawValue) else { return nil }
        let target = SessionTargets.target(for: sessionStart, order: exercise.order)
        // Pain cap: no heavier load past it, and no extra reps at it.
        if let cap = target?.maxLoadKg {
            let past = switch suggestion.change {
            case .loadUp: unit.toKilograms(suggestion.load) > cap + 0.01
            case .addReps: set.weightKg >= cap - 0.01
            case .hold, .loadDown, .trimReps: false
            }
            if past {
                let held = AutoregulationLog.Entry(setOrder: next.order, message: painHoldMessage(for: exercise.exerciseID), reps: nil)
                AutoregulationLog.save(held, for: sessionStart, order: exercise.order)
                return held
            }
        }
        let changesReps = suggestion.change == .trimReps || suggestion.change == .addReps
        let plannedKg = target?.loadKg
        // A set you've set to some other weight is yours: left alone.
        func isEligible(_ upcoming: SetLog) -> Bool {
            abs(upcoming.weightKg - set.weightKg) < 0.01 || plannedKg.map { abs(upcoming.weightKg - $0) < 0.01 } == true
        }
        // The note says "Next set …", so the next set must be one that changes.
        guard isEligible(next) else { return nil }
        var restore: [AutoregulationLog.Entry.Restore] = []
        for upcoming in remaining where isEligible(upcoming) {
            let before = AutoregulationLog.Entry.Restore(setOrder: upcoming.order, weightKg: upcoming.weightKg, reps: upcoming.reps)
            if changesReps {
                guard upcoming.reps != suggestion.reps else { continue }
                upcoming.reps = suggestion.reps
            } else {
                let newKg = unit.toKilograms(suggestion.load)
                guard abs(upcoming.weightKg - newKg) >= 0.01 else { continue }
                upcoming.weightKg = newKg
            }
            restore.append(before)
        }
        guard let first = restore.first else { return nil }
        let entry = AutoregulationLog.Entry(setOrder: first.setOrder, message: message,
                                            reps: changesReps ? suggestion.reps : nil, restore: restore)
        AutoregulationLog.save(entry, for: sessionStart, order: exercise.order)
        return entry
    }

    /// "Held: easing your knee" for a lift that loads a sore area
    /// (`PainGuard.areas`, the newest reports in the trainer's log); "Held for
    /// pain" when the area isn't clear.
    static func painHoldMessage(for exerciseID: String) -> String {
        guard let slot = ExerciseCatalog.slot(for: exerciseID) else { return "Held for pain" }
        let loaded = PainGuard.areas(forExerciseID: exerciseID, slot: slot)
        let sore = PainGuard.active(PainLogStore.shared.reports, today: .now).map(\.area).filter { loaded.contains($0) }
        if let area = sore.first ?? (loaded.count == 1 ? loaded.first : nil) {
            return "Held: easing \(area.possessive)"
        }
        return "Held for pain"
    }

    /// Undo for the set-by-set change: puts the sets it changed back and
    /// marks the change undone (so no second one is made this session).
    static func undo(_ entry: AutoregulationLog.Entry, in exercise: ExerciseLog, sessionStart: Date) {
        for item in entry.restore ?? [] {
            guard let set = exercise.sets.first(where: { $0.order == item.setOrder }), !set.isCompleted else { continue }
            set.weightKg = item.weightKg
            set.reps = item.reps
        }
        var undone = entry
        undone.undone = true
        AutoregulationLog.save(undone, for: sessionStart, order: exercise.order)
    }

    // MARK: Ghosts

    /// Last session's working sets per exercise (kg), cached for the live session.
    private static var ghostCache: [String: [LiftProgress.LoggedSet]] = [:]
    private static var ghostSession = ""

    /// The most recent earlier session's completed working sets for an
    /// exercise, in kg, in order (`LiftHistory.previousSets`).
    static func previousWorking(for exerciseID: String, before start: Date, context: ModelContext?) -> [LiftProgress.LoggedSet] {
        let session = WatchSession.id(for: start)
        if ghostSession != session {
            ghostSession = session
            ghostCache = [:]
        }
        if let cached = ghostCache[exerciseID] { return cached }
        guard let context else { return [] }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt < start },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        let sessions = (try? context.fetch(descriptor)) ?? []
        let sets = LiftHistory.previousSets(for: exerciseID, before: start, in: sessions)
            .filter { !$0.isWarmup && !$0.kind.isStage }
            .map { LiftProgress.LoggedSet(weight: $0.weightKg, reps: $0.reps, rpe: $0.rpe) }
        ghostCache[exerciseID] = sets
        return sets
    }

    /// The exercise's sets for the Watch, with last time's matching set, the
    /// target and the autoregulation note on the set it changed.
    static func watchSets(for exercise: ExerciseLog, sessionStart: Date, context: ModelContext?) -> [WatchSession.SetSnapshot] {
        let ghosts = previousWorking(for: exercise.exerciseID, before: sessionStart, context: context)
        let target = SessionTargets.target(for: sessionStart, order: exercise.order)
        let entry = AutoregulationLog.entry(for: sessionStart, order: exercise.order)
        var result: [WatchSession.SetSnapshot] = []
        var workingIndex = 0
        let ordered = exercise.orderedSets
        let items = structureItems(ordered)
        let positions = SetStructure.positions(items)
        for (index, set) in ordered.enumerated() {
            var snapshot = WatchSession.SetSnapshot(reps: set.reps, weightKg: set.weightKg, isCompleted: set.isCompleted,
                                                    isWarmup: set.isWarmup, rpe: set.rpe)
            // Set type (`SetKind`): the Watch labels it and runs the stage's short rest (none for a drop).
            snapshot.title = SetStructure.title(at: index, in: items)
            if set.kind != .straight { snapshot.kind = set.kind.rawValue }
            if positions[index].isStage {
                snapshot.restBeforeSeconds = set.kind.restBeforeSeconds
                if !set.isCompleted { snapshot.note = set.kind.howTo }
            } else if !set.isWarmup {
                if workingIndex < ghosts.count {
                    let ghost = ghosts[workingIndex]
                    snapshot.lastWeightKg = ghost.weight
                    snapshot.lastReps = ghost.reps
                    snapshot.lastRPE = ghost.rpe
                }
                snapshot.targetReps = targetReps(for: set, target: target, entry: entry)
                snapshot.targetRIR = target?.targetRIR
                if let entry, entry.isShown, entry.setOrder == set.order, !set.isCompleted {
                    snapshot.note = entry.message
                } else if set.kind == .failure, !set.isCompleted {
                    snapshot.note = set.kind.howTo
                }
                workingIndex += 1
            }
            result.append(snapshot)
        }
        return result
    }

    // MARK: Records

    /// e1RM, rep and volume records for an exercise once its sets are done,
    /// against every earlier session of it, in the workout's unit (`SetFeedback.records`).
    /// Drop stages and mini-sets are left out on both sides: a first-ever
    /// light drop weight isn't a rep record, and fatigued stages aren't e1RM evidence.
    static func records(for exercise: ExerciseLog, sessionStart: Date, sessions: [WorkoutSession], unit: WeightUnit) -> [SetFeedback.Record] {
        let today = exercise.orderedSets
            .filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage }
            .map { LiftProgress.LoggedSet(weight: unit.display($0.weightKg), reps: $0.reps, rpe: $0.rpe) }
        let earlier = sessions
            .filter { !$0.isActive && $0.startedAt < sessionStart }
            .compactMap { session -> LiftProgress.LoggedSession? in
                let sets = session.exercises
                    .filter { $0.exerciseID == exercise.exerciseID }
                    .flatMap(\.sets)
                    .filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage }
                    .map { LiftProgress.LoggedSet(weight: unit.display($0.weightKg), reps: $0.reps, rpe: $0.rpe) }
                return sets.isEmpty ? nil : LiftProgress.LoggedSession(date: session.startedAt, sets: sets)
            }
        return SetFeedback.records(today: today, earlier: earlier)
    }

    // MARK: Set types

    /// The sets as `SetStructure` sees them (warm-up flag and `SetKind`), in order.
    static func structureItems(_ sets: [SetLog]) -> [SetStructure.Item] {
        sets.map { SetStructure.Item(isWarmup: $0.isWarmup, kind: $0.kind) }
    }

    /// "Warm-up 1 of 3", "Set 2 of 3", "Drop 1 of 2" for a set of an exercise.
    static func title(for set: SetLog, in sets: [SetLog]) -> String {
        let index = sets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0
        return SetStructure.title(at: index, in: structureItems(sets))
    }

    /// The rest before the exercise's next set when that set is a drop stage
    /// or mini-set (`SetKind.restBeforeSeconds`: 0 for a drop, about 20 s for
    /// rest-pause, 15 s for myo-reps); nil when it's a normal set or there is none.
    static func stageRest(before exercise: ExerciseLog) -> Int? {
        let sets = exercise.orderedSets
        guard let index = sets.firstIndex(where: { !$0.isCompleted }) else { return nil }
        let positions = SetStructure.positions(structureItems(sets))
        guard positions[index].isStage else { return nil }
        return sets[index].kind.restBeforeSeconds
    }
}

/// A per-session entry keyed by exercise order, moved to the new orders
/// after a reorder (`mapping`: old → new; others keep theirs).
private func remapped<Value>(_ entry: [String: Value], _ mapping: [Int: Int]) -> [String: Value] {
    var result: [String: Value] = [:]
    for (key, value) in entry {
        let order = Int(key).map { mapping[$0] ?? $0 }
        result[order.map { String($0) } ?? key] = value
    }
    return result
}
