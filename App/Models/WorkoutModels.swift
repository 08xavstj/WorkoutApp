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
    /// The workout another device (Apple Watch, Garmin) recorded for this same
    /// session in Apple Health, found by `WorkoutLinker`; nil until matched.
    var linkedWorkoutUUID: UUID?
    var linkedWorkoutSource: String?
    /// The HKWorkout the Tensile Watch app saved for this session (`WatchSync`):
    /// when set, the Watch's workout is the Health record and the phone saves none.
    var watchWorkoutUUID: UUID?

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

    /// Working sets without drop stages and mini-sets: a drop, rest-pause or
    /// myo-rep set counts as one effortful set for session effort and strain,
    /// not three (feature spec §3.3). Their reps still count in the volume.
    var effortSets: [SetLog] {
        workingSets.filter { !$0.kind.isStage }
    }

    var totalVolumeKg: Double {
        workingSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    /// The summary the strain calculator works on.
    var strainSummary: StrengthSessionSummary {
        StrengthSessionSummary(
            name: name,
            start: startedAt,
            end: endedAt ?? .now,
            sessionRPE: sessionRPE.map(Double.init),
            setRPEs: effortSets.compactMap(\.rpe),
            workingSets: effortSets.count,
            totalVolumeKg: totalVolumeKg,
            linkedWorkoutUUID: linkedWorkoutUUID,
            linkedWorkoutSource: linkedWorkoutSource
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
    /// The set type (`SetKind`: drop, rest-pause, myo-rep, failure) as its raw
    /// value; nil for a straight set, so sets logged before set types existed
    /// read as straight. Added in schema 1.3.0.
    var setKindRaw: String?

    init(order: Int, weightKg: Double = 0, reps: Int = 0, rpe: Double? = nil, isWarmup: Bool = false,
         kind: SetKind = .straight) {
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.setKindRaw = kind == .straight ? nil : kind.rawValue
    }

    var isCompleted: Bool { completedAt != nil }

    /// Straight, a drop stage or mini-set that continues the set before it, or to failure.
    var kind: SetKind {
        get { SetKind(storedValue: setKindRaw) }
        set { setKindRaw = newValue == .straight ? nil : newValue.rawValue }
    }

    /// Estimated one-rep max (Epley, counting reps left from the set's RPE).
    var estimatedOneRepMax: Double {
        OneRepMax.estimate(weight: weightKg, reps: reps, rpe: rpe)
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

// Each schema version must describe the models exactly as they were stored
// in that version. Versions that point at the same live classes get identical
// checksums and SwiftData aborts at launch ("Duplicate version checksums
// detected"). So 1.0.0 and 1.1.0 use frozen copies of the workout models from
// before 1.2.0 (below), 1.2.0 its own frozen copies from before 1.3.0, and
// only the current version (1.3.0) uses the live classes.

nonisolated enum WorkoutSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [WorkoutSchemaV2.WorkoutSession.self, WorkoutSchemaV2.ExerciseLog.self,
         WorkoutSchemaV2.SetLog.self, WorkoutSchemaV2.HRVReading.self]
    }
}

/// Adds custom workout templates. Existing models are unchanged, so the
/// move from 1.0.0 is a lightweight migration.
nonisolated enum WorkoutSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 1, 0)
    static var models: [any PersistentModel.Type] {
        WorkoutSchema.models + [WorkoutTemplate.self, TemplateExercise.self]
    }

    // Frozen: the workout models as stored in 1.0.0 and 1.1.0. Don't edit
    // these; change the live classes and add a new schema version instead.

    @Model
    final class WorkoutSession {
        var startedAt: Date
        var endedAt: Date?
        var name: String
        var sessionRPE: Int?
        var notes: String
        var savedToHealth: Bool

        @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
        var exercises: [ExerciseLog] = []

        init(name: String, startedAt: Date) {
            self.name = name
            self.startedAt = startedAt
            self.notes = ""
            self.savedToHealth = false
        }
    }

    @Model
    final class ExerciseLog {
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
    }

    @Model
    final class SetLog {
        var order: Int
        var weightKg: Double
        var reps: Int
        var rpe: Double?
        var isWarmup: Bool
        var completedAt: Date?
        var exercise: ExerciseLog?

        init(order: Int, weightKg: Double, reps: Int, rpe: Double?, isWarmup: Bool) {
            self.order = order
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
        }
    }

    @Model
    final class HRVReading {
        var date: Date
        var milliseconds: Double
        var source: String

        init(date: Date, milliseconds: Double, source: String) {
            self.date = date
            self.milliseconds = milliseconds
            self.source = source
        }
    }
}

/// Adds the link from a session to the watch workout recorded alongside it
/// (`linkedWorkoutUUID`, `linkedWorkoutSource`) and the Tensile Watch app's own
/// workout (`watchWorkoutUUID`): optional properties on `WorkoutSession`, nil by
/// default, so another lightweight migration.
nonisolated enum WorkoutSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 2, 0)
    static var models: [any PersistentModel.Type] {
        [WorkoutSession.self, ExerciseLog.self, SetLog.self, HRVReading.self,
         WorkoutTemplate.self, TemplateExercise.self]
    }

    // Frozen: the workout models as stored in 1.2.0. Don't edit these; change
    // the live classes and add a new schema version instead. The templates
    // haven't changed since 1.1.0, so they're still the live classes.

    @Model
    final class WorkoutSession {
        var startedAt: Date
        var endedAt: Date?
        var name: String
        var sessionRPE: Int?
        var notes: String
        var savedToHealth: Bool
        var linkedWorkoutUUID: UUID?
        var linkedWorkoutSource: String?
        var watchWorkoutUUID: UUID?

        @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
        var exercises: [ExerciseLog] = []

        init(name: String, startedAt: Date) {
            self.name = name
            self.startedAt = startedAt
            self.notes = ""
            self.savedToHealth = false
        }
    }

    @Model
    final class ExerciseLog {
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
    }

    @Model
    final class SetLog {
        var order: Int
        var weightKg: Double
        var reps: Int
        var rpe: Double?
        var isWarmup: Bool
        var completedAt: Date?
        var exercise: ExerciseLog?

        init(order: Int, weightKg: Double, reps: Int, rpe: Double?, isWarmup: Bool) {
            self.order = order
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
        }
    }

    @Model
    final class HRVReading {
        var date: Date
        var milliseconds: Double
        var source: String

        init(date: Date, milliseconds: Double, source: String) {
            self.date = date
            self.milliseconds = milliseconds
            self.source = source
        }
    }
}

/// Adds set types (`SetLog.setKindRaw`: drop, rest-pause, myo-rep, failure):
/// an optional property on `SetLog`, nil (a straight set) by default, so
/// another lightweight migration.
nonisolated enum WorkoutSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 3, 0)
    static var models: [any PersistentModel.Type] {
        [WorkoutSession.self, ExerciseLog.self, SetLog.self, HRVReading.self,
         WorkoutTemplate.self, TemplateExercise.self]
    }
}

nonisolated enum WorkoutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WorkoutSchema.self, WorkoutSchemaV2.self, WorkoutSchemaV3.self, WorkoutSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: WorkoutSchema.self, toVersion: WorkoutSchemaV2.self),
            .lightweight(fromVersion: WorkoutSchemaV2.self, toVersion: WorkoutSchemaV3.self),
            .lightweight(fromVersion: WorkoutSchemaV3.self, toVersion: WorkoutSchemaV4.self)
        ]
    }
}
