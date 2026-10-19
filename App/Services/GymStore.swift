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
    var planner: WorkoutPlanner { WorkoutPlanner(gym: profile, style: style) }

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
                let working = exercise.sets.filter { $0.isCompleted && !$0.isWarmup && $0.reps > 0 }
                guard let top = working.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) else { continue }
                let e1RM = unit.fromKilograms(top.estimatedOneRepMax)
                let previousBest = result[exercise.exerciseID]?.bestEstimatedOneRepMax ?? 0
                result[exercise.exerciseID] = ExerciseHistory(
                    bestEstimatedOneRepMax: max(previousBest, e1RM),
                    lastWeight: unit.fromKilograms(top.weightKg),
                    lastReps: top.reps,
                    lastRPE: top.rpe,
                    lastDate: session.startedAt
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

    /// Best e1RM (kg) before a date, for PR detection.
    static func bestOneRepMax(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> Double {
        sessions
            .filter { !$0.isActive && $0.startedAt < date }
            .flatMap { $0.exercises.filter { $0.exerciseID == exerciseID } }
            .flatMap { $0.sets.filter { $0.isCompleted && !$0.isWarmup } }
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

    struct BuilderRequest: Identifiable, Equatable {
        let id = UUID()
        var focus: WorkoutFocus?
        var minutes: Int?
    }

    func openBuilder(focus: WorkoutFocus? = nil, minutes: Int? = nil) {
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
        let session = WorkoutSession(name: name)
        context.insert(session)
        for (order, planned) in exercises.enumerated() {
            let log = ExerciseLog(exerciseID: planned.exerciseID, name: planned.name, order: order)
            log.session = session
            context.insert(log)
            let weightKg = planned.load.map { unit.toKilograms($0) } ?? 0
            for index in 0..<max(1, planned.sets) {
                let set = SetLog(order: index, weightKg: weightKg, reps: planned.reps.upperBound, rpe: nil)
                set.exercise = log
                context.insert(set)
            }
        }
        try? context.save()
        activeSession = session
    }

    func startEmpty(in context: ModelContext) {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = hour < 12 ? "Morning Workout" : (hour < 17 ? "Afternoon Workout" : "Evening Workout")
        let session = WorkoutSession(name: name)
        context.insert(session)
        try? context.save()
        activeSession = session
    }
}
