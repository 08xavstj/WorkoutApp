import Foundation
import AppCore

/// Everything the AI coach is allowed to know, as plain values. Built on the
/// main actor, then handed to the model (on-device tools or the cloud function).
nonisolated struct CoachSnapshot: Codable, Sendable, Equatable {
    nonisolated struct Workout: Codable, Sendable, Equatable {
        var date: Date
        var name: String
        var minutes: Int
        var sessionRPE: Int?
        var workingSets: Int
        var volume: String
        /// e.g. "Bench Press: best 100 kg x 5"
        var highlights: [String]
    }

    var date: Date
    var weightUnit: String
    var strain: Double?
    var targetStrain: String?
    var cardioLoad: Double?
    var liftingLoad: Double?
    var zoneMinutes: [Int]?
    var yesterdayStrain: Double?
    var recovery: Int?
    var recoveryCalibrated: Bool?
    var hrv: Double?
    var hrvChangePercent: Double?
    var restingHeartRate: Double?
    var restingHeartRateChange: Double?
    var sleepScore: Int?
    var sleepHours: Double?
    var sleepNeedHours: Double?
    var deepHours: Double?
    var remHours: Double?
    var sleepInterruptions: Int?
    var bodyMassKg: Double?
    var proteinTargetGrams: Double?
    var nutritionToday: Nutrition?
    var nutritionYesterday: Nutrition?
    var recentWorkouts: [Workout]
    /// Equipment, plates and increments the user has.
    var gym: String?
    /// The trainer's planned session for today, if one was built.
    var suggestedWorkout: String?
    var caloriesBurnedSoFar: Double?
    var caloriesProjected: Double?
    var calorieBalance: Double?

    /// Food totals from Apple Health (logged in Cronometer or another food app).
    nonisolated struct Nutrition: Codable, Sendable, Equatable {
        var calories: Double?
        var proteinGrams: Double?
        var carbsGrams: Double?
        var fatGrams: Double?
        var fiberGrams: Double?
        var waterLiters: Double?

        init?(_ day: NutritionDay?) {
            guard let day, !day.isEmpty else { return nil }
            calories = day.calories
            proteinGrams = day.proteinGrams
            carbsGrams = day.carbsGrams
            fatGrams = day.fatGrams
            fiberGrams = day.fiberGrams
            waterLiters = day.waterLiters
        }

        var summary: String {
            func g(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) g" } ?? "n/a" }
            let kcal = calories.map { "\(Int($0.rounded())) kcal" } ?? "n/a kcal"
            return "\(kcal), protein \(g(proteinGrams)), carbs \(g(carbsGrams)), fat \(g(fatGrams)), fiber \(g(fiberGrams))"
        }
    }

    /// Human-readable summary of today's scores.
    var todaySummary: String {
        func fmt(_ value: Double?, _ digits: Int = 1) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(digits))) } ?? "n/a"
        }
        var lines: [String] = []
        lines.append("Date: \(date.formatted(date: .complete, time: .omitted))")
        lines.append("Strain today: \(fmt(strain)) / 21 (target \(targetStrain ?? "n/a")). Cardio load \(fmt(cardioLoad, 0)), lifting load \(fmt(liftingLoad, 0)).")
        if let zoneMinutes {
            lines.append("Heart-rate zone minutes (Z1-Z5): \(zoneMinutes.map(String.init).joined(separator: ", ")).")
        }
        lines.append("Yesterday's strain: \(fmt(yesterdayStrain)).")
        let calibration = recoveryCalibrated == false ? " (still building a baseline - treat as rough)" : ""
        lines.append("Recovery: \(recovery.map { "\($0)%" } ?? "n/a")\(calibration).")
        if hrv == nil {
            lines.append("HRV is not available today (Garmin doesn't share it with Apple Health), so recovery uses resting heart rate and sleep.")
        }
        lines.append("HRV: \(fmt(hrv, 0)) ms (\(fmt(hrvChangePercent, 0))% vs baseline). Resting HR: \(fmt(restingHeartRate, 0)) bpm (\(fmt(restingHeartRateChange)) vs baseline).")
        let target = proteinTargetGrams.map { " (protein target \(Int($0)) g)" } ?? ""
        lines.append("Food today so far: \(nutritionToday?.summary ?? "nothing logged")\(target).")
        if let caloriesProjected {
            let balance = calorieBalance.map { $0 < 0 ? "deficit of \(Int(-$0))" : "surplus of \(Int($0))" } ?? "unknown balance"
            lines.append("Calories burned so far: \(Int(caloriesBurnedSoFar ?? 0)), projected for today: \(Int(caloriesProjected)) (\(balance) kcal vs food logged).")
        }
        lines.append("Food yesterday: \(nutritionYesterday?.summary ?? "nothing logged").")
        if let bodyMassKg {
            lines.append("Body weight: \(bodyMassKg.formatted(.number.precision(.fractionLength(1)))) kg.")
        }
        lines.append("Sleep: score \(sleepScore.map(String.init) ?? "n/a"), \(fmt(sleepHours)) h asleep of \(fmt(sleepNeedHours)) h needed, deep \(fmt(deepHours)) h, REM \(fmt(remHours)) h, \(sleepInterruptions.map(String.init) ?? "n/a") interruptions.")
        return lines.joined(separator: "\n")
    }

    static func describe(_ plan: PlannedWorkout) -> String {
        let lines = plan.exercises.map { exercise in
            let load = exercise.load.map { " at \($0.formatted(.number.precision(.fractionLength(0...2)))) \(plan.unit.rawValue)" } ?? ""
            return "- \(exercise.name): \(exercise.sets) x \(exercise.reps.lowerBound)-\(exercise.reps.upperBound) @ RPE \(exercise.rpe.formatted())\(load)"
        }
        return (["\(plan.title), about \(WorkoutPlanner.estimatedMinutes(plan.exercises)) min:"] + lines).joined(separator: "\n")
    }

    var trainerSummary: String {
        var parts: [String] = []
        if let gym { parts.append(gym) }
        if let suggestedWorkout { parts.append("Suggested session (weights already rounded to the user's plates/dumbbells):\n\(suggestedWorkout)") }
        return parts.isEmpty ? "No gym set up yet." : parts.joined(separator: "\n")
    }

    var workoutsSummary: String {
        guard !recentWorkouts.isEmpty else { return "No gym sessions logged in the last 14 days." }
        return recentWorkouts.map { workout in
            let rpe = workout.sessionRPE.map { ", RPE \($0)" } ?? ""
            let header = "\(workout.date.formatted(date: .abbreviated, time: .omitted)) - \(workout.name): \(workout.minutes) min\(rpe), \(workout.workingSets) working sets, volume \(workout.volume) \(weightUnit)"
            return ([header] + workout.highlights.map { "  - \($0)" }).joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

extension CoachSnapshot {
    @MainActor
    static func make(
        metrics: DailyMetricsModel,
        sessions: [WorkoutSession],
        unit: WeightUnit,
        gymSummary: String? = nil,
        plan: PlannedWorkout? = nil,
        now: Date = .now
    ) -> CoachSnapshot {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let workouts = sessions
            .filter { !$0.isActive && $0.startedAt >= cutoff }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(12)
            .map { session in
                Workout(
                    date: session.startedAt,
                    name: session.name,
                    minutes: Int(session.duration / 60),
                    sessionRPE: session.sessionRPE,
                    workingSets: session.workingSets.count,
                    volume: unit.format(session.totalVolumeKg),
                    highlights: session.orderedExercises.compactMap { exercise in
                        let best = exercise.sets
                            .filter { $0.isCompleted && !$0.isWarmup }
                            .max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }
                        guard let best else { return nil }
                        return "\(exercise.name): best \(unit.format(best.weightKg)) \(unit.rawValue) x \(best.reps)"
                    }
                )
            }

        let hours: (TimeInterval?) -> Double? = { $0.map { $0 / 3600 } }
        return CoachSnapshot(
            date: now,
            weightUnit: unit.rawValue,
            strain: metrics.strain?.strain,
            targetStrain: metrics.targetStrain.map { "\(Int($0.lowerBound))-\(Int($0.upperBound))" },
            cardioLoad: metrics.strain?.cardioLoad,
            liftingLoad: metrics.strain?.liftingLoad,
            zoneMinutes: metrics.strain?.zoneMinutes.map { Int($0.rounded()) },
            yesterdayStrain: metrics.yesterdayStrain,
            recovery: metrics.recovery?.score,
            recoveryCalibrated: metrics.recovery?.isCalibrated,
            hrv: metrics.hrv,
            hrvChangePercent: metrics.recovery?.hrvChangePercent,
            restingHeartRate: metrics.restingHeartRate,
            restingHeartRateChange: metrics.recovery?.restingHeartRateChange,
            sleepScore: metrics.sleep?.score,
            sleepHours: hours(metrics.sleep?.asleep),
            sleepNeedHours: hours(metrics.sleep?.need),
            deepHours: hours(metrics.sleep?.deep),
            remHours: hours(metrics.sleep?.rem),
            sleepInterruptions: metrics.sleep?.interruptions,
            bodyMassKg: metrics.bodyMassKg,
            proteinTargetGrams: metrics.proteinTarget,
            nutritionToday: Nutrition(metrics.nutritionToday),
            nutritionYesterday: Nutrition(metrics.nutritionYesterday),
            recentWorkouts: Array(workouts),
            gym: gymSummary,
            suggestedWorkout: plan.map(Self.describe),
            caloriesBurnedSoFar: metrics.energy?.burnedSoFar,
            caloriesProjected: metrics.energy?.projectedTotal,
            calorieBalance: metrics.energy?.balance
        )
    }
}
