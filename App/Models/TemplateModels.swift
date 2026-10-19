import Foundation
import SwiftData
import AppCore

/// A workout you built yourself and can start again. Weights in kilograms.
@Model
final class WorkoutTemplate {
    var name: String
    var createdAt: Date
    var lastUsedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    var orderedExercises: [TemplateExercise] {
        exercises.sorted { $0.order < $1.order }
    }
}

@Model
final class TemplateExercise {
    /// Matches `Exercise.id` in the bundled exercise library.
    var exerciseID: String
    var name: String
    var order: Int
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
    /// Target effort (RPE on the reps-left scale); nil = the default of 8.
    var targetRPE: Double?
    /// A weight you chose yourself; nil = suggested from your history.
    var weightKg: Double?
    var template: WorkoutTemplate?

    init(exerciseID: String, name: String, order: Int, sets: Int = 3, repsLow: Int = 8, repsHigh: Int = 12,
         targetRPE: Double? = nil, weightKg: Double? = nil) {
        self.exerciseID = exerciseID
        self.name = name
        self.order = order
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = max(repsLow, repsHigh)
        self.targetRPE = targetRPE
        self.weightKg = weightKg
    }

    var reps: ClosedRange<Int> { min(repsLow, repsHigh)...max(repsLow, repsHigh) }
}

extension WorkoutTemplate {
    /// A template from a logged session: same exercises in the same order, with
    /// its working-set count, rep range and average effort. Weights are left to
    /// the suggestions so they progress.
    static func from(_ session: WorkoutSession, in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: session.name)
        context.insert(template)
        for (order, exercise) in session.orderedExercises.enumerated() {
            let working = exercise.orderedSets.filter { !$0.isWarmup }
            let done = working.filter { $0.reps > 0 }
            let reps = done.map(\.reps)
            let rpes = done.compactMap(\.rpe)
            let averageRPE = rpes.isEmpty ? nil : ((rpes.reduce(0, +) / Double(rpes.count)) * 2).rounded() / 2
            let item = TemplateExercise(
                exerciseID: exercise.exerciseID, name: exercise.name, order: order,
                sets: max(1, working.count),
                repsLow: reps.min() ?? 8, repsHigh: reps.max() ?? 12,
                targetRPE: averageRPE
            )
            item.template = template
            context.insert(item)
        }
        try? context.save()
        return template
    }
}
