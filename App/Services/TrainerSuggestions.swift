import Foundation
import AppCore

/// Workout options that fit today's strain range, and the coaching line.
enum TrainerSuggestions {
    struct Suggestion: Identifiable, Equatable {
        var option: StrainPlanner.Option
        var focus: WorkoutFocus?
        var minutes: Int
        /// Lands inside today's range. False only for the planned session or,
        /// when nothing fits, the closest option.
        var fits: Bool = true
        var id: String { option.id }
    }

    /// With a session planned today (`planned`), that session (its focus and
    /// length) comes first, so the Strain sheet agrees with Today's Start
    /// button; the best-fitting easy cardio follows.
    @MainActor
    static func make(metrics: DailyMetricsModel, settings: UserSettings, sessions: [WorkoutSession],
                     planned: PlannedDay? = nil) -> [Suggestion] {
        let planner = StrainPlanner()
        let focus = WorkoutPlanner.suggestedFocus(recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions))
        let rpe = WorkoutPlanner.targetRPE(recovery: metrics.recoveryForTraining)
        let profile = metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)
        var options: [StrainPlanner.Option] = []
        for minutes in [30, 45, 60] {
            options.append(StrainPlanner.Option(
                id: "strength-\(minutes)", kind: .strength, title: focus.title,
                detail: "\(minutes) min · Strength", minutes: Double(minutes),
                load: planner.liftingLoad(minutes: Double(minutes), rpe: rpe)
            ))
        }
        // Up to 75 min, so an easy day with a higher range still has a ride that reaches it.
        for minutes in [20, 30, 45, 60, 75] {
            options.append(StrainPlanner.Option(
                id: "cardio-\(minutes)", kind: .cardio, title: "Easy ride",
                detail: "\(minutes) min · conversational pace", minutes: Double(minutes),
                load: planner.cardioLoad(minutes: Double(minutes), reserveFraction: 0.65, profile: profile)
            ))
        }
        if let planned {
            options.append(StrainPlanner.Option(
                id: "planned-\(planned.minutes)", kind: .strength, title: planned.focus.title,
                detail: "\(planned.minutes) min · Planned today", minutes: Double(planned.minutes),
                load: planner.liftingLoad(minutes: Double(planned.minutes), rpe: rpe)
            ))
        }
        let current = metrics.strain?.strain ?? 0
        let target = metrics.targetStrain ?? StrainCalculator.targetStrain(forRecovery: 50)
        let ranked = planner.rank(options, current: current, target: target)
        // Only options that end inside the range are offered as fitting it.
        let fitting = ranked.filter { target.contains($0.landsAt) }
        if let planned, let plannedOption = ranked.first(where: { $0.id.hasPrefix("planned-") }) {
            let cardio = fitting.first { $0.kind == .cardio }.map { [Suggestion(option: $0, focus: nil, minutes: Int($0.minutes))] } ?? []
            return [Suggestion(option: plannedOption, focus: planned.focus, minutes: planned.minutes,
                               fits: target.contains(plannedOption.landsAt))] + cardio
        }
        let pool = fitting.filter { !$0.id.hasPrefix("planned-") }
        guard !pool.isEmpty else {
            // Nothing lands inside: the closest strength option, marked as not fitting.
            guard let closest = ranked.first(where: { $0.kind == .strength }) else { return [] }
            return [Suggestion(option: closest, focus: focus, minutes: Int(closest.minutes), fits: false)]
        }
        let bestStrength = pool.first { $0.kind == .strength }
        let bestCardio = pool.first { $0.kind == .cardio }
        return pool
            .filter { $0.id == bestStrength?.id || $0.id == bestCardio?.id }
            .map { option in
                Suggestion(option: option, focus: option.kind == .strength ? focus : nil, minutes: Int(option.minutes))
            }
    }

    /// One or two sentences for the coaching line under the rings.
    ///
    /// Autonomy-supportive: the reason, then options the user chooses between,
    /// with the range as information. No "push", no "your body needs extra
    /// care": a good recovery is not a reason to train harder than planned,
    /// and a low one is an easy day, not a failure (Teixeira et al. 2020;
    /// Ntoumanis et al. 2021; docs/research/behaviour-change.md rec. 5).
    @MainActor
    static func coachingLine(metrics: DailyMetricsModel) -> (text: String, highlight: String?) {
        if metrics.restMode {
            return ("Rest mode is on, so there's no strain range today. Sleep, fluids and an easy walk if you feel up to it.", nil)
        }
        guard let recovery = metrics.recovery else {
            return ("Wear your watch to sleep tonight to get recovery and daily coaching.", nil)
        }
        guard let target = metrics.targetStrain else { return ("", nil) }
        let range = strainRangeText(target)
        let upper = strainText(target.upperBound)
        // The weekly plan's rest, recovery and make-up days speak for themselves
        // (`TrainingDayPlanner`); planned training days keep the lines below.
        if let guidance = metrics.dayGuidance {
            switch guidance.kind {
            case .rest, .recovery:
                return (guidance.reason, "Anything up to \(upper) strain is fine today.")
            case .makeUp:
                return (guidance.reason, "Your range is \(range).")
            case .easyTraining where !metrics.trainEasyToday:
                return (guidance.reason, "Anything under \(upper) strain is fine.")
            case .training, .easyTraining:
                break
            }
        }
        if metrics.trainEasyToday, let trend = recovery.hrvTrend {
            return ("Your 7-day HRV (\(Int(trend.average.rounded())) ms) is below your normal range (\(Int(trend.normalRange.lowerBound.rounded()))–\(Int(trend.normalRange.upperBound.rounded())) ms), so today suits an easy session: technique work, mobility or a Zone 2 ride, whichever you prefer,",
                    "anything under \(upper) strain is fine.")
        }
        let sleptWell = (metrics.sleep?.score ?? 80) >= 75
        switch recovery.status {
        case .high:
            return (sleptWell ? "You're recovered and slept well, so today fits your planned session:" : "You're recovered, though sleep was short. Train as planned and get to bed on time:", "your range is \(range).")
        case .moderate:
            return (sleptWell ? "Recovery is normal. A planned session or an easier one both fit; keep the effort controlled:" : "Recovery is normal and sleep was short. A controlled session or an easy day both fit:", "your range is \(range).")
        case .low:
            return ("Easy day: \(lowRecoveryCause(recovery.contributors)), so a light session or a walk suits today, and an early night helps:", "anything under \(upper) strain is fine.")
        }
    }

    /// Why recovery is low, from the inputs that were there and pulled it
    /// down (`RecoveryContributor`), so a sleep-only score doesn't blame HRV.
    static func lowRecoveryCause(_ contributors: [RecoveryContributor]) -> String {
        let lowering = Set(contributors.filter { $0.effect == .lowers }.map(\.id))
        let hrv = !lowering.isDisjoint(with: ["hrv", "hrvTrend"])
        let rhr = lowering.contains("rhr")
        if hrv && rhr { return "HRV and resting heart rate are off your normal" }
        if hrv { return "HRV is below your normal" }
        if rhr { return "resting heart rate is above your normal" }
        if lowering.contains("sleep") { return "last night's sleep was below your usual" }
        return "recovery is low"
    }
}
