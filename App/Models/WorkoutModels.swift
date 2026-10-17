import Foundation
import SwiftData
import AppCore

/// A gym session. Weights are always stored in kilograms; the UI converts.
@Model
final class WorkoutSession {
    var startedAt: Date
    var endedAt: Date?
    var name: String
    /// How hard the whole session felt, 1-10. Asked for when you finish.
    var sessionRPE: Int?
    var notes: String
    /// True once the session has been written to Apple Health.
    var savedToHealth: Bool

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    var exercises: [ExerciseLog] = []

    init(name: String = "Workout", startedAt: Date = .now) {
        self.name = name
        self.startedAt = startedAt
        self.notes = ""
        self.savedToHealth = false
    }

    var isActive: Bool { endedAt == nil }

    var orderedExercises: [ExerciseLog] {
        exercises.sorted { $0.order < $1.order }
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    var workingSets: [SetLog] {
        exercises.flatMap(\.sets).filter { $0.isCompleted && !$0.isWarmup }
    }

    var totalVolumeKg: Double {
        workingSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    /// The summary the strain calculator works on.
    var strainSummary: StrengthSessionSummary {
        StrengthSessionSummary(
            start: startedAt,
            end: endedAt ?? .now,
            sessionRPE: sessionRPE.map(Double.init),
            setRPEs: workingSets.compactMap(\.rpe),
            workingSets: workingSets.count,
            totalVolumeKg: totalVolumeKg
        )
    }
}

@Model
final class ExerciseLog {
    /// Matches `Exercise.id` in the bundled exercise library.
    var exerciseID: String
    var name: String
    var order: Int
    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise)
    var sets: [SetLog] = []

    init(exerciseID: String, name: String, order: Int) {
        self.exerciseID = exerciseID
        self.name = name
        self.order = order
    }

    var orderedSets: [SetLog] {
        sets.sorted { $0.order < $1.order }
    }
}

@Model
final class SetLog {
    var order: Int
    var weightKg: Double
    var reps: Int
    /// Optional effort for this set, 1-10.
    var rpe: Double?
    var isWarmup: Bool
    var completedAt: Date?
    var exercise: ExerciseLog?

    init(order: Int, weightKg: Double = 0, reps: Int = 0, rpe: Double? = nil, isWarmup: Bool = false) {
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
    }

    var isCompleted: Bool { completedAt != nil }

    /// Estimated one-rep max (Epley).
    var estimatedOneRepMax: Double {
        guard reps > 0 else { return 0 }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }
}

/// Overnight HRV typed in by the user, for watches (like Garmin) that don't
/// share HRV with Apple Health. One reading per morning.
@Model
final class HRVReading {
    /// Start of the day the reading belongs to (the morning after the night).
    var date: Date
    var milliseconds: Double
    var source: String

    init(date: Date, milliseconds: Double, source: String = "Garmin") {
        self.date = Calendar.current.startOfDay(for: date)
        self.milliseconds = milliseconds
        self.source = source
    }
}

nonisolated enum WorkoutSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [WorkoutSession.self, ExerciseLog.self, SetLog.self, HRVReading.self]
    }
}

nonisolated enum WorkoutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [WorkoutSchema.self] }
    static var stages: [MigrationStage] { [] }
}
