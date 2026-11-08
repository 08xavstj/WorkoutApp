import Foundation
import SwiftData
import AppCore

/// Your gym setup (equipment, plates, dumbbells, stacks), saved on the phone.
@Observable
final class GymStore {
    private(set) var profile: GymProfile
    /// False until you've opened My Gym and saved it at least once.
    private(set) var isConfigured: Bool

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "gymProfile"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(GymProfile.self, from: data) {
            profile = saved
            isConfigured = true
        } else {
            // Until My Gym is set up, match the unit chosen in Settings.
            profile = defaults.string(forKey: "weightUnit") == "kg" ? .commercialKilograms : .commercialPounds
            isConfigured = false
        }
    }

    /// Set from the user's goals (rep ranges and effort).
    var style: TrainingStyle = .balanced
    var planner: WorkoutPlanner {
        var planner = WorkoutPlanner(gym: profile, style: style)
        planner.progressionModes = ProgressionPreferences.overrides()
        return planner
    }

    /// The one unit every lifting screen shows weights in: the gym's, so the
    /// numbers match the plates on the bar (Settings' unit is for body weight).
    var liftingUnit: WeightUnit { profile.unit == .kg ? .kilograms : .pounds }

    func save(_ profile: GymProfile) {
        self.profile = profile
        isConfigured = true
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Builds the trainer's view of your lifting history from logged sessions.
enum LiftHistory {
    /// Best e1RM and most recent top set per exercise, in the gym's unit.
    static func make(from sessions: [WorkoutSession], unit: LoadUnit) -> [String: ExerciseHistory] {
        var result: [String: ExerciseHistory] = [:]
        // Oldest first so the newest session wins for "last" values.
        for session in sessions.filter({ !$0.isActive }).sorted(by: { $0.startedAt < $1.startedAt }) {
            for exercise in session.exercises {
                // Drop stages and mini-sets are lighter or fatigued by design: not the lift's top set.
                let working = exercise.sets.filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage && $0.reps > 0 }
                guard let top = working.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) else { continue }
                let e1RM = unit.fromKilograms(top.estimatedOneRepMax)
                let previous = result[exercise.exerciseID]
                let previousBest = previous?.bestEstimatedOneRepMax ?? 0
                let topWeight = unit.fromKilograms(top.weightKg)
                // The last few top weights and last session's sets, for rep and set progression.
                result[exercise.exerciseID] = ExerciseHistory(
                    bestEstimatedOneRepMax: max(previousBest, e1RM),
                    lastWeight: topWeight,
                    lastReps: top.reps,
                    lastRPE: top.rpe,
                    lastDate: session.startedAt,
                    recentWeights: ExerciseHistory.appending(topWeight, to: previous?.recentWeights ?? []),
                    lastSets: working.count
                )
            }
        }
        return result
    }

    /// Completed sets from the most recent finished session that included this exercise.
    static func previousSets(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> [SetLog] {
        let previous = sessions
            .filter { !$0.isActive && $0.startedAt < date }
            .sorted { $0.startedAt > $1.startedAt }
            .lazy
            .compactMap { session in session.exercises.first { $0.exerciseID == exerciseID } }
            .first
        return previous?.orderedSets.filter(\.isCompleted) ?? []
    }

    // MARK: Live-workout cache

    /// The live workout asks for every open card's history on each render;
    /// sorting all sessions each time is wasted work, so answers are kept per
    /// session start and session count (a finished or deleted session resets it).
    private static var cacheKey = ""
    private static var previousCache: [String: [SetLog]] = [:]
    private static var bestCache: [String: Double] = [:]

    private static func resetCache(before date: Date, sessions: [WorkoutSession]) {
        let key = "\(date.timeIntervalSinceReferenceDate)/\(sessions.count)"
        guard key != cacheKey else { return }
        cacheKey = key
        previousCache = [:]
        bestCache = [:]
    }

    /// `previousSets`, cached for the live workout.
    static func cachedPreviousSets(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> [SetLog] {
        resetCache(before: date, sessions: sessions)
        if let cached = previousCache[exerciseID] { return cached }
        let sets = previousSets(for: exerciseID, before: date, in: sessions)
        previousCache[exerciseID] = sets
        return sets
    }

    /// `bestOneRepMax`, cached for the live workout.
    static func cachedBestOneRepMax(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> Double {
        resetCache(before: date, sessions: sessions)
        if let cached = bestCache[exerciseID] { return cached }
        let best = bestOneRepMax(for: exerciseID, before: date, in: sessions)
        bestCache[exerciseID] = best
        return best
    }

    /// Best e1RM (kg) before a date, for PR detection.
    static func bestOneRepMax(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> Double {
        sessions
            .filter { !$0.isActive && $0.startedAt < date }
            .flatMap { $0.exercises.filter { $0.exerciseID == exerciseID } }
            .flatMap { $0.sets.filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage } }
            .map(\.estimatedOneRepMax)
            .max() ?? 0
    }

    /// Exercise IDs from sessions in the last `days` days, newest first.
    static func recentExerciseIDs(_ sessions: [WorkoutSession], days: Int = 4, now: Date = .now) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return sessions
            .filter { !$0.isActive && $0.startedAt >= cutoff }
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap { $0.orderedExercises.map(\.exerciseID) }
    }
}

/// Starting a workout from a plan, from anywhere in the app.
@Observable
final class WorkoutLauncher {
    var activeSession: WorkoutSession?
    /// Set to open the workout builder sheet.
    var builderRequest: BuilderRequest?
    /// Set when the Apple Watch asks to finish (`WatchSync`): the workout
    /// screen opens its finish sheet and clears it.
    var pendingFinish = false
    /// The workout in progress, kept current by the app from its sessions. Every
    /// start (Today, Log, Fitness, Coach, the Watch) resumes it instead of
    /// starting a second one.
    var running: WorkoutSession?

    /// The running workout, if it still exists and hasn't ended.
    private var resumable: WorkoutSession? {
        guard let running, !running.isDeleted, running.modelContext != nil, running.isActive else { return nil }
        return running
    }

    /// Opens the workout in progress instead of starting another; false when none runs.
    private func resumeIfRunning() -> Bool {
        guard let resumable else { return false }
        builderRequest = nil
        activeSession = resumable
        return true
    }

    struct BuilderRequest: Identifiable, Equatable {
        let id = UUID()
        var focus: WorkoutFocus?
        var minutes: Int?
    }

    func openBuilder(focus: WorkoutFocus? = nil, minutes: Int? = nil) {
        if resumeIfRunning() { return }
        builderRequest = BuilderRequest(focus: focus, minutes: minutes)
    }

    /// Creates a session pre-filled with the plan's exercises and sets.
    func start(_ plan: PlannedWorkout, in context: ModelContext) {
        start(name: plan.title, exercises: plan.exercises, unit: plan.unit, in: context)
    }

    /// Starts one of your own workouts. Your exercises, sets, reps and any
    /// weights you set are used as they are; missing weights are suggested
    /// from your history (loadable with your gym's plates where it knows how).
    func start(_ template: WorkoutTemplate, gym: GymStore, sessions: [WorkoutSession], library: ExerciseLibrary, in context: ModelContext) {
        if resumeIfRunning() { return }
        let unit = gym.profile.unit
        let history = LiftHistory.make(from: sessions, unit: unit)
        let items = template.orderedExercises.map { exercise in
            TemplateItem(
                exerciseID: exercise.exerciseID,
                name: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                rpe: exercise.targetRPE,
                weight: exercise.weightKg.map { unit.fromKilograms($0) },
                libraryLoad: EquipmentKind.fromLibrary(library.exercise(id: exercise.exerciseID)?.equipment)
            )
        }
        let planned = gym.planner.prescribe(template: items, history: history)
        template.lastUsedAt = .now
        start(name: template.name, exercises: planned, unit: unit, in: context)
    }

    private func start(name: String, exercises: [PlannedExercise], unit: LoadUnit, in context: ModelContext) {
        if resumeIfRunning() { return }
        let session = WorkoutSession(name: name)
        context.insert(session)
        for (order, planned) in exercises.enumerated() {
            Self.insertLog(planned, order: order, in: session, unit: unit, context: context)
        }
        // Superset pairs (`Supersets`) for the live view: exercise order → group.
        SupersetRegistry.save(SupersetRegistry.groups(in: exercises), for: session.startedAt)
        SessionTargets.save(exercises, for: session.startedAt, unit: unit)
        try? context.save()
        running = session
        activeSession = session
    }

    /// One planned exercise as an `ExerciseLog` with its sets, in the session.
    private static func insertLog(_ planned: PlannedExercise, order: Int, in session: WorkoutSession, unit: LoadUnit,
                                  context: ModelContext) {
        let log = ExerciseLog(exerciseID: planned.exerciseID, name: planned.name, order: order)
        log.session = session
        context.insert(log)
        let weightKg = planned.load.map { unit.toKilograms($0) } ?? 0
        // Warm-up ramp sets first (`WarmUp`), marked so they stay out of volume, strain and PRs.
        let warmUps = planned.warmUpSets ?? []
        for (index, ramp) in warmUps.enumerated() {
            let set = SetLog(order: index, weightKg: unit.toKilograms(ramp.load), reps: ramp.reps, rpe: nil, isWarmup: true)
            set.exercise = log
            context.insert(set)
        }
        for index in 0..<max(1, planned.sets) {
            let set = SetLog(order: warmUps.count + index, weightKg: weightKg, reps: planned.repsToday, rpe: nil)
            set.exercise = log
            context.insert(set)
        }
        // Time-saving sets (`TimeSaver`): the drop stages or mini-sets after the last set.
        if let kind = planned.lastSetKind, let stages = planned.stages {
            let first = warmUps.count + max(1, planned.sets)
            for (index, stage) in stages.enumerated() {
                let stageKg = stage.load.map { unit.toKilograms($0) } ?? weightKg
                let set = SetLog(order: first + index, weightKg: stageKg, reps: stage.reps, rpe: nil, kind: kind)
                set.exercise = log
                context.insert(set)
            }
        }
    }

    /// Adds planned exercises (the abs finisher, `AbsFinisher`) to the end of a
    /// running session: orders continue past the highest, and their targets
    /// and superset pairs join the session's (`SessionTargets`, `SupersetRegistry`).
    /// Returns the orders used.
    @discardableResult
    func append(_ exercises: [PlannedExercise], to session: WorkoutSession, unit: LoadUnit, in context: ModelContext) -> [Int] {
        guard !exercises.isEmpty else { return [] }
        // One past the highest order: targets, supersets, records and the Watch are keyed by it.
        let first = (session.exercises.map(\.order).max() ?? -1) + 1
        let orders = exercises.indices.map { first + $0 }
        for (planned, order) in zip(exercises, orders) {
            Self.insertLog(planned, order: order, in: session, unit: unit, context: context)
        }
        var groups = SupersetRegistry.groups(for: session.startedAt)
        for (planned, order) in zip(exercises, orders) {
            if let group = planned.supersetGroup { groups[order] = group }
        }
        SupersetRegistry.save(groups, for: session.startedAt)
        SessionTargets.add(exercises, orders: orders, for: session.startedAt, unit: unit)
        try? context.save()
        return orders
    }

    func startEmpty(in context: ModelContext) {
        if resumeIfRunning() { return }
        let hour = Calendar.current.component(.hour, from: .now)
        let name = hour < 12 ? "Morning Workout" : (hour < 17 ? "Afternoon Workout" : "Evening Workout")
        let session = WorkoutSession(name: name)
        context.insert(session)
        try? context.save()
        running = session
        activeSession = session
    }
}
