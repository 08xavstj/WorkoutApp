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

        /// Reps in reserve the plan asks for.
        var targetRIR: Double { max(0, 10 - rpe) }
    }

    private static let key = "sessionTargets"
    private static let keepSeconds: TimeInterval = 2 * 86_400

    /// Saves the plan's targets by exercise position (`ExerciseLog.order`).
    static func save(_ exercises: [PlannedExercise], for sessionStart: Date) {
        var all = load()
        let cutoff = Date.now.addingTimeInterval(-keepSeconds)
        all = all.filter { WatchSession.startDate(for: $0.key).map { $0 >= cutoff } ?? false }
        var entry: [String: Target] = [:]
        for (index, exercise) in exercises.enumerated() {
            entry[String(index)] = Target(repsLow: exercise.reps.lowerBound, repsHigh: exercise.reps.upperBound, rpe: exercise.rpe)
        }
        if !entry.isEmpty { all[WatchSession.id(for: sessionStart)] = entry }
        store(all)
    }

    static func target(for sessionStart: Date, order: Int) -> Target? {
        load()[WatchSession.id(for: sessionStart)]?[String(order)]
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

    /// Target reps for a set: the planned top of the range, or the reps an
    /// autoregulation change set from this set on.
    static func targetReps(for set: SetLog, target: SessionTargets.Target?, entry: AutoregulationLog.Entry?) -> Int? {
        if let entry, let reps = entry.reps, set.order >= entry.setOrder { return reps }
        return target?.repsHigh
    }

    /// After a working set is ticked: compares its RPE with the target and,
    /// when the gap is two reps or more, changes the remaining sets that are
    /// still at the same weight (ones you've edited are left alone). At most
    /// once per exercise per session; never off the first working set.
    @discardableResult
    static func autoregulate(after set: SetLog, in exercise: ExerciseLog, sessionStart: Date,
                             gym: GymProfile, blockRIR: Int? = nil) -> AutoregulationLog.Entry? {
        guard set.isCompleted, !set.isWarmup,
              AutoregulationLog.entry(for: sessionStart, order: exercise.order) == nil,
              let rir = targetRIR(sessionStart: sessionStart, order: exercise.order, blockRIR: blockRIR) else { return nil }
        let working = exercise.orderedSets.filter { !$0.isWarmup }
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
        let changesReps = suggestion.change == .trimReps || suggestion.change == .addReps
        for upcoming in remaining where abs(upcoming.weightKg - set.weightKg) < 0.01 {
            if changesReps {
                upcoming.reps = suggestion.reps
            } else {
                upcoming.weightKg = unit.toKilograms(suggestion.load)
            }
        }
        let entry = AutoregulationLog.Entry(setOrder: next.order, message: message, reps: changesReps ? suggestion.reps : nil)
        AutoregulationLog.save(entry, for: sessionStart, order: exercise.order)
        return entry
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
            .filter { !$0.isWarmup }
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
        for set in exercise.orderedSets {
            var snapshot = WatchSession.SetSnapshot(reps: set.reps, weightKg: set.weightKg, isCompleted: set.isCompleted,
                                                    isWarmup: set.isWarmup, rpe: set.rpe)
            if !set.isWarmup {
                if workingIndex < ghosts.count {
                    let ghost = ghosts[workingIndex]
                    snapshot.lastWeightKg = ghost.weight
                    snapshot.lastReps = ghost.reps
                    snapshot.lastRPE = ghost.rpe
                }
                snapshot.targetReps = targetReps(for: set, target: target, entry: entry)
                snapshot.targetRIR = target?.targetRIR
                if let entry, entry.setOrder == set.order, !set.isCompleted {
                    snapshot.note = entry.message
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
    static func records(for exercise: ExerciseLog, sessionStart: Date, sessions: [WorkoutSession], unit: WeightUnit) -> [SetFeedback.Record] {
        let today = exercise.orderedSets
            .filter { $0.isCompleted && !$0.isWarmup }
            .map { LiftProgress.LoggedSet(weight: unit.display($0.weightKg), reps: $0.reps, rpe: $0.rpe) }
        let earlier = sessions
            .filter { !$0.isActive && $0.startedAt < sessionStart }
            .compactMap { session -> LiftProgress.LoggedSession? in
                let sets = session.exercises
                    .filter { $0.exerciseID == exercise.exerciseID }
                    .flatMap(\.sets)
                    .filter { $0.isCompleted && !$0.isWarmup }
                    .map { LiftProgress.LoggedSet(weight: unit.display($0.weightKg), reps: $0.reps, rpe: $0.rpe) }
                return sets.isEmpty ? nil : LiftProgress.LoggedSession(date: session.startedAt, sets: sets)
            }
        return SetFeedback.records(today: today, earlier: earlier)
    }
}
