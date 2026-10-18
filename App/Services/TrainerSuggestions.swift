import Foundation
import AppCore

/// Workout options that would close today's strain gap, and the coaching line.
enum TrainerSuggestions {
    struct Suggestion: Identifiable, Equatable {
        var option: StrainPlanner.Option
        var focus: WorkoutFocus?
        var minutes: Int
        var id: String { option.id }
    }

    @MainActor
    static func make(metrics: DailyMetricsModel, settings: UserSettings, sessions: [WorkoutSession]) -> [Suggestion] {
        let planner = StrainPlanner()
        let focus = WorkoutPlanner.suggestedFocus(recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions))
        let rpe = WorkoutPlanner.targetRPE(recovery: metrics.recovery?.score)
        let profile = metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)
        var options: [StrainPlanner.Option] = []
        for minutes in [30, 45, 60] {
            options.append(StrainPlanner.Option(
                id: "strength-\(minutes)", kind: .strength, title: focus.title,
                detail: "\(minutes) min · Strength", minutes: Double(minutes),
                load: planner.liftingLoad(minutes: Double(minutes), rpe: rpe)
            ))
        }
        for minutes in [20, 30, 45] {
            options.append(StrainPlanner.Option(
                id: "cardio-\(minutes)", kind: .cardio, title: "Zone 2 ride",
                detail: "\(minutes) min · Cardio", minutes: Double(minutes),
                load: planner.cardioLoad(minutes: Double(minutes), reserveFraction: 0.65, profile: profile)
            ))
        }
        let current = metrics.strain?.strain ?? 0
        let target = metrics.targetStrain ?? 10...14
        let ranked = planner.rank(options, current: current, target: target)
        let bestStrength = ranked.first { $0.kind == .strength }
        let bestCardio = ranked.first { $0.kind == .cardio }
        return ranked
            .filter { $0.id == bestStrength?.id || $0.id == bestCardio?.id }
            .map { option in
                Suggestion(option: option, focus: option.kind == .strength ? focus : nil, minutes: Int(option.minutes))
            }
    }

    /// One or two sentences for the coaching line under the rings.
    @MainActor
    static func coachingLine(metrics: DailyMetricsModel) -> (text: String, highlight: String?) {
        guard let recovery = metrics.recovery else {
            return ("Wear your watch to sleep tonight to get recovery and daily coaching.", nil)
        }
        let target = StrainCalculator.targetStrain(forRecovery: recovery.score)
        let range = "\(Int(target.lowerBound))–\(Int(target.upperBound))%"
        let sleptWell = (metrics.sleep?.score ?? 80) >= 75
        switch recovery.status {
        case .high:
            return (sleptWell ? "Recovery is high and you slept well. Push today:" : "Recovery is high. Push today, but get to bed on time:", "aim for strain \(range).")
        case .moderate:
            return (sleptWell ? "Recovery is moderate. Train, but keep the effort controlled:" : "Recovery is moderate and sleep was short. Keep it controlled:", "aim for strain \(range).")
        case .low:
            return ("Your body needs extra care. Keep it light and prioritise sleep:", "stay under \(Int(target.upperBound))% strain.")
        }
    }
}
